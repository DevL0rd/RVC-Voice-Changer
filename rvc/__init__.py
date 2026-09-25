import os
from pathlib import Path

DATA_DIR = Path(
    os.environ.get("RVC_DATA_DIR")
    or Path(os.environ.get("XDG_DATA_HOME") or Path.home() / ".local" / "share") / "Linux-RVC-Voice-Changer"
)
ASSETS_DIR = DATA_DIR / "assets"
