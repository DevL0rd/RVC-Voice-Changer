#!/usr/bin/env bash
set -uo pipefail

failed=0
check() {
    if eval "$2" >/dev/null 2>&1; then
        echo "ok: $1"
    else
        echo "FAILED: $1"
        failed=1
    fi
}

applet="${XDG_DATA_HOME:-$HOME/.local/share}/plasma/plasmoids/org.devl0rd.rvcvoicechanger"
hook=/usr/share/libalpm/hooks/linux-rvc-voice-changer-update.hook
check "linux-rvc-voice-changer.service runs" "systemctl --user is-active linux-rvc-voice-changer.service"
check "rvc-voice-changer-ctl answers" "$HOME/.local/bin/rvc-voice-changer-ctl status | python3 -c 'import json, sys; assert json.load(sys.stdin)[\"runtime\"][\"virtual_microphone\"]'"
check "RVC Virtual Microphone is in PipeWire" "pw-dump | grep -q '\"node.name\": \"rvc_virtual_microphone\"'"
check "the global shortcuts are registered" "gdbus call --session --dest org.kde.kglobalaccel --object-path /kglobalaccel --method org.kde.KGlobalAccel.allComponents | grep -q linux_rvc_voice_changer"
check "the applet is installed" "test -f $applet/metadata.json"
check "the applet has the shared components" "test -f $applet/contents/ui/lib/PopupShell.qml"
check "the system update hook is registered" "test -f $hook"
check "the system update hook can fetch updates" "grep -q 'NetworkAccess = allowed' $hook"
check "the update unit is enabled" "systemctl --user is-enabled linux-rvc-voice-changer-update.service"
check "Plasma runs" "systemctl --user is-active plasma-plasmashell.service"
exit "$failed"
