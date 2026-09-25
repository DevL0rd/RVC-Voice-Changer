#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

ARCH_PACKAGES=(python pipewire pipewire-pulse wireplumber libpulse kpackage kdeclarative qt6-declarative glib2 curl git)
FEDORA_PACKAGES=(python3 pipewire-utils pipewire-pulseaudio wireplumber pulseaudio-utils kf6-kpackage kf6-kdeclarative qt6-qtdeclarative glib2 curl git libdnf5-plugin-actions)
SUSE_PACKAGES=(python3 pipewire-tools pipewire-pulseaudio wireplumber pulseaudio-utils kf6-kpackage kf6-kdeclarative-imports qt6-declarative-imports glib2-tools curl git)
DEBIAN_PACKAGES=(python3 python3-venv pipewire-bin pipewire-pulse wireplumber pulseaudio-utils kpackagetool6 qml6-module-org-kde-kquickcontrols qml6-module-qt-labs-folderlistmodel qml6-module-qtquick-shapes libglib2.0-bin curl git)

missing_packages() {
    local package
    case "$1" in
    pacman) pacman -T "${@:2}" || true ;;
    dnf | zypper)
        for package in "${@:2}"; do
            rpm -q --whatprovides "$package" >/dev/null 2>&1 || printf '%s\n' "$package"
        done
        ;;
    apt-get)
        for package in "${@:2}"; do
            [[ $(dpkg-query -W -f='${db:Status-Status}' "$package" 2>/dev/null) == installed ]] || printf '%s\n' "$package"
        done
        ;;
    esac
}

if [[ -e /run/ostree-booted ]]; then
    manager=dnf
elif ! manager=$(package_manager); then
    echo "Unsupported package manager. Install Python 3 with venv, PipeWire with WirePlumber and PipeWire-Pulse, pactl, kpackagetool6, curl and git, then run ./install.sh --skip-deps"
    exit 1
fi
case "$manager" in
pacman) packages=("${ARCH_PACKAGES[@]}") ;;
dnf) packages=("${FEDORA_PACKAGES[@]}") ;;
zypper) packages=("${SUSE_PACKAGES[@]}") ;;
apt-get) packages=("${DEBIAN_PACKAGES[@]}") ;;
esac
if $RVC_ATOMIC; then
    mapfile -t packages < <(printf '%s\n' "${packages[@]}" | grep -vx libdnf5-plugin-actions)
fi

mapfile -t missing < <(missing_packages "$manager" "${packages[@]}")
((${#missing[@]})) || exit 0

if [[ $RVC_OS_ID == steamos ]]; then
    echo "This SteamOS build is missing ${missing[*]}, and SteamOS can't keep extra system packages across updates."
    echo "Update SteamOS, then run ./install.sh again."
    exit 1
elif $RVC_ATOMIC; then
    echo "This system is missing ${missing[*]}. Add them to the system image with:"
    echo "  rpm-ostree install ${missing[*]}"
    echo "Then reboot and run ./install.sh again."
    exit 1
fi

echo "Installing missing system packages: ${missing[*]}"
case "$manager" in
pacman) run_root pacman -S --needed --noconfirm "${missing[@]}" ;;
dnf) run_root dnf install -y "${missing[@]}" ;;
zypper) run_root zypper --non-interactive install "${missing[@]}" ;;
apt-get) run_root apt-get install -y "${missing[@]}" ;;
esac
