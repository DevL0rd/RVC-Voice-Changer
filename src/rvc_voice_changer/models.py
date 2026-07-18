from __future__ import annotations

from dataclasses import asdict, dataclass
from pathlib import Path


@dataclass(frozen=True)
class VoiceModel:
    id: str
    name: str
    model_path: str
    index_path: str | None
    ready: bool
    warning: str = ""

    def as_dict(self) -> dict[str, object]:
        return asdict(self)


def discover_models(models_dir: Path) -> list[VoiceModel]:
    models_dir.mkdir(parents=True, exist_ok=True)
    result: list[VoiceModel] = []
    for directory in sorted((item for item in models_dir.iterdir() if item.is_dir()), key=lambda item: item.name.casefold()):
        weights = sorted(directory.glob("*.pth"))
        indexes = sorted(directory.glob("*.index"))
        warning = ""
        if not weights:
            warning = "Missing .pth model"
        elif len(weights) > 1:
            warning = "More than one .pth model; using the first"
        result.append(
            VoiceModel(
                id=directory.name,
                name=directory.name,
                model_path=str(weights[0]) if weights else "",
                index_path=str(indexes[0]) if indexes else None,
                ready=bool(weights),
                warning=warning,
            )
        )
    return result
