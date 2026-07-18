#!/bin/bash
set -euo pipefail

REPO_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
if [[ ! -f "$REPO_DIR/src/rvc_voice_changer/daemon.py" ]]; then
    echo "Repository files are incomplete."
    exit 1
fi

missing=0
for command_name in python3 pw-dump pw-loopback pw-cat kpackagetool6 curl; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
        echo "Missing required command: $command_name"
        missing=1
    fi
done
if (( missing )); then
    echo "Install the missing PipeWire/Plasma dependencies, then run this again."
    exit 1
fi

chmod +x "$REPO_DIR/bin/rvc-voice-changer" "$REPO_DIR/bin/rvc-voice-changer-ctl"

echo "Creating the isolated RVC runtime..."
python3 -m venv "$REPO_DIR/.venv"
"$REPO_DIR/.venv/bin/python" -m pip install --upgrade pip setuptools wheel

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

case "$TORCH_BACKEND" in
    cuda)
        echo "Installing NVIDIA CUDA PyTorch..."
        "$REPO_DIR/.venv/bin/python" -m pip install --upgrade --force-reinstall \
            "torch==2.11.0" "torchaudio==2.11.0"
        ;;
    rocm)
        echo "Installing AMD ROCm PyTorch..."
        "$REPO_DIR/.venv/bin/python" -m pip install --upgrade --force-reinstall \
            --index-url https://repo.amd.com/rocm/whl-multi-arch/ \
            "torch[device-all]" torchaudio
        ;;
    cpu)
        echo "Installing CPU-only PyTorch..."
        "$REPO_DIR/.venv/bin/python" -m pip install --upgrade --force-reinstall \
            --index-url https://download.pytorch.org/whl/cpu \
            "torch==2.11.0" "torchaudio==2.11.0"
        ;;
    custom)
        echo "Installing PyTorch from custom index: $TORCH_INDEX_URL"
        "$REPO_DIR/.venv/bin/python" -m pip install --upgrade --force-reinstall \
            --index-url "$TORCH_INDEX_URL" torch torchaudio
        ;;
    *)
        echo "Unsupported RVC_TORCH_BACKEND: $TORCH_BACKEND (use auto, cuda, rocm, or cpu)"
        exit 1
        ;;
esac

if [[ "$TORCH_BACKEND" == rocm ]] && ! "$REPO_DIR/.venv/bin/python" - <<'PY'
import sys
import torch
sys.exit(0 if torch.cuda.is_available() and torch.version.hip else 1)
PY
then
    if (( TORCH_BACKEND_WAS_AUTO )); then
        echo "The AMD GPU is not usable through ROCm; falling back to CPU-only PyTorch."
        "$REPO_DIR/.venv/bin/python" -m pip install --upgrade --force-reinstall \
            --index-url https://download.pytorch.org/whl/cpu \
            "torch==2.11.0" "torchaudio==2.11.0"
        TORCH_BACKEND=cpu
    else
        echo "ROCm was requested, but PyTorch cannot use an AMD GPU on this machine."
        exit 1
    fi
fi

"$REPO_DIR/.venv/bin/python" -m pip install -r "$REPO_DIR/requirements-runtime.txt"

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

download_asset "predictors/rmvpe.pt" "$REPO_DIR/rvc/models/predictors/rmvpe.pt"
download_asset "predictors/fcpe.pt" "$REPO_DIR/rvc/models/predictors/fcpe.pt"
download_asset "embedders/contentvec/pytorch_model.bin" "$REPO_DIR/rvc/models/embedders/contentvec/pytorch_model.bin"
download_asset "embedders/contentvec/config.json" "$REPO_DIR/rvc/models/embedders/contentvec/config.json"

BIN_DIR="$HOME/.local/bin"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/Linux-RVC-Voice-Changer"
USER_UNIT_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
PLASMOID="$REPO_DIR/plasmoids/org.devl0rd.rvcvoicechanger"

mkdir -p "$BIN_DIR" "$CONFIG_DIR" "$USER_UNIT_DIR"
ln -sfn "$REPO_DIR/bin/rvc-voice-changer" "$BIN_DIR/rvc-voice-changer"
ln -sfn "$REPO_DIR/bin/rvc-voice-changer-ctl" "$BIN_DIR/rvc-voice-changer-ctl"

if [[ ! -f "$CONFIG_DIR/config.json" ]]; then
    cp "$REPO_DIR/config.example.json" "$CONFIG_DIR/config.json"
    echo "Created $CONFIG_DIR/config.json"
fi

sed "s|@REPO_DIR@|$REPO_DIR|g" \
    "$REPO_DIR/systemd/linux-rvc-voice-changer.service.in" \
    > "$USER_UNIT_DIR/linux-rvc-voice-changer.service"
systemctl --user daemon-reload
systemctl --user enable linux-rvc-voice-changer.service
systemctl --user restart linux-rvc-voice-changer.service
echo "Enabled linux-rvc-voice-changer.service"

if kpackagetool6 -t Plasma/Applet -u "$PLASMOID" >/dev/null 2>&1; then
    echo "Upgraded RVC Voice Changer Plasma applet"
else
    kpackagetool6 -t Plasma/Applet -i "$PLASMOID" >/dev/null
    echo "Installed RVC Voice Changer Plasma applet"
fi

"$REPO_DIR/.venv/bin/python" - <<'PY'
import torch
if torch.cuda.is_available():
    platform = "AMD ROCm" if torch.version.hip else "NVIDIA CUDA"
    print(f"Inference runtime: {platform} GPU + CPU")
else:
    print("Inference runtime: CPU")
PY

echo
echo "Installed. Add 'RVC Voice Changer' from Plasma's Add Widgets menu."
echo "Voice folders: $REPO_DIR/models/"
echo "Logs: journalctl --user -u linux-rvc-voice-changer.service -f"
