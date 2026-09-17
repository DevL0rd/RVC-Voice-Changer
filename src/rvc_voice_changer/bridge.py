from __future__ import annotations

import math
import shutil
import subprocess
import threading
import time
from array import array
from contextlib import suppress
from typing import Callable

from .cable import PROCESSING_INPUT_NAME


CAPTURE_NODE = "rvc_bypass_capture"
OUTPUT_NODE = "rvc_bypass_output"
METER_NODE = "rvc_level_meter"
METER_RATE = 8000
METER_FRAMES = 2000
METER_LEASE = 3.0
LINK_TIMEOUT = 2.0


def _terminate(process: subprocess.Popen[bytes] | None) -> None:
    if process is None:
        return
    if process.poll() is None:
        process.terminate()
        try:
            process.wait(timeout=1)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=1)
    for stream in (process.stdin, process.stdout, process.stderr):
        if stream:
            with suppress(OSError, ValueError):
                stream.close()


class MicrophoneBridge:
    def __init__(self, on_lost: Callable[[str], None], on_level: Callable[[float], None]) -> None:
        self._on_lost = on_lost
        self._on_level = on_level
        self._lock = threading.Lock()
        self._source = ""
        self._loopback: subprocess.Popen[bytes] | None = None
        self._monitor: subprocess.Popen[bytes] | None = None
        self._meter: subprocess.Popen[bytes] | None = None
        self._meter_thread: threading.Thread | None = None
        self._meter_until = 0.0
        self._stopping = threading.Event()
        self._ready = threading.Event()
        self._wrong_source = ""

    @property
    def running(self) -> bool:
        return self._loopback is not None

    def start(self, source: str) -> None:
        loopback = shutil.which("pw-loopback")
        link = shutil.which("pw-link")
        if not loopback or not link:
            raise RuntimeError("pw-loopback and pw-link are required; install PipeWire audio tools")
        self.stop()
        with self._lock:
            self._source = source
            self._stopping.clear()
            self._ready.clear()
            self._wrong_source = ""
            self._monitor = subprocess.Popen(
                [link, "-m", "-l", "-I"],
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
            )
            threading.Thread(
                target=self._watch_links, args=(self._monitor,), name="rvc-bypass-links", daemon=True
            ).start()
            capture_props = " ".join(
                (
                    f"target.object={source}",
                    f"node.name={CAPTURE_NODE}",
                    'node.description="RVC Bypass Capture"',
                    "node.dont-reconnect=true",
                    "audio.position=[ MONO ]",
                )
            )
            playback_props = " ".join(
                (
                    f"target.object={PROCESSING_INPUT_NAME}",
                    f"node.name={OUTPUT_NODE}",
                    'node.description="RVC Bypass Output"',
                    "node.dont-reconnect=true",
                    "audio.position=[ MONO ]",
                )
            )
            self._loopback = subprocess.Popen(
                [loopback, "--capture-props", capture_props, "--playback-props", playback_props],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.PIPE,
                start_new_session=True,
            )
        if self._ready.wait(LINK_TIMEOUT) and not self._wrong_source:
            return
        if self._wrong_source:
            wrong = self._wrong_source
            self.stop()
            raise RuntimeError(f"Input {source} is not available; PipeWire linked {wrong} instead")
        process = self._loopback
        error = ""
        if process is not None and process.poll() is not None and process.stderr:
            error = process.stderr.read().decode(errors="replace").strip()
        self.stop()
        raise RuntimeError(error or f"PipeWire could not link input {source} to RVC Virtual Microphone")

    def stop(self) -> None:
        self._stopping.set()
        with self._lock:
            loopback, self._loopback = self._loopback, None
            monitor, self._monitor = self._monitor, None
            meter, self._meter = self._meter, None
            self._meter_until = 0.0
        _terminate(meter)
        _terminate(loopback)
        _terminate(monitor)
        thread, self._meter_thread = self._meter_thread, None
        if thread and thread is not threading.current_thread():
            thread.join(timeout=2)

    def want_level(self) -> None:
        with self._lock:
            if self._loopback is None:
                return
            self._meter_until = time.monotonic() + METER_LEASE
            if self._meter_thread is not None and self._meter_thread.is_alive():
                return
            self._meter_thread = threading.Thread(target=self._run_meter, name="rvc-level-meter", daemon=True)
            self._meter_thread.start()

    def _lost(self, message: str) -> None:
        if self._stopping.is_set():
            return
        self.stop()
        self._on_lost(message)

    def _watch_links(self, monitor: subprocess.Popen[bytes]) -> None:
        header = ""
        capture_linked = False
        output_linked = False
        assert monitor.stdout is not None
        for raw in monitor.stdout:
            line = raw.decode(errors="replace").rstrip("\n")
            kind, body = line[:1], line[1:].strip()
            if "|->" in body or "|<-" in body:
                ports = header + " " + body
                capture = CAPTURE_NODE + ":" in ports
                output = OUTPUT_NODE + ":" in ports
                if kind == "+":
                    if capture and self._source + ":" not in ports:
                        peer = body.split(maxsplit=1)[-1] if header.startswith(CAPTURE_NODE + ":") else header
                        peer = peer.rsplit(":", 1)[0]
                        if self._ready.is_set():
                            self._lost(f"PipeWire moved the bypass input to {peer}")
                        else:
                            self._wrong_source = peer
                            self._ready.set()
                        return
                    capture_linked = capture_linked or capture
                    output_linked = output_linked or output
                    if capture_linked and output_linked:
                        self._ready.set()
                elif kind == "-" and self._ready.is_set() and (capture or output):
                    self._lost(
                        "PipeWire input stream stopped during bypass"
                        if capture
                        else "RVC Virtual Microphone bypass stream stopped"
                    )
                    return
                continue
            header = body
            if kind == "-" and self._ready.is_set() and (CAPTURE_NODE + ":" in body or OUTPUT_NODE + ":" in body):
                self._lost("PipeWire bypass stream stopped")
                return
        if monitor is self._monitor:
            self._lost("PipeWire link monitor stopped during bypass")

    def _run_meter(self) -> None:
        executable = shutil.which("pw-cat")
        if not executable:
            return
        command = [
            executable,
            "--record",
            "--raw",
            "--format",
            "f32",
            "--rate",
            str(METER_RATE),
            "--channels",
            "1",
            "--channel-map",
            "MONO",
            "--latency",
            str(METER_FRAMES),
            "--target",
            self._source,
            "--properties",
            " ".join(
                (
                    "application.id=org.devl0rd.rvcvoicechanger",
                    'application.name="Linux RVC Voice Changer"',
                    f"node.name={METER_NODE}",
                    "node.dont-reconnect=true",
                )
            ),
            "-",
        ]
        with self._lock:
            if self._stopping.is_set():
                return
            process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
            self._meter = process
        assert process.stdout is not None
        size = METER_FRAMES * 4
        try:
            while time.monotonic() < self._meter_until and not self._stopping.is_set():
                raw = process.stdout.read(size)
                if len(raw) != size:
                    break
                samples = array("f", raw)
                rms = math.sqrt(math.fsum(value * value for value in samples) / len(samples))
                self._on_level(round(20.0 * math.log10(max(rms, 1e-5)), 1))
        finally:
            with self._lock:
                if self._meter is process:
                    self._meter = None
            _terminate(process)
            self._on_level(-100.0)
