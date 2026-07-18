#!/bin/bash
set -euo pipefail

BIN_DIR="$HOME/.local/bin"
USER_UNIT_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"

echo "Stopping Linux RVC Voice Changer..."
systemctl --user disable --now linux-rvc-voice-changer.service 2>/dev/null || true
rm -f "$USER_UNIT_DIR/linux-rvc-voice-changer.service"
systemctl --user daemon-reload

rm -f "$BIN_DIR/rvc-voice-changer" "$BIN_DIR/rvc-voice-changer-ctl"
kpackagetool6 -t Plasma/Applet -r org.devl0rd.rvcvoicechanger >/dev/null 2>&1 || true

echo "Removed the service, command links, applet, and live virtual microphone."
echo "Kept voice models and ~/.config/Linux-RVC-Voice-Changer/config.json."
