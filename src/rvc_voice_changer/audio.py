from __future__ import annotations

import json
import subprocess
from typing import Any


VIRTUAL_NODE_NAMES = {"rvc_processing_sink", "rvc_virtual_microphone"}


def _label(props: dict[str, Any]) -> str:
    return str(
        props.get("node.description")
        or props.get("device.description")
        or props.get("node.nick")
        or props.get("node.name")
        or "Unknown audio device"
    )


def list_audio_devices() -> dict[str, list[dict[str, str]]]:
    groups: dict[str, list[dict[str, str]]] = {"inputs": [], "outputs": [], "monitors": []}
    try:
        completed = subprocess.run(["pw-dump"], check=True, capture_output=True, text=True, timeout=5)
        objects = json.loads(completed.stdout)
    except (FileNotFoundError, subprocess.SubprocessError, json.JSONDecodeError):
        return groups

    seen: set[tuple[str, str]] = set()
    for item in objects:
        info = item.get("info") or {}
        props = info.get("props") or {}
        media_class = props.get("media.class")
        name = str(props.get("node.name") or "")
        if not name or name in VIRTUAL_NODE_NAMES:
            continue
        entry = {"id": name, "name": _label(props)}
        if media_class == "Audio/Source":
            target = "inputs"
        elif media_class == "Audio/Sink":
            target = "outputs"
        else:
            continue
        key = (target, name)
        if key not in seen:
            groups[target].append(entry)
            seen.add(key)

    groups["inputs"].sort(key=lambda item: item["name"].casefold())
    groups["outputs"].sort(key=lambda item: item["name"].casefold())
    groups["monitors"] = list(groups["outputs"])
    groups["outputs"].insert(0, {"id": "rvc_processing_sink", "name": "RVC Virtual Microphone"})
    return groups
