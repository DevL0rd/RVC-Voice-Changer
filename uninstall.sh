#!/bin/bash
set -euo pipefail

REPO_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
BIN_DIR="$HOME/.local/bin"
source "$REPO_DIR/packaging/lib.sh"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
USER_UNIT_DIR=$(user_unit_dir)
MODELS_DIR=$(voice_models_dir)

echo "Stopping Linux RVC Voice Changer..."
systemctl --user disable --now linux-rvc-voice-changer.service 2>/dev/null || true
rm -f "$USER_UNIT_DIR/linux-rvc-voice-changer.service"
systemctl --user daemon-reload
unregister_system_updates

for action in toggle-voice-change toggle-translation-out toggle-translation-in; do
    gdbus call --session --dest org.kde.kglobalaccel --object-path /kglobalaccel \
        --method org.kde.KGlobalAccel.unregister linux-rvc-voice-changer "$action" >/dev/null 2>&1 || true
done

rm -f "$BIN_DIR/rvc-voice-changer" "$BIN_DIR/rvc-voice-changer-ctl"
kpackagetool6 -t Plasma/Applet -r org.devl0rd.rvcvoicechanger >/dev/null 2>&1 || true

remove_installed_runtime
rm -rf "$REPO_DIR/.venv" "$REPO_DIR/rvc/models" "$REPO_DIR/plasmoids/org.devl0rd.rvcvoicechanger/contents/ui/lib"
rm -f "$RVC_CONFIG_DIR/installed-revision"
rm -rf "$USER_STATE_DIR"
for directory in "$USER_UNIT_DIR" "$CONFIG_HOME/systemd" "$BIN_DIR" "$HOME/.local/lib" "$DATA_HOME/plasma/plasmoids" "$DATA_HOME/plasma"; do
    if [[ -d $directory ]]; then
        rmdir --ignore-fail-on-non-empty "$directory"
    fi
done

echo "Removed the service, command links, applet, shortcuts, Python runtime, downloaded pitch and speech models, and live virtual microphone."
if [[ -d $MODELS_DIR ]]; then
    echo "Kept voice models in $MODELS_DIR/ and $RVC_CONFIG_DIR/config.json."
else
    echo "Kept $RVC_CONFIG_DIR/config.json."
fi
