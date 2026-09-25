#!/bin/bash
set -euo pipefail

REPO_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
if [[ ! -f "$REPO_DIR/src/rvc_voice_changer/daemon.py" ]]; then
    echo "Repository files are incomplete."
    exit 1
fi
source "$REPO_DIR/packaging/lib.sh"

AUR=false
SKIP_DEPS=false
SYSTEM_UPDATE=false
SYSTEM_UPDATE_ROOT=false
OWNER=""
[[ ${RVC_AUR:-} == @(1|true|yes) ]] && AUR=true
while (( $# )); do
    case "$1" in
    --aur) AUR=true ;;
    --skip-deps) SKIP_DEPS=true ;;
    --system-update) SYSTEM_UPDATE=true ;;
    --system-update-root) SYSTEM_UPDATE_ROOT=true ;;
    --owner) OWNER=${2:-}; shift ;;
    -h | --help)
        echo "Usage: ./install.sh [--skip-deps] [--aur]"
        echo "Installs the voice changer and, for a git checkout, updates it with every system update."
        echo "  --skip-deps  Do not install missing system packages with the package manager"
        echo "  --aur        Installed by a package (also RVC_AUR=true); no update hook is registered."
        exit 0
        ;;
    *) echo "Unknown option: $1"; exit 1 ;;
    esac
    shift
done

if $SYSTEM_UPDATE_ROOT; then
    if [[ $EUID -ne 0 || -z $OWNER ]]; then
        echo "--system-update-root runs from the system update hook."
        exit 1
    fi
    install_update_hooks "$REPO_DIR" "$REPO_DIR" "$OWNER" "$(package_manager)"
    exit 0
fi

if ! $AUR && ! $SKIP_DEPS && ! $SYSTEM_UPDATE; then
    "$REPO_DIR/packaging/dependencies.sh"
fi

missing=0
for command_name in python3 pw-dump pw-loopback pw-link pw-cat pactl kpackagetool6 curl; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
        echo "Missing required command: $command_name"
        missing=1
    fi
done
if (( missing )); then
    echo "Install the missing PipeWire/Plasma dependencies, then run this again."
    exit 1
fi

if [[ ! -e "$REPO_DIR/shared/common/PopupShell.qml" ]]; then
    echo "shared/common (Plasma-Shared submodule) is empty."
    echo "Run: git submodule update --init --recursive"
    exit 1
fi

BIN_DIR="$HOME/.local/bin"
USER_UNIT_DIR=$(user_unit_dir)
VENV_PYTHON="$RVC_VENV_DIR/bin/python"
RUNTIME_STAGING=""
PLASMOID_STAGING=""
trap 'rm -rf "$RUNTIME_STAGING" "$PLASMOID_STAGING"' EXIT

mkdir -p "$RVC_CONFIG_DIR" "$RVC_DATA_DIR"
if [[ ! -f "$RVC_CONFIG_DIR/config.json" ]]; then
    cp "$REPO_DIR/config.example.json" "$RVC_CONFIG_DIR/config.json"
    echo "Created $RVC_CONFIG_DIR/config.json"
fi
MODELS_DIR=$(voice_models_dir "$REPO_DIR")

move_legacy_voices() {
    local legacy="$REPO_DIR/models" entry name target number
    [[ -d $legacy ]] || return 0
    mkdir -p "$MODELS_DIR"
    shopt -s nullglob dotglob
    for entry in "$legacy"/*; do
        name=$(basename "$entry")
        target="$MODELS_DIR/$name"
        if [[ -e $target || -L $target ]]; then
            target="$MODELS_DIR/$name (from checkout)"
            number=1
            while [[ -e $target || -L $target ]]; do
                number=$((number + 1))
                target="$MODELS_DIR/$name (from checkout $number)"
            done
            echo "$MODELS_DIR/$name already exists, so both are kept."
        fi
        mv "$entry" "$target"
        echo "Moved $entry to $target"
    done
    shopt -u nullglob dotglob
    rmdir "$legacy"
}

move_legacy_assets() {
    local legacy="$REPO_DIR/rvc/models" file target
    [[ -d $legacy ]] || return 0
    while IFS= read -r -d '' file; do
        target="$RVC_ASSETS_DIR/${file#"$legacy"/}"
        if [[ -s $file && ! -s $target ]]; then
            mkdir -p "$(dirname "$target")"
            mv "$file" "$target"
            echo "Moved $file to $target"
        fi
    done < <(find "$legacy" -type f ! -name '*.part' -print0)
    rm -rf "$legacy"
    echo "Removed $legacy"
}

remove_legacy_runtime() {
    local path
    if [[ -e $REPO_DIR/.venv ]]; then
        rm -rf "$REPO_DIR/.venv"
        echo "Removed $REPO_DIR/.venv (the Python runtime now lives in $RVC_VENV_DIR)"
    fi
    for path in "$REPO_DIR"/plasmoids/*/contents/ui/lib; do
        [[ -e $path ]] || continue
        rm -rf "$path"
        echo "Removed $path"
    done
    while IFS= read -r -d '' path; do
        rm -rf "$path"
        echo "Removed $path"
    done < <(find "$REPO_DIR/src" "$REPO_DIR/rvc" -type d -name __pycache__ -prune -print0)
}

move_legacy_voices
move_legacy_assets

PYTHON_VERSION=$(python3 -c 'import sys; print("%d.%d" % sys.version_info[:2])')
if [[ -d $RVC_VENV_DIR && ! -d $RVC_VENV_DIR/lib/python$PYTHON_VERSION ]]; then
    echo "Python is now $PYTHON_VERSION; rebuilding the isolated RVC runtime..."
    rm -rf "$RVC_VENV_DIR"
fi
if [[ ! -x $VENV_PYTHON ]]; then
    echo "Creating the isolated RVC runtime in $RVC_VENV_DIR..."
    python3 -m venv "$RVC_VENV_DIR"
    "$VENV_PYTHON" -m pip install --upgrade pip setuptools wheel
fi

TORCH_BACKEND=${RVC_TORCH_BACKEND:-auto}
TORCH_INDEX_URL=${RVC_TORCH_INDEX_URL:-}
TORCH_BACKEND_WAS_AUTO=0
if [[ -n "$TORCH_INDEX_URL" ]]; then
    TORCH_BACKEND=custom
elif [[ "$TORCH_BACKEND" == auto ]]; then
    TORCH_BACKEND_WAS_AUTO=1
    if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi -L >/dev/null 2>&1; then
        TORCH_BACKEND=cuda
    elif command -v rocminfo >/dev/null 2>&1 && rocminfo >/dev/null 2>&1; then
        TORCH_BACKEND=rocm
    else
        TORCH_BACKEND=cpu
        for vendor_file in /sys/class/drm/card*/device/vendor; do
            if [[ -r "$vendor_file" ]] && [[ "$(<"$vendor_file")" == 0x1002 ]]; then
                TORCH_BACKEND=rocm
                break
            fi
        done
    fi
fi

torch_matches() {
    "$VENV_PYTHON" - "$1" <<'PY' >/dev/null 2>&1
import sys
import torch
import torchaudio
backend = sys.argv[1]
pinned = torch.__version__.split("+")[0] == "2.11.0"
if backend == "cuda":
    ok = pinned and torch.version.cuda is not None
elif backend == "cpu":
    ok = pinned and torch.version.cuda is None and not getattr(torch.version, "hip", None)
elif backend == "rocm":
    ok = bool(getattr(torch.version, "hip", None))
else:
    ok = False
sys.exit(0 if ok else 1)
PY
}

if torch_matches "$TORCH_BACKEND"; then
    echo "PyTorch for $TORCH_BACKEND is already installed."
else
case "$TORCH_BACKEND" in
    cuda)
        echo "Installing NVIDIA CUDA PyTorch..."
        "$VENV_PYTHON" -m pip install --upgrade --force-reinstall \
            "torch==2.11.0" "torchaudio==2.11.0"
        ;;
    rocm)
        echo "Installing AMD ROCm PyTorch..."
        "$VENV_PYTHON" -m pip install --upgrade --force-reinstall \
            --index-url https://repo.amd.com/rocm/whl-multi-arch/ \
            "torch[device-all]" torchaudio
        ;;
    cpu)
        echo "Installing CPU-only PyTorch..."
        "$VENV_PYTHON" -m pip install --upgrade --force-reinstall \
            --index-url https://download.pytorch.org/whl/cpu \
            "torch==2.11.0" "torchaudio==2.11.0"
        ;;
    custom)
        echo "Installing PyTorch from custom index: $TORCH_INDEX_URL"
        "$VENV_PYTHON" -m pip install --upgrade --force-reinstall \
            --index-url "$TORCH_INDEX_URL" torch torchaudio
        ;;
    *)
        echo "Unsupported RVC_TORCH_BACKEND: $TORCH_BACKEND (use auto, cuda, rocm, or cpu)"
        exit 1
        ;;
esac
fi

if [[ "$TORCH_BACKEND" == rocm ]] && ! "$VENV_PYTHON" - <<'PY'
import sys
import torch
sys.exit(0 if torch.cuda.is_available() and torch.version.hip else 1)
PY
then
    if (( TORCH_BACKEND_WAS_AUTO )); then
        echo "The AMD GPU is not usable through ROCm; falling back to CPU-only PyTorch."
        TORCH_BACKEND=cpu
        if ! torch_matches cpu; then
            "$VENV_PYTHON" -m pip install --upgrade --force-reinstall \
                --index-url https://download.pytorch.org/whl/cpu \
                "torch==2.11.0" "torchaudio==2.11.0"
        fi
    else
        echo "ROCm was requested, but PyTorch cannot use an AMD GPU on this machine."
        exit 1
    fi
fi

"$VENV_PYTHON" -m pip install -r "$REPO_DIR/requirements-runtime.txt"

download_asset() {
    local remote_path=$1
    local destination=$2
    if [[ -s "$destination" ]]; then
        return
    fi
    mkdir -p "$(dirname "$destination")"
    echo "Downloading $(basename "$destination")..."
    curl --fail --location --retry 3 --output "$destination.part" \
        "https://huggingface.co/IAHispano/Applio/resolve/main/Resources/$remote_path"
    mv "$destination.part" "$destination"
}

download_asset "predictors/rmvpe.pt" "$RVC_ASSETS_DIR/predictors/rmvpe.pt"
download_asset "predictors/fcpe.pt" "$RVC_ASSETS_DIR/predictors/fcpe.pt"
download_asset "embedders/contentvec/pytorch_model.bin" "$RVC_ASSETS_DIR/embedders/contentvec/pytorch_model.bin"
download_asset "embedders/contentvec/config.json" "$RVC_ASSETS_DIR/embedders/contentvec/config.json"

RUNTIME_STAGING=$(mktemp -d "$RVC_DATA_DIR/.runtime.XXXXXX")
chmod 755 "$RUNTIME_STAGING"
cp -a "$REPO_DIR/bin" "$REPO_DIR/src" "$REPO_DIR/rvc" "$RUNTIME_STAGING/"
find "$RUNTIME_STAGING" \( -name __pycache__ -o -path "$RUNTIME_STAGING/rvc/models" \) -prune -exec rm -rf {} +
chmod +x "$RUNTIME_STAGING/bin/rvc-voice-changer" "$RUNTIME_STAGING/bin/rvc-voice-changer-ctl"

UNIT="$USER_UNIT_DIR/linux-rvc-voice-changer.service"
STAMP="$RVC_CONFIG_DIR/installed-revision"
NEW_UNIT=$(sed "s|@DATA_DIR@|$RVC_DATA_DIR|g" "$REPO_DIR/systemd/linux-rvc-voice-changer.service.in")
REVISION=$( { printf '%s\n' "$NEW_UNIT" "$PYTHON_VERSION"; sha256sum <"$REPO_DIR/requirements-runtime.txt"; (cd "$RUNTIME_STAGING" && find . -type f -print0 | LC_ALL=C sort -z | xargs -0 sha256sum); } | sha256sum | cut -d' ' -f1)
RESTART=0
if [[ -x $RVC_RUNTIME_DIR/bin/rvc-voice-changer && -f $STAMP && "$(<"$STAMP")" == "$REVISION" ]]; then
    rm -rf "$RUNTIME_STAGING"
else
    PREVIOUS_RUNTIME="$RVC_DATA_DIR/.runtime.previous.$$"
    if [[ -e $RVC_RUNTIME_DIR ]]; then
        mv "$RVC_RUNTIME_DIR" "$PREVIOUS_RUNTIME"
    fi
    mv "$RUNTIME_STAGING" "$RVC_RUNTIME_DIR"
    rm -rf "$PREVIOUS_RUNTIME"
    echo "Installed the voice changer to $RVC_RUNTIME_DIR"
    RESTART=1
fi
RUNTIME_STAGING=""

mkdir -p "$BIN_DIR" "$USER_UNIT_DIR"
ln -sfn "$RVC_RUNTIME_DIR/bin/rvc-voice-changer" "$BIN_DIR/rvc-voice-changer"
ln -sfn "$RVC_RUNTIME_DIR/bin/rvc-voice-changer-ctl" "$BIN_DIR/rvc-voice-changer-ctl"

if [[ ! -f "$UNIT" ]] || [[ "$(<"$UNIT")" != "$NEW_UNIT" ]]; then
    printf '%s\n' "$NEW_UNIT" > "$UNIT"
    systemctl --user daemon-reload
    RESTART=1
fi
systemctl --user enable linux-rvc-voice-changer.service >/dev/null 2>&1
if (( RESTART )); then
    systemctl --user restart linux-rvc-voice-changer.service
    echo "Restarted linux-rvc-voice-changer.service"
elif ! systemctl --user is-active --quiet linux-rvc-voice-changer.service; then
    systemctl --user start linux-rvc-voice-changer.service
    echo "Started linux-rvc-voice-changer.service"
else
    echo "linux-rvc-voice-changer.service is up to date"
fi
printf '%s\n' "$REVISION" > "$STAMP"
remove_legacy_runtime

PLASMOID_STAGING=$(mktemp -d)
PLASMOID="$PLASMOID_STAGING/org.devl0rd.rvcvoicechanger"
cp -a "$REPO_DIR/plasmoids/org.devl0rd.rvcvoicechanger" "$PLASMOID"
rm -rf "$PLASMOID/contents/ui/lib"
mkdir -p "$PLASMOID/contents/ui/lib"
cp "$REPO_DIR/shared/common/"*.qml "$REPO_DIR/shared/common/"*.js "$PLASMOID/contents/ui/lib/"
if kpackagetool6 -t Plasma/Applet -u "$PLASMOID" >/dev/null 2>&1; then
    echo "Upgraded RVC Voice Changer Plasma applet"
else
    kpackagetool6 -t Plasma/Applet -i "$PLASMOID" >/dev/null
    echo "Installed RVC Voice Changer Plasma applet"
fi
rm -rf "$PLASMOID_STAGING"
PLASMOID_STAGING=""

"$VENV_PYTHON" - <<'PY'
import torch
if torch.cuda.is_available():
    platform = "AMD ROCm" if torch.version.hip else "NVIDIA CUDA"
    print(f"Inference runtime: {platform} GPU + CPU")
else:
    print("Inference runtime: CPU")
PY

if $SYSTEM_UPDATE; then
    install_user_updater "$REPO_DIR" "$REPO_DIR"
    notify_updated "The voice changer is up to date. Restart Plasma or log out and back in to load the updated widget."
    exit 0
fi
register_system_updates "$REPO_DIR" "$AUR"

echo
echo "Installed. Add 'RVC Voice Changer' from Plasma's Add Widgets menu."
echo "Voice folders: $MODELS_DIR/"
echo "Logs: journalctl --user -u linux-rvc-voice-changer.service -f"
echo "Restarting Plasma..."
systemctl --user restart plasma-plasmashell.service
