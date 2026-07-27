from __future__ import annotations

import copy
import json
import threading
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any
from urllib.parse import parse_qs, urlparse

from .audio import list_audio_devices
from .config import ConfigStore, TRANSLATION_LANGUAGES
from .engine import VoiceEngine
from .logs import RollingLog
from .models import VoiceModel, discover_models
from .shortcuts import GlobalShortcutManager


class Application:
    def __init__(self, config: ConfigStore, engine: VoiceEngine) -> None:
        self.config = config
        self.engine = engine
        self.logs = RollingLog()
        self.engine.set_event_sink(self.logs.append)
        self.shortcuts = GlobalShortcutManager(self.toggle_shortcut, self.logs.append)
        self._models: list[VoiceModel] = []
        self._lock = threading.RLock()
        self.rescan()
        try:
            self.engine.bypass(self.config.data)
        except Exception as error:
            self.engine.fail(error)
        self.shortcuts.start(self.config.data["shortcuts"])
        self.logs.append("info", "Linux RVC Voice Changer daemon ready")

    def rescan(self) -> list[VoiceModel]:
        with self._lock:
            self._models = discover_models(self.config.models_dir)
            selected = self.config.data["model"]["selected"]
            if selected and not any(model.id == selected for model in self._models):
                self.config.update({"model": {"selected": ""}})
            if hasattr(self, "logs"):
                self.logs.append("info", f"Model scan found {len(self._models)} voice folders")
            return self._models

    def log_entries(self, after: int = 0) -> dict[str, Any]:
        return self.logs.since(max(0, after))

    def selected_model(self) -> VoiceModel | None:
        selected = self.config.data["model"]["selected"]
        return next((model for model in self._models if model.id == selected), None)

    def state(self, include_devices: bool = True) -> dict[str, Any]:
        with self._lock:
            public_config = copy.deepcopy(self.config.data)
            translate = public_config["translate"]
            translate["api_key_set"] = bool(translate["api_key"])
            translate["api_key"] = ""
            return {
                "config": public_config,
                "models_url": self.config.models_dir.resolve().as_uri(),
                "models": [model.as_dict() for model in self._models],
                "translation_languages": [
                    {"id": code, "name": name}
                    for code, name in TRANSLATION_LANGUAGES
                ],
                "devices": list_audio_devices() if include_devices else {},
                "runtime": self.engine.as_dict(),
            }

    def set_enabled(self, enabled: bool) -> dict[str, Any]:
        with self._lock:
            try:
                if enabled:
                    self.engine.enable(self.selected_model(), self.config.data)
                else:
                    self.engine.bypass(self.config.data)
                    self.logs.append("info", "Conversion disabled; stable virtual microphone remains in bypass")
            except Exception as error:
                self.engine.fail(error)
                raise
            return self.state(include_devices=False)

    def update_config(self, patch: dict[str, Any]) -> dict[str, Any]:
        with self._lock:
            needs_restart = self._requires_restart(patch)
            restart = self.engine.state.enabled and needs_restart
            if restart:
                self.engine.stop_conversion()
            self.config.update(patch)
            if "shortcuts" in patch:
                self.shortcuts.update(self.config.data["shortcuts"])
            changed = ", ".join(sorted(str(key) for key in patch))
            self.logs.append("info", f"Settings updated: {changed}")
            if restart:
                try:
                    self.engine.enable(self.selected_model(), self.config.data)
                except Exception:
                    raise
            elif not self.engine.state.enabled and needs_restart:
                self.engine.bypass(self.config.data)
            return self.state(include_devices=False)

    def toggle_shortcut(self, setting: str) -> None:
        if setting == "voice_change":
            enabled = not self.engine.state.enabled
            self.set_enabled(enabled)
            self.logs.append(
                "info",
                f"Global shortcut toggled Voice {'on' if enabled else 'off'}",
            )
            return
        if setting == "translation_out":
            enabled = not bool(self.config.data["translate"]["enabled"])
            self.update_config({"translate": {"enabled": enabled}})
            actual = bool(self.config.data["translate"]["enabled"])
            self.logs.append(
                "info",
                f"Global shortcut toggled Mic translate {'on' if actual else 'off'}",
            )
            return
        if setting == "translation_in":
            enabled = not bool(self.config.data["incoming_translate"]["enabled"])
            self.update_config({"incoming_translate": {"enabled": enabled}})
            actual = bool(self.config.data["incoming_translate"]["enabled"])
            self.logs.append(
                "info",
                f"Global shortcut toggled App translate {'on' if actual else 'off'}",
            )
            return
        raise ValueError(f"Unknown shortcut action: {setting}")

    def reset_config(self) -> dict[str, Any]:
        with self._lock:
            self.engine.stop_conversion()
            self.config.reset()
            self.shortcuts.update(self.config.data["shortcuts"])
            self.rescan()
            self.engine.bypass(self.config.data)
            self.logs.append("warning", "Settings reset to shipped defaults")
            return self.state(include_devices=False)

    @staticmethod
    def _requires_restart(patch: dict[str, Any]) -> bool:
        audio = set((patch.get("audio") or {}).keys())
        model = set((patch.get("model") or {}).keys())
        translate = set((patch.get("translate") or {}).keys())
        return bool(
            audio - {"input_gain_db", "output_gain_db", "monitor_gain_db"}
            or model & {"selected", "speaker_id", "f0_method"}
            or patch.get("cleanup")
            or patch.get("gpu")
            or translate - {"original_voice_volume"}
            or patch.get("incoming_translate")
            or "models_dir" in patch
        )

    def close(self) -> None:
        self.shortcuts.stop()
        self.engine.shutdown()


class ApiHandler(BaseHTTPRequestHandler):
    server_version = "LinuxRVCVoiceChanger/0.1"

    @property
    def app(self) -> Application:
        return self.server.app  # type: ignore[attr-defined]

    def log_message(self, format: str, *args: object) -> None:
        if self.path.startswith("/v1/state") or self.path.startswith("/v1/logs"):
            return
        print(f"api: {format % args}")

    def _send(self, status: HTTPStatus, data: dict[str, Any]) -> None:
        payload = json.dumps(data, separators=(",", ":")).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, PATCH, OPTIONS")
        self.end_headers()
        self.wfile.write(payload)

    def _body(self) -> dict[str, Any]:
        length = int(self.headers.get("Content-Length", "0"))
        if length <= 0:
            return {}
        value = json.loads(self.rfile.read(length))
        if not isinstance(value, dict):
            raise ValueError("Request body must be a JSON object")
        return value

    def do_OPTIONS(self) -> None:
        self._send(HTTPStatus.NO_CONTENT, {})

    def do_GET(self) -> None:
        parsed = urlparse(self.path)
        path = parsed.path
        if path == "/v1/state":
            values = parse_qs(parsed.query).get("devices", ["1"])
            include_devices = values[0].casefold() not in {"0", "false", "no"}
            self._send(HTTPStatus.OK, self.app.state(include_devices=include_devices))
        elif path == "/v1/health":
            self._send(HTTPStatus.OK, {"ok": True, "runtime": self.app.engine.as_dict()})
        elif path == "/v1/logs":
            values = parse_qs(parsed.query).get("after", ["0"])
            try:
                after = int(values[0])
            except ValueError:
                self._send(HTTPStatus.BAD_REQUEST, {"error": "after must be an integer"})
                return
            self._send(HTTPStatus.OK, self.app.log_entries(after))
        else:
            self._send(HTTPStatus.NOT_FOUND, {"error": "Not found"})

    def do_POST(self) -> None:
        path = urlparse(self.path).path
        try:
            body = self._body()
            if path == "/v1/enabled":
                if "enabled" not in body:
                    raise ValueError("Missing enabled")
                self._send(HTTPStatus.OK, self.app.set_enabled(bool(body["enabled"])))
            elif path == "/v1/models/rescan":
                self.app.rescan()
                self._send(HTTPStatus.OK, self.app.state(include_devices=False))
            elif path == "/v1/config/reset":
                self._send(HTTPStatus.OK, self.app.reset_config())
            else:
                self._send(HTTPStatus.NOT_FOUND, {"error": "Not found"})
        except (ValueError, json.JSONDecodeError) as error:
            self._send(HTTPStatus.BAD_REQUEST, {"error": str(error)})
        except RuntimeError as error:
            self._send(HTTPStatus.CONFLICT, {"error": str(error), "runtime": self.app.engine.as_dict()})

    def do_PATCH(self) -> None:
        try:
            if urlparse(self.path).path != "/v1/config":
                self._send(HTTPStatus.NOT_FOUND, {"error": "Not found"})
                return
            self._send(HTTPStatus.OK, self.app.update_config(self._body()))
        except (ValueError, json.JSONDecodeError, TypeError) as error:
            self._send(HTTPStatus.BAD_REQUEST, {"error": str(error)})
        except RuntimeError as error:
            self._send(HTTPStatus.CONFLICT, {"error": str(error), "runtime": self.app.engine.as_dict()})


class ApiServer(ThreadingHTTPServer):
    daemon_threads = True

    def __init__(self, address: tuple[str, int], app: Application) -> None:
        super().__init__(address, ApiHandler)
        self.app = app
