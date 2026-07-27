from __future__ import annotations

import asyncio
import threading
from collections.abc import Callable
from typing import Any


COMPONENT_ID = "linux-rvc-voice-changer"
COMPONENT_NAME = "Linux RVC Voice Changer"

_ACTIONS: dict[str, tuple[str, str]] = {
    "voice_change": ("toggle-voice-change", "Toggle voice change"),
    "translation_out": ("toggle-translation-out", "Toggle microphone translation"),
    "translation_in": ("toggle-translation-in", "Toggle application translation"),
}

_MODIFIERS = {
    "Shift": 0x02000000,
    "Ctrl": 0x04000000,
    "Alt": 0x08000000,
    "Meta": 0x10000000,
    "Num": 0x20000000,
}

_SPECIAL_KEYS = {
    "Esc": 0x01000000,
    "Escape": 0x01000000,
    "Tab": 0x01000001,
    "Backtab": 0x01000002,
    "Backspace": 0x01000003,
    "Return": 0x01000004,
    "Enter": 0x01000005,
    "Ins": 0x01000006,
    "Insert": 0x01000006,
    "Del": 0x01000007,
    "Delete": 0x01000007,
    "Pause": 0x01000008,
    "Print": 0x01000009,
    "SysReq": 0x0100000A,
    "Clear": 0x0100000B,
    "Home": 0x01000010,
    "End": 0x01000011,
    "Left": 0x01000012,
    "Up": 0x01000013,
    "Right": 0x01000014,
    "Down": 0x01000015,
    "PgUp": 0x01000016,
    "Page Up": 0x01000016,
    "PgDown": 0x01000017,
    "Page Down": 0x01000017,
    "CapsLock": 0x01000024,
    "NumLock": 0x01000025,
    "ScrollLock": 0x01000026,
    "Menu": 0x01000055,
    "Help": 0x01000058,
    "Space": 0x20,
}
_SPECIAL_KEYS.update({f"F{number}": 0x0100002F + number for number in range(1, 36)})


def key_sequence_value(sequence: str) -> int:
    """Convert one portable QKeySequence chord to Qt's combined integer."""
    remaining = str(sequence or "").strip()
    if not remaining:
        return 0
    if ", " in remaining:
        raise ValueError("Multi-step shortcuts are not supported")

    combined = 0
    while True:
        matched = False
        for name, value in _MODIFIERS.items():
            prefix = f"{name}+"
            if remaining.startswith(prefix):
                combined |= value
                remaining = remaining[len(prefix) :]
                matched = True
                break
        if not matched:
            break

    if combined == 0:
        raise ValueError("A shortcut must include Alt, Ctrl, Shift, or Meta")
    if not remaining:
        raise ValueError("A shortcut must include a non-modifier key")

    key = _SPECIAL_KEYS.get(remaining)
    if key is None and len(remaining) == 1:
        key = ord(remaining.upper())
    if key is None:
        raise ValueError(f"Unsupported shortcut key: {remaining}")
    return combined | key


class GlobalShortcutManager:
    """Register persistent Wayland-safe shortcuts with KDE's KGlobalAccel."""

    def __init__(
        self,
        trigger: Callable[[str], None],
        event: Callable[[str, str], None],
    ) -> None:
        self._trigger = trigger
        self._event = event
        self._thread: threading.Thread | None = None
        self._loop: asyncio.AbstractEventLoop | None = None
        self._ready = threading.Event()
        self._stopping = threading.Event()
        self._interface: Any = None
        self._bus: Any = None

    def start(self, settings: dict[str, Any]) -> None:
        if self._thread is not None:
            return
        self._stopping.clear()
        self._thread = threading.Thread(
            target=self._run,
            args=(dict(settings),),
            name="rvc-global-shortcuts",
            daemon=True,
        )
        self._thread.start()

    def update(self, settings: dict[str, Any]) -> None:
        if not self._ready.wait(timeout=2) or self._loop is None:
            self._event("warning", "Global shortcut service is not ready")
            return
        future = asyncio.run_coroutine_threadsafe(
            self._register(dict(settings)),
            self._loop,
        )
        try:
            future.result(timeout=3)
        except Exception as error:
            self._event("warning", f"Could not update global shortcuts: {error}")

    def stop(self) -> None:
        self._stopping.set()
        if self._loop is not None:
            self._loop.call_soon_threadsafe(lambda: None)
        thread, self._thread = self._thread, None
        if thread and thread is not threading.current_thread():
            thread.join(timeout=3)

    def _run(self, settings: dict[str, Any]) -> None:
        try:
            asyncio.run(self._main(settings))
        except Exception as error:
            self._event("warning", f"Global shortcuts unavailable: {error}")
        finally:
            self._loop = None
            self._ready.set()

    async def _main(self, settings: dict[str, Any]) -> None:
        from dbus_next import BusType
        from dbus_next.aio import MessageBus

        self._loop = asyncio.get_running_loop()
        self._bus = await MessageBus(bus_type=BusType.SESSION).connect()
        introspection = await self._bus.introspect(
            "org.kde.kglobalaccel",
            "/kglobalaccel",
        )
        proxy = self._bus.get_proxy_object(
            "org.kde.kglobalaccel",
            "/kglobalaccel",
            introspection,
        )
        self._interface = proxy.get_interface("org.kde.KGlobalAccel")
        await self._register(settings)

        component_path = await self._interface.call_get_component(COMPONENT_ID)
        component_introspection = await self._bus.introspect(
            "org.kde.kglobalaccel",
            component_path,
        )
        component_proxy = self._bus.get_proxy_object(
            "org.kde.kglobalaccel",
            component_path,
            component_introspection,
        )
        component = component_proxy.get_interface("org.kde.kglobalaccel.Component")
        component.on_global_shortcut_pressed(self._pressed)
        self._ready.set()
        self._event("info", "KDE global shortcuts registered")

        while not self._stopping.is_set():
            await asyncio.sleep(0.25)

        for _setting, (action, label) in _ACTIONS.items():
            await self._interface.call_set_inactive(
                [COMPONENT_ID, action, COMPONENT_NAME, label]
            )
        self._bus.disconnect()

    async def _register(self, settings: dict[str, Any]) -> None:
        if self._interface is None:
            return
        for setting, (action, label) in _ACTIONS.items():
            action_id = [COMPONENT_ID, action, COMPONENT_NAME, label]
            sequence = str(settings.get(setting, "") or "").strip()
            keys = [key_sequence_value(sequence)] if sequence else []
            await self._interface.call_do_register(action_id)
            if setting == "translation_out":
                await self._interface.call_set_shortcut(action_id, [134217812], 12)
            else:
                await self._interface.call_set_shortcut(action_id, [], 12)
            assigned = await self._interface.call_set_shortcut(action_id, keys, 6)
            if assigned != keys:
                self._event(
                    "warning",
                    f"Shortcut {sequence or 'None'} could not be assigned to {label}",
                )

    def _pressed(self, component: str, action: str, _timestamp: int) -> None:
        if component != COMPONENT_ID:
            return
        setting = next(
            (name for name, values in _ACTIONS.items() if values[0] == action),
            None,
        )
        if setting is None:
            return
        threading.Thread(
            target=self._trigger_safely,
            args=(setting,),
            name=f"rvc-shortcut-{setting}",
            daemon=True,
        ).start()

    def _trigger_safely(self, setting: str) -> None:
        try:
            self._trigger(setting)
        except Exception as error:
            self._event("warning", f"Global shortcut failed: {error}")
