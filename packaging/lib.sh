#!/usr/bin/env bash

UPDATE_ID="linux-rvc-voice-changer"
UPDATE_TITLE="RVC Voice Changer"
UPDATE_UNIT="$UPDATE_ID-update.service"
UPDATE_LOGIN_UNIT="$UPDATE_ID-login-update.service"
UPDATE_LIB_DIR="/usr/lib/$UPDATE_ID"
UPDATE_STATE_DIR="/var/lib/$UPDATE_ID"
UPDATE_LEGACY_HOOK="/etc/pacman.d/hooks/$UPDATE_ID-update.hook"
USER_STATE_DIR="$HOME/.local/state/$UPDATE_ID"
UPDATE_PENDING="$USER_STATE_DIR/update-pending"
declare -A UPDATE_HOOKS=(
    [pacman]="$UPDATE_ID-update.hook /usr/share/libalpm/hooks/$UPDATE_ID-update.hook 644"
    [dnf]="$UPDATE_ID-update.actions /etc/dnf/libdnf5-plugins/actions.d/$UPDATE_ID-update.actions 644"
    [zypper]="$UPDATE_ID-update.zypp /usr/lib/zypp/plugins/commit/$UPDATE_ID-update 755"
    [apt-get]="$UPDATE_ID-update.apt /etc/apt/apt.conf.d/99$UPDATE_ID-update 644"
)
RVC_OS_ID=$(. /etc/os-release && printf '%s' "$ID")
RVC_ATOMIC=false
if [[ -e /run/ostree-booted || $RVC_OS_ID == steamos ]]; then
    RVC_ATOMIC=true
fi

run_root() {
    if [[ $EUID -eq 0 ]]; then
        "$@"
    else
        sudo "$@"
    fi
}

package_manager() {
    local manager
    for manager in pacman dnf zypper apt-get; do
        if command -v "$manager" >/dev/null; then
            printf '%s\n' "$manager"
            return 0
        fi
    done
    return 1
}

user_unit_dir() {
    printf '%s\n' "${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
}

enable_user_unit() {
    local checkout="$1" unit="$2" units
    units=$(user_unit_dir)
    mkdir -p "$units"
    sed "s|@CHECKOUT@|$checkout|g" "$checkout/packaging/$unit.in" >"$units/$unit"
    systemctl --user daemon-reload
    systemctl --user enable "$unit" >/dev/null 2>&1
}

disable_user_unit() {
    local unit
    unit="$(user_unit_dir)/$1"
    [[ -e $unit ]] || return 0
    systemctl --user disable "$1" >/dev/null 2>&1 || true
    rm -f "$unit"
    systemctl --user daemon-reload
}

remove_legacy_hook() {
    [[ -e $UPDATE_LEGACY_HOOK ]] || return 0
    run_root rm -f "$UPDATE_LEGACY_HOOK"
    local directory
    directory=$(dirname "$UPDATE_LEGACY_HOOK")
    if [[ -z $(ls -A "$directory") ]] && ! pacman -Qoq "$directory" >/dev/null 2>&1; then
        run_root rmdir "$directory"
    fi
}

install_update_hooks() {
    local checkout="$1" owner="$2" manager="$3" source target mode
    read -r source target mode <<<"${UPDATE_HOOKS[$manager]}"
    run_root install -Dm755 "$checkout/packaging/system-update" "$UPDATE_LIB_DIR/system-update"
    run_root install -Dm"$mode" "$checkout/packaging/$source" "$target"
    if [[ $manager == pacman ]] && grep -qa 'NetworkAccess' /usr/lib/libalpm.so.*; then
        run_root sed -i '/^Exec = /a NetworkAccess = allowed' "$target"
    fi
    printf '%s\n%s\n' "$checkout" "$owner" | run_root install -Dm644 /dev/stdin "$UPDATE_STATE_DIR/source"
    remove_legacy_hook
}

register_system_updates() {
    local checkout="$1" aur="$2" manager
    if [[ $aur == true ]] || ! git -C "$checkout" rev-parse --git-dir >/dev/null 2>&1; then
        unregister_system_updates
        return 0
    fi
    if $RVC_ATOMIC; then
        echo "Registering $UPDATE_TITLE to update at login after system updates..."
        enable_user_unit "$checkout" "$UPDATE_LOGIN_UNIT"
        return 0
    fi
    if ! manager=$(package_manager); then
        echo "No supported package manager to hook updates into. Update with: git pull && ./install.sh"
        unregister_system_updates
        return 0
    fi
    echo "Registering $UPDATE_TITLE with system updates..."
    install_update_hooks "$checkout" "$(id -un)" "$manager"
    enable_user_unit "$checkout" "$UPDATE_UNIT"
}

unregister_system_updates() {
    local entry source target mode
    for entry in "${UPDATE_HOOKS[@]}"; do
        read -r source target mode <<<"$entry"
        if [[ -e $target ]]; then
            run_root rm -f "$target"
        fi
    done
    remove_legacy_hook
    if [[ -e $UPDATE_STATE_DIR || -e $UPDATE_LIB_DIR ]]; then
        run_root rm -rf "$UPDATE_STATE_DIR" "$UPDATE_LIB_DIR"
    fi
    disable_user_unit "$UPDATE_UNIT"
    disable_user_unit "$UPDATE_LOGIN_UNIT"
    rm -f "$UPDATE_PENDING"
}

notify_updated() {
    rm -f "$UPDATE_PENDING"
    gdbus call --session --dest org.freedesktop.Notifications --object-path /org/freedesktop/Notifications \
        --method org.freedesktop.Notifications.Notify "$UPDATE_TITLE" 0 system-software-update "$UPDATE_TITLE updated" "$1" '[]' '{}' 10000 >/dev/null 2>&1 || true
}
