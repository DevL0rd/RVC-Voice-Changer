from __future__ import annotations

import threading
from collections import deque
from datetime import datetime
from typing import Any


class RollingLog:
    """Small in-memory event log for the local control UI."""

    def __init__(self, capacity: int = 200) -> None:
        self._entries: deque[dict[str, Any]] = deque(maxlen=capacity)
        self._lock = threading.Lock()
        self._next_id = 1

    def append(self, level: str, message: str) -> None:
        with self._lock:
            self._entries.append(
                {
                    "id": self._next_id,
                    "time": datetime.now().astimezone().isoformat(timespec="seconds"),
                    "level": str(level).lower(),
                    "message": str(message),
                }
            )
            self._next_id += 1

    def since(self, after: int = 0) -> dict[str, Any]:
        with self._lock:
            latest_id = self._next_id - 1
            reset = after > latest_id
            if reset:
                after = 0
            entries = [dict(entry) for entry in self._entries if entry["id"] > after]
            return {"entries": entries, "latest_id": latest_id, "reset": reset}
