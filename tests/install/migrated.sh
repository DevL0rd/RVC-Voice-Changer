#!/usr/bin/env bash
set -uo pipefail

checkout="$1"
shift
data="${XDG_DATA_HOME:-$HOME/.local/share}/Linux-RVC-Voice-Changer"
failed=0
check() {
    if eval "$2" >/dev/null 2>&1; then
        echo "ok: $1"
    else
        echo "FAILED: $1"
        failed=1
    fi
}

check "the old voice moved to the voice models folder" "test -f '$data/models/TestVoice/model.pth'"
check "the checkout's models folder is gone" "test ! -e '$checkout/models'"
for asset in "$@"; do
    check "$asset moved to the installed assets" "test -s '$data/assets/$asset'"
done
check "the checkout's downloaded models folder is gone" "test ! -e '$checkout/rvc/models'"
check "the checkout's Python runtime is gone" "test ! -e '$checkout/.venv'"
check "the checkout's staged widget components are gone" "! compgen -G '$checkout/plasmoids/*/contents/ui/lib'"
check "the Python runtime is installed" "test -x '$data/venv/bin/python'"
leftovers=$(git -C "$checkout" status --porcelain --ignored)
if [[ -n $leftovers ]]; then
    printf 'FAILED: installing left files in the checkout:\n%s\n' "$leftovers"
    failed=1
else
    echo "ok: installing left nothing in the checkout"
fi
exit "$failed"
