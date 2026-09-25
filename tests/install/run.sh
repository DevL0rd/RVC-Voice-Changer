#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/../.."
CONTAINER="rvc-install-test"
IMAGE="${RVC_TEST_IMAGE:-archlinux:latest}"
CHECKOUT="/home/tester/RVC-Voice-Changer"
MOVED="/home/tester/moved"
ASSETS=(predictors/rmvpe.pt predictors/fcpe.pt embedders/contentvec/pytorch_model.bin embedders/contentvec/config.json)
SESSION_ENV=(-e USER=tester -e LOGNAME=tester -e XDG_RUNTIME_DIR=/run/user/1000
    -e DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus -e WAYLAND_DISPLAY=wayland-0 -e RVC_TORCH_BACKEND=cpu)

as_root() {
    docker exec "$CONTAINER" "$@"
}

as_tester() {
    docker exec -u tester -w "$CHECKOUT" "${SESSION_ENV[@]}" "$CONTAINER" "$@"
}

as_tester_at_home() {
    docker exec -u tester -w /home/tester "${SESSION_ENV[@]}" "$CONTAINER" "$@"
}

step() {
    printf '\n==> %s\n' "$1"
}

step "Starting an Arch Linux system with Plasma"
docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
docker run -d --name "$CONTAINER" --privileged --cgroupns=private --tmpfs /run --tmpfs /run/lock "$IMAGE" /usr/lib/systemd/systemd >/dev/null
trap 'docker rm -f "$CONTAINER" >/dev/null 2>&1 || true' EXIT
as_root pacman -Syu --noconfirm --needed plasma-desktop sudo git
as_root bash -c 'useradd -m -u 1000 tester && echo "tester ALL=(ALL) NOPASSWD: ALL" >/etc/sudoers.d/tester'
docker cp . "$CONTAINER:$CHECKOUT"
docker cp tests/install/. "$CONTAINER:/opt/install-test"
as_root chown -R tester: "$CHECKOUT"
as_tester git config --global --add safe.directory '*'

step "Installing the voice changer's dependencies"
as_tester packaging/dependencies.sh

step "Leaving a voice, placeholder pitch and speech models and a Python runtime in the checkout like older versions did"
as_tester bash -c 'mkdir -p models/TestVoice .venv/bin && echo placeholder >models/TestVoice/model.pth'
for asset in "${ASSETS[@]}"; do
    as_tester bash -c 'mkdir -p "$(dirname "rvc/models/$1")" && echo placeholder >"rvc/models/$1"' _ "$asset"
done

step "Starting a Plasma session"
as_root bash -c 'loginctl enable-linger tester; for _ in $(seq 60); do [[ -S /run/user/1000/bus ]] && exit 0; sleep 1; done; exit 1'
as_tester /opt/install-test/session.sh
as_root /opt/install-test/snapshot.sh before

step "Installing the voice changer"
as_tester ./install.sh

step "Checking that the old checkout files moved out of the checkout"
as_tester /opt/install-test/migrated.sh "$CHECKOUT" "${ASSETS[@]}"

step "Checking that the voice changer runs"
as_tester /opt/install-test/verify.sh "$CHECKOUT"

step "Moving the checkout away and checking that the voice changer still runs"
as_tester_at_home mv "$CHECKOUT" "$MOVED"
as_tester_at_home systemctl --user restart linux-rvc-voice-changer.service
as_tester_at_home /opt/install-test/verify.sh "$CHECKOUT"
as_tester_at_home mv "$MOVED" "$CHECKOUT"

step "Uninstalling the voice changer"
as_tester ./uninstall.sh
sleep 10

step "Checking that uninstalling left the system as it was and kept the voice"
as_root /opt/install-test/snapshot.sh after
as_root /opt/install-test/compare.sh
as_tester test -f /home/tester/.local/share/Linux-RVC-Voice-Changer/models/TestVoice/model.pth
leftovers=$(as_tester git status --porcelain --ignored)
if [[ -n $leftovers ]]; then
    printf 'Uninstalling left files in the checkout:\n%s\n' "$leftovers"
    exit 1
fi
