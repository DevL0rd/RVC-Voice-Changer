from __future__ import annotations

import copy
import json
import os
from pathlib import Path
from typing import Any


DEFAULT_CONFIG: dict[str, Any] = {
    "server": {"host": "127.0.0.1", "port": 17843},
    "models_dir": "models",
    "audio": {
        "input_device": "",
        "output_device": "rvc_processing_sink",
        "monitor_device": "",
        "monitor_enabled": True,
        "sample_rate": 48000,
        "block_ms": 250,
        "crossfade_ms": 50,
        "extra_ms": 2500,
        "input_gain_db": 0.0,
        "output_gain_db": 0.0,
        "monitor_gain_db": 24.0,
    },
    "model": {
        "selected": "",
        "speaker_id": 0,
        "pitch": 0,
        "f0_method": "rmvpe",
        "index_rate": 0.6,
        "rms_mix_rate": 0.0,
        "protect": 0.2,
        "autotune": False,
        "autotune_strength": 1.0,
        "proposed_pitch": True,
        "proposed_pitch_threshold": 255.0,
    },
    "cleanup": {
        "vad_enabled": False,
        "vad_sensitivity": 3,
        "noise_suppression": False,
        "noise_suppression_strength": 0.5,
        "noise_gate_db": -60.0,
        "high_pass_hz": 80,
        "low_pass_hz": 16000,
    },
    "gpu": {
        "backend": "auto",
        "device": 0,
        "allow_tf32": True,
        "cpu_threads": 0,
    },
}


def _merge(base: dict[str, Any], patch: dict[str, Any]) -> dict[str, Any]:
    for key, value in patch.items():
        if isinstance(value, dict) and isinstance(base.get(key), dict):
            _merge(base[key], value)
        elif key in base:
            base[key] = value
    return base


class ConfigStore:
    def __init__(self, repo_dir: Path) -> None:
        config_home = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config"))
        self.path = config_home / "Linux-RVC-Voice-Changer" / "config.json"
        self.repo_dir = repo_dir
        self.data: dict[str, Any] = {}
        self.load()

    def load(self) -> dict[str, Any]:
        data = copy.deepcopy(DEFAULT_CONFIG)
        if self.path.exists():
            with self.path.open(encoding="utf-8") as handle:
                loaded = json.load(handle)
            if isinstance(loaded, dict):
                _merge(data, loaded)
        self.data = data
        self._normalise()
        self.save()
        return self.data

    def update(self, patch: dict[str, Any]) -> dict[str, Any]:
        _merge(self.data, patch)
        self._normalise()
        self.save()
        return self.data

    def reset(self) -> dict[str, Any]:
        self.data = copy.deepcopy(DEFAULT_CONFIG)
        self._normalise()
        self.save()
        return self.data

    def save(self) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        temporary = self.path.with_suffix(".tmp")
        temporary.write_text(json.dumps(self.data, indent=2) + "\n", encoding="utf-8")
        temporary.replace(self.path)

    @property
    def models_dir(self) -> Path:
        value = Path(os.path.expandvars(os.path.expanduser(str(self.data["models_dir"]))))
        return value if value.is_absolute() else self.repo_dir / value

    def _normalise(self) -> None:
        model = self.data["model"]
        audio = self.data["audio"]
        cleanup = self.data["cleanup"]
        gpu = self.data["gpu"]
        server = self.data["server"]

        model["speaker_id"] = max(0, int(model["speaker_id"]))
        model["pitch"] = max(-24, min(24, int(model["pitch"])))
        model["f0_method"] = str(model["f0_method"]) if model["f0_method"] in {"rmvpe", "fcpe", "crepe", "crepe-tiny"} else "rmvpe"
        model["index_rate"] = max(0.0, min(1.0, float(model["index_rate"])))
        model["rms_mix_rate"] = max(0.0, min(1.0, float(model["rms_mix_rate"])))
        model["protect"] = max(0.0, min(0.5, float(model["protect"])))
        model["autotune"] = bool(model["autotune"])
        model["autotune_strength"] = max(0.0, min(1.0, float(model["autotune_strength"])))
        model["proposed_pitch"] = bool(model["proposed_pitch"])
        model["proposed_pitch_threshold"] = max(50.0, min(1200.0, float(model["proposed_pitch_threshold"])))

        audio["sample_rate"] = int(audio["sample_rate"])
        if audio["sample_rate"] not in {32000, 40000, 44100, 48000}:
            audio["sample_rate"] = 48000
        audio["block_ms"] = max(10, min(1000, int(audio["block_ms"])))
        audio["crossfade_ms"] = max(0, min(500, int(audio["crossfade_ms"])))
        audio["extra_ms"] = max(100, min(5000, int(audio["extra_ms"])))
        audio["input_gain_db"] = max(-24.0, min(24.0, float(audio["input_gain_db"])))
        audio["output_gain_db"] = max(-24.0, min(24.0, float(audio["output_gain_db"])))
        audio["monitor_gain_db"] = max(-24.0, min(24.0, float(audio["monitor_gain_db"])))
        audio["monitor_enabled"] = bool(audio["monitor_enabled"])

        cleanup["vad_enabled"] = bool(cleanup["vad_enabled"])
        cleanup["vad_sensitivity"] = max(0, min(3, int(cleanup["vad_sensitivity"])))
        cleanup["noise_suppression"] = bool(cleanup["noise_suppression"])
        cleanup["noise_suppression_strength"] = max(0.0, min(1.0, float(cleanup["noise_suppression_strength"])))
        cleanup["noise_gate_db"] = max(-100.0, min(0.0, float(cleanup["noise_gate_db"])))
        cleanup["high_pass_hz"] = max(0, min(1000, int(cleanup["high_pass_hz"])))
        cleanup["low_pass_hz"] = max(1000, min(24000, int(cleanup["low_pass_hz"])))

        gpu["backend"] = str(gpu["backend"]) if gpu["backend"] in {"auto", "cuda", "cpu"} else "auto"
        gpu["device"] = max(0, int(gpu["device"]))
        gpu["allow_tf32"] = bool(gpu["allow_tf32"])
        gpu["cpu_threads"] = max(0, min(256, int(gpu["cpu_threads"])))
        server["host"] = "127.0.0.1"
        server["port"] = max(1024, min(65535, int(server["port"])))
