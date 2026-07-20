from __future__ import annotations

import json
import math
import os
import shutil
import subprocess
import threading
import time
from contextlib import suppress
from dataclasses import asdict, dataclass, field
from typing import Any, BinaryIO, Callable

from .cable import PROCESSING_INPUT_NAME, VIRTUAL_MICROPHONE_NAME, VirtualMicrophone
from .models import VoiceModel


@dataclass
class RuntimeState:
    enabled: bool = False
    status: str = "idle"
    error: str = ""
    gpu_name: str = ""
    cuda_available: bool = False
    rocm_available: bool = False
    inference_backend: str = ""
    inference_device: str = ""
    cpu_threads: int = 0
    virtual_microphone: bool = False
    latency_ms: float = 0.0
    input_level_db: float = -100.0
    block_ms: float = 0.0
    dropped_blocks: int = 0
    profile_ms: dict[str, float] = field(default_factory=dict)
    bottleneck: str = ""
    realtime_factor: float = 0.0


class VoiceEngine:
    """Runs Applio's RVC converter on the selected accelerator or CPU."""

    def __init__(self) -> None:
        self.cable = VirtualMicrophone()
        self.state = RuntimeState()
        self._lock = threading.RLock()
        self._stop_event = threading.Event()
        self._thread: threading.Thread | None = None
        self._capture: subprocess.Popen[bytes] | None = None
        self._playbacks: list[tuple[subprocess.Popen[bytes], str]] = []
        self._converter: Any = None
        self._config: dict[str, Any] | None = None
        self._block_frames = 0
        self._event_sink: Callable[[str, str], None] | None = None
        self.refresh_gpu()

    def set_event_sink(self, sink: Callable[[str, str], None]) -> None:
        self._event_sink = sink

    def _event(self, level: str, message: str) -> None:
        if self._event_sink is not None:
            self._event_sink(level, message)

    def refresh_gpu(self) -> None:
        self.state.cuda_available = False
        self.state.rocm_available = False
        self.state.gpu_name = ""
        try:
            import torch

            self.state.cuda_available = bool(torch.cuda.is_available())
            self.state.rocm_available = bool(self.state.cuda_available and torch.version.hip)
            if self.state.cuda_available:
                self.state.gpu_name = torch.cuda.get_device_name(0)
        except Exception:
            self.state.cuda_available = False
            self.state.rocm_available = False

    def _select_device(self, config: dict[str, Any]) -> str:
        import torch

        inference = config["gpu"]
        requested = str(inference.get("backend", "auto"))
        device_index = int(inference.get("device", 0))
        self.refresh_gpu()

        if requested == "auto":
            if self.state.cuda_available:
                device_index = device_index if device_index < torch.cuda.device_count() else 0
                requested = "cuda"
            else:
                requested = "cpu"

        if requested == "cuda":
            if not self.state.cuda_available:
                raise RuntimeError("GPU inference was requested, but CUDA/ROCm PyTorch is unavailable")
            if device_index >= torch.cuda.device_count():
                raise RuntimeError(f"GPU device {device_index} does not exist")
            torch.cuda.set_device(device_index)
            self.state.gpu_name = torch.cuda.get_device_name(device_index)
            os.environ["RVC_CUDA_DEVICE"] = str(device_index)
            os.environ["RVC_DEVICE"] = f"cuda:{device_index}"
            is_rocm = bool(torch.version.hip)
            if not is_rocm:
                allow_tf32 = bool(inference.get("allow_tf32", True))
                torch.backends.cuda.matmul.allow_tf32 = allow_tf32
                torch.backends.cudnn.allow_tf32 = allow_tf32
            self.state.inference_backend = "rocm" if is_rocm else "cuda"
            self.state.inference_device = f"{self.state.gpu_name} · GPU {device_index}"
            self.state.cpu_threads = torch.get_num_threads()
            return f"cuda:{device_index}"

        logical_cpus = max(1, os.cpu_count() or 1)
        configured_threads = int(inference.get("cpu_threads", 0))
        cpu_threads = configured_threads or max(1, logical_cpus // 2)
        torch.set_num_threads(cpu_threads)
        os.environ["RVC_DEVICE"] = "cpu"
        self.state.inference_backend = "cpu"
        self.state.inference_device = f"CPU · {cpu_threads} threads"
        self.state.cpu_threads = cpu_threads
        return "cpu"

    def enable(self, model: VoiceModel | None, config: dict[str, Any]) -> None:
        with self._lock:
            self._deactivate(keep_cable=True)
            self.state.status = "loading"
            self.state.error = ""
            try:
                self._start(model, config)
            except Exception as error:
                self.fail(error)
                raise

    def _start(self, model: VoiceModel | None, config: dict[str, Any]) -> None:
        if model is None or not model.ready:
            raise RuntimeError("Select a voice folder containing an RVC .pth model")
        input_device = str(config["audio"]["input_device"])
        if not input_device:
            raise RuntimeError("Select an input microphone")
        for command in ("pw-cat", "pw-loopback"):
            if not shutil.which(command):
                raise RuntimeError(f"{command} is required for PipeWire audio")

        import torch
        from rvc.realtime.core import VoiceChanger

        self._select_device(config)

        audio = config["audio"]
        cleanup = config["cleanup"]
        sample_rate = int(audio["sample_rate"])
        requested_frames = int(sample_rate * int(audio["block_ms"]) / 1000)
        read_chunk_size = max(1, round(requested_frames / 128))
        self._block_frames = read_chunk_size * 128
        self.state.block_ms = self._block_frames * 1000.0 / sample_rate
        self._config = config

        self._prepare_cable()
        self._require_audio_source(input_device)

        self._converter = VoiceChanger(
            read_chunk_size=read_chunk_size,
            cross_fade_overlap_size=float(audio["crossfade_ms"]) / 1000.0,
            extra_convert_size=float(audio["extra_ms"]) / 1000.0,
            model_path=model.model_path,
            index_path=model.index_path or "",
            f0_method=config["model"]["f0_method"],
            embedder_model="contentvec",
            embedder_model_custom=None,
            silent_threshold=float(cleanup["noise_gate_db"]),
            vad_enabled=bool(cleanup.get("vad_enabled", False)),
            vad_sensitivity=int(cleanup.get("vad_sensitivity", 3)),
            sid=int(config["model"].get("speaker_id", 0)),
            clean_audio=bool(cleanup["noise_suppression"]),
            clean_strength=float(cleanup["noise_suppression_strength"]),
            post_process=False,
            audio_sample_rate=sample_rate,
        )

        self._stop_event.clear()
        self._capture = self._open_capture(input_device, sample_rate, self._block_frames)
        targets: list[tuple[str, str]] = [(PROCESSING_INPUT_NAME, "output")]
        monitor = str(audio.get("monitor_device") or "") if audio.get("monitor_enabled") else ""
        if monitor and monitor != PROCESSING_INPUT_NAME:
            targets.append((monitor, "monitor"))
        self._playbacks = [
            (self._open_playback(target, sample_rate, self._block_frames), role)
            for target, role in targets
        ]

        self._thread = threading.Thread(target=self._audio_loop, name="rvc-audio", daemon=True)
        self._thread.start()
        self.state.enabled = True
        self.state.status = "running"
        self._event(
            "info",
            f"Conversion started: {model.name} on {self.state.inference_device}",
        )

    def bypass(self, config: dict[str, Any]) -> None:
        """Keep the virtual microphone alive and feed it unconverted input."""
        with self._lock:
            self._deactivate(keep_cable=True)
            self.state.error = ""
            self._prepare_cable()

            audio = config["audio"]
            input_device = str(audio.get("input_device") or "")
            self._config = config
            self.state.status = "bypass"
            if not input_device:
                return
            self._require_audio_source(input_device)

            sample_rate = int(audio["sample_rate"])
            requested_frames = int(sample_rate * int(audio["block_ms"]) / 1000)
            self._block_frames = max(1, round(requested_frames / 128)) * 128
            self.state.block_ms = self._block_frames * 1000.0 / sample_rate
            self._stop_event.clear()
            self._capture = self._open_capture(input_device, sample_rate, self._block_frames)
            playback = self._open_playback(PROCESSING_INPUT_NAME, sample_rate, self._block_frames)
            self._playbacks = [(playback, "bypass")]
            self._thread = threading.Thread(target=self._bypass_loop, name="rvc-bypass", daemon=True)
            self._thread.start()
            self._event("info", "Bypass active: physical microphone is feeding RVC Virtual Microphone")

    def _bypass_loop(self) -> None:
        import numpy as np

        assert self._capture is not None and self._capture.stdout is not None
        byte_count = self._block_frames * 4
        try:
            while not self._stop_event.is_set():
                raw = self._read_exact(self._capture.stdout, byte_count)
                if len(raw) != byte_count:
                    if not self._stop_event.is_set():
                        raise RuntimeError("PipeWire input stream stopped during bypass")
                    return
                if not self._playbacks:
                    raise RuntimeError("RVC Virtual Microphone bypass stream stopped")
                playback = self._playbacks[0][0]
                if playback.poll() is not None or playback.stdin is None:
                    raise RuntimeError("RVC Virtual Microphone bypass stream stopped")
                playback.stdin.write(raw)
                playback.stdin.flush()
                samples = np.frombuffer(raw, dtype=np.float32)
                rms = math.sqrt(float(np.square(samples, dtype=np.float64).mean()))
                self.state.input_level_db = round(20.0 * math.log10(max(rms, 1e-5)), 1)
        except Exception as error:
            if not self._stop_event.is_set():
                self.state.status = "error"
                self.state.error = str(error)
                self._stop_event.set()
                self._stop_processes()
                self._event("error", f"Bypass stream failed: {error}")

    def _pw_cat_command(self, mode: str, target: str, sample_rate: int, block_frames: int) -> list[str]:
        node_name = "rvc_capture_stream" if mode == "record" else "rvc_output_stream"
        return [
            "pw-cat",
            f"--{mode}",
            "--raw",
            "--format",
            "f32",
            "--rate",
            str(sample_rate),
            "--channels",
            "1",
            "--channel-map",
            "MONO",
            "--latency",
            str(block_frames),
            "--target",
            target,
            "--properties",
            " ".join(
                (
                    "application.id=org.devl0rd.rvcvoicechanger",
                    'application.name="Linux RVC Voice Changer"',
                    f"node.name={node_name}",
                    "node.dont-reconnect=true",
                )
            ),
            "-",
        ]

    def _open_capture(self, target: str, sample_rate: int, block_frames: int) -> subprocess.Popen[bytes]:
        process = subprocess.Popen(
            self._pw_cat_command("record", target, sample_rate, block_frames),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        self._confirm_started(process, f"input {target}")
        try:
            self._confirm_capture_link(process, target)
        except Exception:
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=1)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait(timeout=1)
            for stream in (process.stdout, process.stderr):
                if stream:
                    with suppress(OSError, ValueError):
                        stream.close()
            raise
        return process

    def _open_playback(self, target: str, sample_rate: int, block_frames: int) -> subprocess.Popen[bytes]:
        process = subprocess.Popen(
            self._pw_cat_command("playback", target, sample_rate, block_frames),
            stdin=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        self._confirm_started(process, f"output {target}")
        return process

    @staticmethod
    def _confirm_started(process: subprocess.Popen[bytes], description: str) -> None:
        try:
            process.wait(timeout=0.2)
        except subprocess.TimeoutExpired:
            return
        message = process.stderr.read().decode(errors="replace").strip() if process.stderr else ""
        raise RuntimeError(message or f"PipeWire could not open {description}")

    @staticmethod
    def _read_exact(stream: BinaryIO, size: int) -> bytes:
        chunks: list[bytes] = []
        remaining = size
        while remaining:
            chunk = stream.read(remaining)
            if not chunk:
                break
            chunks.append(chunk)
            remaining -= len(chunk)
        return b"".join(chunks)

    def _audio_loop(self) -> None:
        import numpy as np
        from scipy.signal import butter, sosfilt, sosfilt_zi

        assert self._config is not None
        assert self._capture is not None and self._capture.stdout is not None
        config = self._config
        audio_cfg = config["audio"]
        cleanup = config["cleanup"]
        model = config["model"]
        sample_rate = int(audio_cfg["sample_rate"])
        byte_count = self._block_frames * 4

        filters: list[list[Any]] = []
        high_pass = int(cleanup.get("high_pass_hz", 0))
        low_pass = int(cleanup.get("low_pass_hz", 0))
        if high_pass > 0:
            sos = butter(2, high_pass, btype="highpass", fs=sample_rate, output="sos")
            filters.append([sos, sosfilt_zi(sos) * 0.0])
        if 0 < low_pass < sample_rate // 2:
            sos = butter(2, low_pass, btype="lowpass", fs=sample_rate, output="sos")
            filters.append([sos, sosfilt_zi(sos) * 0.0])

        try:
            while not self._stop_event.is_set():
                capture_started = time.perf_counter()
                raw = self._read_exact(self._capture.stdout, byte_count)
                capture_ms = (time.perf_counter() - capture_started) * 1000.0
                if len(raw) != byte_count:
                    if not self._stop_event.is_set():
                        raise RuntimeError("PipeWire input stream stopped")
                    return
                processing_started = time.perf_counter()
                preprocess_started = time.perf_counter()
                samples = np.frombuffer(raw, dtype=np.float32).copy()
                samples *= 10.0 ** (float(audio_cfg["input_gain_db"]) / 20.0)
                for filter_state in filters:
                    samples, filter_state[1] = sosfilt(filter_state[0], samples, zi=filter_state[1])
                np.clip(samples, -1.0, 1.0, out=samples)
                preprocess_ms = (time.perf_counter() - preprocess_started) * 1000.0

                inference_started = time.perf_counter()
                converted, volume = self._converter.process_audio(
                    samples,
                    f0_up_key=int(model["pitch"]),
                    index_rate=float(model["index_rate"]),
                    protect=float(model["protect"]),
                    volume_envelope=float(model["rms_mix_rate"]),
                    f0_autotune=bool(model.get("autotune", False)),
                    f0_autotune_strength=float(model.get("autotune_strength", 1.0)),
                    proposed_pitch=bool(model.get("proposed_pitch", False)),
                    proposed_pitch_threshold=float(model.get("proposed_pitch_threshold", 255.0)),
                )
                inference_ms = (time.perf_counter() - inference_started) * 1000.0
                payloads: dict[str, bytes] = {}
                alive: list[tuple[subprocess.Popen[bytes], str]] = []
                postprocess_ms = 0.0
                write_ms = 0.0
                for playback, role in self._playbacks:
                    if playback.poll() is not None or playback.stdin is None:
                        self.state.dropped_blocks += 1
                        continue
                    if role not in payloads:
                        postprocess_started = time.perf_counter()
                        gain_key = "monitor_gain_db" if role == "monitor" else "output_gain_db"
                        gained = converted * (10.0 ** (float(audio_cfg[gain_key]) / 20.0))
                        payloads[role] = np.clip(gained, -1.0, 1.0).astype(np.float32, copy=False).tobytes()
                        postprocess_ms += (time.perf_counter() - postprocess_started) * 1000.0
                    write_started = time.perf_counter()
                    playback.stdin.write(payloads[role])
                    playback.stdin.flush()
                    write_ms += (time.perf_counter() - write_started) * 1000.0
                    alive.append((playback, role))
                self._playbacks = alive
                if not self._playbacks:
                    raise RuntimeError("Every PipeWire output stream stopped")

                elapsed = (time.perf_counter() - processing_started) * 1000.0
                profile = dict(getattr(self._converter, "last_profile", {}))
                profiled_inference_ms = float(profile.get("device_total", 0.0))
                if "accelerator_total" in profile:
                    profiled_inference_ms += float(profile.get("voice_activity_detection", 0.0))
                profile.update(
                    {
                        "capture_wait": capture_ms,
                        "input_preprocess": preprocess_ms,
                        "inference_wall": inference_ms,
                        "inference_overhead": max(0.0, inference_ms - profiled_inference_ms),
                        "output_postprocess": postprocess_ms,
                        "pipewire_write": write_ms,
                        "compute_total": max(0.0, elapsed - write_ms),
                        "processing_total": elapsed,
                    }
                )
                self._update_profile(profile)
                self.state.latency_ms = round(elapsed, 1)
                self.state.input_level_db = round(20.0 * math.log10(max(float(volume), 1e-5)), 1)
        except Exception as error:
            if not self._stop_event.is_set():
                self.state.status = "error"
                self.state.error = str(error)
                self.state.enabled = False
                self._stop_event.set()
                self._stop_processes()
                self.state.virtual_microphone = self.cable.running
                self._event("error", f"Conversion stream failed: {error}")

    def _update_profile(self, sample: dict[str, float]) -> None:
        alpha = 0.2
        previous = self.state.profile_ms
        averaged = {
            key: value if key not in previous else previous[key] + alpha * (value - previous[key])
            for key, value in sample.items()
        }
        self.state.profile_ms = {key: round(value, 3) for key, value in averaged.items()}
        candidates = {
            key: value
            for key, value in averaged.items()
            if key
            not in {
                "capture_wait",
                "pipewire_write",
                "inference_wall",
                "rvc_wall_total",
                "accelerator_total",
                "cpu_total",
                "device_total",
                "compute_total",
                "processing_total",
            }
        }
        self.state.bottleneck = max(candidates, key=candidates.get, default="")
        block_ms = max(self.state.block_ms, 0.001)
        self.state.realtime_factor = round(averaged.get("compute_total", 0.0) / block_ms, 3)

    @staticmethod
    def _wait_for_node(name: str) -> None:
        deadline = time.monotonic() + 3.0
        while time.monotonic() < deadline:
            try:
                dump = subprocess.run(["pw-dump"], capture_output=True, text=True, timeout=1).stdout
                if name in dump:
                    return
            except (FileNotFoundError, subprocess.SubprocessError):
                pass
            time.sleep(0.1)
        raise RuntimeError(f"PipeWire node {name} did not appear")

    def _prepare_cable(self) -> None:
        self.cable.start()
        self._wait_for_node(PROCESSING_INPUT_NAME)
        self.state.virtual_microphone = True
        repaired = self._repair_virtual_microphone_consumers()
        if repaired:
            noun = "stream" if repaired == 1 else "streams"
            self._event(
                "warning",
                f"Reconnected {repaired} application {noun} to RVC Virtual Microphone",
            )

    @staticmethod
    def _repair_virtual_microphone_consumers() -> int:
        """Move streams that fell back while the virtual source was unavailable."""
        pactl = shutil.which("pactl")
        if not pactl:
            return 0
        try:
            source_result = subprocess.run(
                [pactl, "-f", "json", "list", "sources"],
                check=True,
                capture_output=True,
                text=True,
                timeout=3,
            )
            sources = json.loads(source_result.stdout)
            virtual_source = next(
                str(source["index"])
                for source in sources
                if source.get("name") == VIRTUAL_MICROPHONE_NAME
            )
            output_result = subprocess.run(
                [pactl, "-f", "json", "list", "source-outputs"],
                check=True,
                capture_output=True,
                text=True,
                timeout=3,
            )
            outputs = json.loads(output_result.stdout)
            stale = [
                str(output["index"])
                for output in outputs
                if (output.get("properties") or {}).get("target.object")
                == VIRTUAL_MICROPHONE_NAME
                and str(output.get("source")) != virtual_source
            ]
            for output_index in stale:
                subprocess.run(
                    [pactl, "move-source-output", output_index, VIRTUAL_MICROPHONE_NAME],
                    check=True,
                    capture_output=True,
                    timeout=3,
                )
            return len(stale)
        except (
            FileNotFoundError,
            json.JSONDecodeError,
            StopIteration,
            subprocess.SubprocessError,
            TypeError,
            ValueError,
        ):
            return 0

    @staticmethod
    def _pipewire_objects() -> list[dict[str, Any]]:
        try:
            result = subprocess.run(
                ["pw-dump"],
                check=True,
                capture_output=True,
                text=True,
                timeout=3,
            )
            objects = json.loads(result.stdout)
        except (FileNotFoundError, json.JSONDecodeError, subprocess.SubprocessError) as error:
            raise RuntimeError("Could not inspect PipeWire audio routing") from error
        if not isinstance(objects, list):
            raise RuntimeError("PipeWire returned an invalid audio graph")
        return objects

    @classmethod
    def _require_audio_source(cls, target: str) -> None:
        for item in cls._pipewire_objects():
            props = (item.get("info") or {}).get("props") or {}
            if props.get("node.name") != target:
                continue
            if str(props.get("media.class") or "").startswith("Audio/Source"):
                return
        raise RuntimeError(
            f"Selected input microphone '{target}' is unavailable; choose an available input device"
        )

    @classmethod
    def _confirm_capture_link(cls, process: subprocess.Popen[bytes], target: str) -> None:
        deadline = time.monotonic() + 1.0
        while time.monotonic() < deadline:
            objects = cls._pipewire_objects()
            nodes = {
                str((item.get("info") or {}).get("props", {}).get("node.name") or ""): item.get("id")
                for item in objects
                if item.get("type") == "PipeWire:Interface:Node"
            }
            target_id = nodes.get(target)
            capture_id = nodes.get("rvc_capture_stream")
            linked = any(
                item.get("type") == "PipeWire:Interface:Link"
                and (item.get("info") or {}).get("output-node-id") == target_id
                and (item.get("info") or {}).get("input-node-id") == capture_id
                for item in objects
            )
            if target_id is not None and capture_id is not None and linked:
                return
            if process.poll() is not None:
                break
            time.sleep(0.05)
        raise RuntimeError(f"PipeWire did not connect the selected input microphone '{target}'")

    def _deactivate(self, keep_cable: bool) -> None:
        with self._lock:
            self._stop_event.set()
            thread, self._thread = self._thread, None
            if thread and thread is not threading.current_thread():
                thread.join(timeout=3)
            self._stop_processes()
            self._converter = None
            self._config = None
            if not keep_cable:
                self.cable.stop()
            try:
                import torch

                if torch.cuda.is_available():
                    torch.cuda.empty_cache()
            except Exception:
                pass
            self.state.enabled = False
            self.state.virtual_microphone = self.cable.running
            self.state.status = "idle"
            self.state.error = ""
            self.state.latency_ms = 0.0
            self.state.input_level_db = -100.0
            self.state.profile_ms = {}
            self.state.bottleneck = ""
            self.state.realtime_factor = 0.0

    def stop_conversion(self) -> None:
        self._deactivate(keep_cable=True)

    def shutdown(self) -> None:
        self._deactivate(keep_cable=False)

    def _stop_processes(self) -> None:
        processes = ([self._capture] if self._capture else []) + [process for process, _role in self._playbacks]
        self._capture = None
        self._playbacks = []
        for process in processes:
            if process and process.stdin:
                with suppress(BrokenPipeError, OSError, ValueError):
                    process.stdin.close()
        for process in processes:
            if process and process.poll() is None:
                process.terminate()
        for process in processes:
            if not process:
                continue
            try:
                process.wait(timeout=1)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=1)
            for stream in (process.stdout, process.stderr):
                if stream:
                    with suppress(OSError, ValueError):
                        stream.close()

    def fail(self, error: Exception) -> None:
        self._deactivate(keep_cable=True)
        self.state.status = "error"
        self.state.error = str(error)
        self._event("error", str(error))

    def as_dict(self) -> dict[str, Any]:
        data = asdict(self.state)
        data["virtual_microphone_name"] = "RVC Virtual Microphone"
        return data
