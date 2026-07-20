from __future__ import annotations

import shutil
import subprocess
import threading


PROCESSING_INPUT_NAME = "rvc_processing_input"
VIRTUAL_MICROPHONE_NAME = "rvc_virtual_microphone"


class VirtualMicrophone:
    """Owns the stable PipeWire nodes fed by converted or bypass audio."""

    def __init__(self) -> None:
        self._process: subprocess.Popen[str] | None = None
        self._lock = threading.Lock()

    @property
    def running(self) -> bool:
        return self._process is not None and self._process.poll() is None

    def start(self) -> None:
        with self._lock:
            if self.running:
                return
            executable = shutil.which("pw-loopback")
            if not executable:
                raise RuntimeError("pw-loopback is missing; install PipeWire audio tools")
            capture_props = " ".join(
                (
                    "media.class=Stream/Input/Audio",
                    f"node.name={PROCESSING_INPUT_NAME}",
                    'node.description="RVC Private Processing Input"',
                    "node.autoconnect=false",
                    "node.dont-reconnect=true",
                    "node.virtual=true",
                    "audio.position=[ MONO ]",
                )
            )
            playback_props = " ".join(
                (
                    "media.class=Audio/Source",
                    f"node.name={VIRTUAL_MICROPHONE_NAME}",
                    'node.description="RVC Virtual Microphone"',
                    "node.virtual=true",
                    "audio.position=[ MONO ]",
                )
            )
            self._process = subprocess.Popen(
                [executable, "--capture-props", capture_props, "--playback-props", playback_props],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.PIPE,
                text=True,
                start_new_session=True,
            )
            try:
                self._process.wait(timeout=0.25)
            except subprocess.TimeoutExpired:
                return
            error = self._process.stderr.read().strip() if self._process.stderr else ""
            self._process = None
            raise RuntimeError(error or "PipeWire failed to create RVC Virtual Microphone")

    def stop(self) -> None:
        with self._lock:
            process, self._process = self._process, None
            if not process or process.poll() is not None:
                return
            process.terminate()
            try:
                process.wait(timeout=2)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=2)
