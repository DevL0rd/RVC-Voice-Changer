from __future__ import annotations

import time

import torch


class StageProfiler:
    """Per-stage CUDA/ROCm event or CPU wall-clock profiler."""

    def __init__(self, device: str) -> None:
        self.device = device
        self._accelerated = torch.device(device).type == "cuda"
        self._wall_started = time.perf_counter()
        self._last_wall = self._wall_started
        self._start = torch.cuda.Event(enable_timing=True) if self._accelerated else None
        if self._start is not None:
            self._start.record(torch.cuda.current_stream(device=device))
        self._marks: list[tuple[str, torch.cuda.Event]] = []
        self._cpu_stages: dict[str, float] = {}

    def mark(self, name: str) -> None:
        if self._accelerated:
            event = torch.cuda.Event(enable_timing=True)
            event.record(torch.cuda.current_stream(device=self.device))
            self._marks.append((name, event))
        else:
            now = time.perf_counter()
            elapsed_ms = (now - self._last_wall) * 1000.0
            self._cpu_stages[name] = self._cpu_stages.get(name, 0.0) + elapsed_ms
            self._last_wall = now

    def add_cpu(self, name: str, elapsed_ms: float) -> None:
        self._cpu_stages[name] = self._cpu_stages.get(name, 0.0) + elapsed_ms
        if not self._accelerated:
            self._last_wall = time.perf_counter()

    def finish(self) -> dict[str, float]:
        if self._accelerated and not self._marks:
            self.mark("unclassified")
        result: dict[str, float] = {}
        if self._accelerated:
            self._marks[-1][1].synchronize()
            previous = self._start
            for name, event in self._marks:
                result[name] = result.get(name, 0.0) + float(previous.elapsed_time(event))
                previous = event
            result["accelerator_total"] = sum(result.values())
        for name, elapsed_ms in self._cpu_stages.items():
            result[name] = result.get(name, 0.0) + elapsed_ms
        if not self._accelerated:
            result["cpu_total"] = sum(result.values())
        result["device_total"] = result.get("accelerator_total", result.get("cpu_total", 0.0))
        result["rvc_wall_total"] = (time.perf_counter() - self._wall_started) * 1000.0
        return result
