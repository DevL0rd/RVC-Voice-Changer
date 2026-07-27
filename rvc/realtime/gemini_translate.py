"""Background audio bridge for Gemini Live Translate."""

from __future__ import annotations

import asyncio
import queue
import threading
import time
from collections import deque
from collections.abc import Callable
from contextlib import suppress
from typing import Any

import numpy as np
import soxr


MODEL = "gemini-3.5-live-translate-preview"
INPUT_SAMPLE_RATE = 16_000
OUTPUT_SAMPLE_RATE = 24_000
INPUT_CHUNK_FRAMES = 1_600  # The API recommends 100 ms chunks.


class GeminiLiveTranslator:
    """Stream float32 mono audio to Gemini without blocking the audio thread."""

    def __init__(
        self,
        api_key: str,
        target_language: str,
        echo_target_language: bool,
        sample_rate: int,
        status_callback: Callable[[str, str], None] | None = None,
    ) -> None:
        self.api_key = api_key.strip()
        self.target_language = target_language
        self.echo_target_language = echo_target_language
        self.sample_rate = sample_rate
        self.status_callback = status_callback

        self.status = "disabled"
        self.error = ""
        self.latency_ms = 0.0
        self._input_queue: queue.Queue[np.ndarray] = queue.Queue(maxsize=24)
        self._output_chunks: deque[np.ndarray] = deque()
        self._output_offset = 0
        self._output_frames = 0
        self._output_lock = threading.Lock()
        self._stop_event = threading.Event()
        self._thread: threading.Thread | None = None
        self._loop: asyncio.AbstractEventLoop | None = None
        self._main_task: asyncio.Task[None] | None = None
        self._async_lock = threading.Lock()
        self._latency_lock = threading.Lock()
        self._sent_speech_times: deque[float] = deque(maxlen=100)
        self._latency_output_frames = 0
        self._last_speech_sent_at = 0.0

    def start(self) -> None:
        if not self.api_key:
            raise RuntimeError("Save a Gemini API key before enabling live translation")
        try:
            from google import genai as _genai  # noqa: F401
            from google.genai import types as _types  # noqa: F401
        except ImportError as error:
            raise RuntimeError(
                "Gemini live translation requires the google-genai package; run install.sh"
            ) from error
        if self._thread and self._thread.is_alive():
            return

        self._stop_event.clear()
        self._set_status("connecting")
        self._thread = threading.Thread(
            target=self._thread_main,
            name="gemini-live-translate",
            daemon=True,
        )
        self._thread.start()

    def stop(self) -> None:
        self._stop_event.set()
        with self._async_lock:
            loop = self._loop
            task = self._main_task
        if loop and task and not loop.is_closed():
            loop.call_soon_threadsafe(task.cancel)
        if self._thread and self._thread is not threading.current_thread():
            self._thread.join(timeout=3)
        self._thread = None
        self._clear_input()
        self._clear_output()
        self._set_status("disabled")

    def send(self, audio: np.ndarray) -> None:
        """Queue a converted audio block, dropping stale input instead of blocking."""
        if self._stop_event.is_set() or self.status == "disabled":
            return
        block = np.asarray(audio, dtype=np.float32).reshape(-1).copy()
        try:
            self._input_queue.put_nowait(block)
        except queue.Full:
            with suppress(queue.Empty):
                self._input_queue.get_nowait()
            with suppress(queue.Full):
                self._input_queue.put_nowait(block)

    def read(self, frame_count: int) -> np.ndarray | None:
        """Return exactly one playback block, silence on underrun, or None on error."""
        if frame_count <= 0:
            return np.empty(0, dtype=np.float32)
        with self._output_lock:
            if self._output_frames == 0 and self.status in {
                "error",
                "disabled",
                "reconnecting",
            }:
                return None
            output = np.zeros(frame_count, dtype=np.float32)
            written = 0
            while written < frame_count and self._output_chunks:
                chunk = self._output_chunks[0]
                available = len(chunk) - self._output_offset
                copied = min(frame_count - written, available)
                output[written : written + copied] = chunk[
                    self._output_offset : self._output_offset + copied
                ]
                written += copied
                self._output_offset += copied
                self._output_frames -= copied
                if self._output_offset == len(chunk):
                    self._output_chunks.popleft()
                    self._output_offset = 0
            return output

    def _thread_main(self) -> None:
        loop = asyncio.new_event_loop()
        asyncio.set_event_loop(loop)
        task = loop.create_task(self._run_forever())
        with self._async_lock:
            self._loop = loop
            self._main_task = task
        try:
            loop.run_until_complete(task)
        except asyncio.CancelledError:
            pass
        except Exception as error:
            self._set_status("error", self._safe_error(error))
        finally:
            with self._async_lock:
                self._main_task = None
                self._loop = None
            loop.run_until_complete(loop.shutdown_asyncgens())
            loop.close()

    async def _run_forever(self) -> None:
        delay = 1.0
        first_attempt = True
        while not self._stop_event.is_set():
            self._set_status("connecting" if first_attempt else "reconnecting")
            try:
                await self._run_session()
                if not self._stop_event.is_set():
                    raise RuntimeError("Gemini closed the live translation session")
            except asyncio.CancelledError:
                raise
            except Exception as error:
                self._clear_input()
                self._clear_output()
                self._set_status("error", self._safe_error(error))
                await asyncio.sleep(delay)
                delay = min(30.0, delay * 2.0)
                first_attempt = False

    async def _run_session(self) -> None:
        from google import genai
        from google.genai import types

        client = genai.Client(api_key=self.api_key)
        config = types.LiveConnectConfig(
            response_modalities=["AUDIO"],
            translation_config=types.TranslationConfig(
                target_language_code=self.target_language,
                echo_target_language=self.echo_target_language,
            ),
        )
        try:
            async with client.aio.live.connect(model=MODEL, config=config) as session:
                self._set_status("running")
                await asyncio.gather(
                    self._send_audio(session, types),
                    self._receive_audio(session),
                )
        finally:
            with suppress(Exception):
                await client.aio.aclose()

    async def _send_audio(self, session: Any, types: Any) -> None:
        resampler = soxr.ResampleStream(
            self.sample_rate,
            INPUT_SAMPLE_RATE,
            1,
            dtype="float32",
            quality="HQ",
        )
        pending = np.empty(0, dtype=np.float32)
        try:
            while not self._stop_event.is_set():
                try:
                    block = self._input_queue.get_nowait()
                except queue.Empty:
                    await asyncio.sleep(0.01)
                    continue
                resampled = resampler.resample_chunk(block)
                pending = np.concatenate((pending, resampled))
                while len(pending) >= INPUT_CHUNK_FRAMES:
                    chunk = pending[:INPUT_CHUNK_FRAMES]
                    pending = pending[INPUT_CHUNK_FRAMES:]
                    pcm = (np.clip(chunk, -1.0, 1.0) * 32767.0).astype("<i2").tobytes()
                    if float(np.max(np.abs(chunk), initial=0.0)) > 0.003:
                        sent_at = time.perf_counter()
                        with self._latency_lock:
                            if sent_at - self._last_speech_sent_at > 1.0:
                                self._sent_speech_times.clear()
                                self._latency_output_frames = 0
                            self._sent_speech_times.append(sent_at)
                            self._last_speech_sent_at = sent_at
                    await session.send_realtime_input(
                        audio=types.Blob(
                            data=pcm,
                            mime_type=f"audio/pcm;rate={INPUT_SAMPLE_RATE}",
                        )
                    )
        finally:
            with suppress(Exception):
                await session.send_realtime_input(audio_stream_end=True)

    async def _receive_audio(self, session: Any) -> None:
        resampler = soxr.ResampleStream(
            OUTPUT_SAMPLE_RATE,
            self.sample_rate,
            1,
            dtype="float32",
            quality="HQ",
        )
        while not self._stop_event.is_set():
            received = False
            async for response in session.receive():
                received = True
                server_content = response.server_content
                if not server_content:
                    continue
                if server_content.interrupted:
                    self._clear_output()
                model_turn = server_content.model_turn
                if not model_turn:
                    continue
                for part in model_turn.parts or []:
                    inline_data = part.inline_data
                    if not inline_data or not inline_data.data:
                        continue
                    pcm = np.frombuffer(inline_data.data, dtype="<i2")
                    audio = pcm.astype(np.float32) / 32768.0
                    self._record_latency(len(pcm))
                    self._append_output(resampler.resample_chunk(audio))
            if not received:
                await asyncio.sleep(0.01)

    def _append_output(self, audio: np.ndarray) -> None:
        block = np.asarray(audio, dtype=np.float32).reshape(-1)
        if not len(block):
            return
        maximum = self.sample_rate * 10
        with self._output_lock:
            self._output_chunks.append(block)
            self._output_frames += len(block)
            while self._output_frames > maximum and self._output_chunks:
                removed = self._output_chunks.popleft()
                discarded = len(removed) - self._output_offset
                self._output_frames -= discarded
                self._output_offset = 0

    def _clear_input(self) -> None:
        while True:
            try:
                self._input_queue.get_nowait()
            except queue.Empty:
                return

    def _clear_output(self) -> None:
        with self._output_lock:
            self._output_chunks.clear()
            self._output_offset = 0
            self._output_frames = 0

    def _record_latency(self, output_frames: int) -> None:
        now = time.perf_counter()
        with self._latency_lock:
            self._latency_output_frames += output_frames
            while (
                self._latency_output_frames >= OUTPUT_SAMPLE_RATE // 10
                and self._sent_speech_times
            ):
                sent_at = self._sent_speech_times.popleft()
                measured = max(0.0, (now - sent_at) * 1000.0)
                self.latency_ms = (
                    measured
                    if self.latency_ms <= 0.0
                    else self.latency_ms + 0.2 * (measured - self.latency_ms)
                )
                self._latency_output_frames -= OUTPUT_SAMPLE_RATE // 10

    def _safe_error(self, error: Exception) -> str:
        message = str(error) or error.__class__.__name__
        return message.replace(self.api_key, "***") if self.api_key else message

    def _set_status(self, status: str, error: str = "") -> None:
        changed = status != self.status or error != self.error
        self.status = status
        self.error = error
        if status in {"disabled", "error"}:
            with self._latency_lock:
                self.latency_ms = 0.0
                self._sent_speech_times.clear()
                self._latency_output_frames = 0
                self._last_speech_sent_at = 0.0
        if changed and self.status_callback:
            self.status_callback(status, error)
