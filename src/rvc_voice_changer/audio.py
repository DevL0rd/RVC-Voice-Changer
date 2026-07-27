from __future__ import annotations

import json
import subprocess
from typing import Any

from .cable import PROCESSING_INPUT_NAME, VIRTUAL_MICROPHONE_NAME


VIRTUAL_NODE_NAMES = {PROCESSING_INPUT_NAME, VIRTUAL_MICROPHONE_NAME}


def _label(props: dict[str, Any]) -> str:
    return str(
        props.get("node.description")
        or props.get("device.description")
        or props.get("node.nick")
        or props.get("node.name")
        or "Unknown audio device"
    )


def list_audio_devices() -> dict[str, list[dict[str, str]]]:
    groups: dict[str, list[dict[str, str]]] = {
        "inputs": [],
        "outputs": [],
        "monitors": [],
        "applications": [],
    }
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
        if media_class == "Stream/Output/Audio":
            if props.get("application.id") == "org.devl0rd.rvcvoicechanger":
                continue
            node_id = name
            application = str(
                props.get("application.process.binary")
                or props.get("application.name")
                or _label(props)
            )
            media_name = str(props.get("media.name") or "")
            if media_name and media_name.casefold() not in {
                "audio stream",
                "playback",
                "playstream",
            }:
                application = f"{application} · {media_name}"
            key = ("applications", node_id)
            if key not in seen:
                groups["applications"].append({"id": node_id, "name": application})
                seen.add(key)
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
    groups["applications"].sort(key=lambda item: item["name"].casefold())
    return groups
