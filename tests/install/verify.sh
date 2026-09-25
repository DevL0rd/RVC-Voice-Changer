#!/usr/bin/env bash
set -uo pipefail

checkout="$1"
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
units="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"

mic_ready() {
    "$HOME/.local/bin/rvc-voice-changer-ctl" status | python3 -c 'import json, sys; sys.exit(0 if json.load(sys.stdin)["runtime"]["virtual_microphone"] else 1)'
}
for _ in $(seq 180); do
    mic_ready >/dev/null 2>&1 && break
    systemctl --user is-active --quiet linux-rvc-voice-changer.service || break
    sleep 1
done

check "linux-rvc-voice-changer.service runs" "systemctl --user is-active linux-rvc-voice-changer.service"
check "the service runs from the installed copy" "systemctl --user show -p ExecStart --value linux-rvc-voice-changer.service | grep -F \"\${XDG_DATA_HOME:-\$HOME/.local/share}/Linux-RVC-Voice-Changer/runtime/bin/rvc-voice-changer\""
check "no user unit points into the checkout" "! grep -rqF '$checkout' '$units'"
check "no command link points into the checkout" "! find '$HOME/.local/bin' -lname '$checkout/*' | grep ."
check "rvc-voice-changer-ctl answers and the virtual microphone is up" "mic_ready"
check "RVC Virtual Microphone is in PipeWire" "pw-dump | grep '\"node.name\": \"rvc_virtual_microphone\"'"
check "the global shortcuts are registered" "gdbus call --session --dest org.kde.kglobalaccel --object-path /kglobalaccel --method org.kde.KGlobalAccel.allComponents | grep linux_rvc_voice_changer"
check "the applet is installed" "test -f $applet/metadata.json"
check "the applet has the shared components" "test -f $applet/contents/ui/lib/PopupShell.qml"
check "the system update hook is registered" "test -f $hook"
if grep -qa NetworkAccess /usr/lib/libalpm.so.*; then
    check "the system update hook can fetch updates" "grep -q 'NetworkAccess = allowed' $hook"
else
    echo "note: $(pacman -Q pacman) runs hooks with network access and has no NetworkAccess option"
    check "the system update hook leaves out the NetworkAccess option this pacman doesn't know" "! grep -q NetworkAccess $hook"
fi
check "the update unit is enabled" "systemctl --user is-enabled linux-rvc-voice-changer-update.service"
check "the updater runs from its installed copy" "test -x $HOME/.local/lib/linux-rvc-voice-changer/system-update && grep -q '^ExecStart=$HOME/.local/lib/linux-rvc-voice-changer/system-update$' $units/linux-rvc-voice-changer-update.service"
check "Plasma runs" "systemctl --user is-active plasma-plasmashell.service"
if ((failed)); then
    echo "--- rvc-voice-changer-ctl status"
    "$HOME/.local/bin/rvc-voice-changer-ctl" status 2>&1 | tail -n 40
    echo "--- linux-rvc-voice-changer.service log"
    journalctl --user -u linux-rvc-voice-changer.service --no-pager -n 80 2>&1
    echo "--- PipeWire"
    systemctl --user --no-pager status pipewire.service wireplumber.service pipewire-pulse.service 2>&1 | tail -n 40
fi
exit "$failed"
