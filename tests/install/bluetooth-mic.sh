#!/usr/bin/env bash
set -uo pipefail

SOURCE="bluez_input.E8:07:BF:9C:1D:B7"
API="http://127.0.0.1:17843/v1"

state() {
    curl -s "$API/state" | python3 -c "import json, sys; state = json.load(sys.stdin); runtime = json.load(sys.stdin)['runtime']; print(runtime.get('status', ''), '|', runtime.get('error') or '')"
}

input_device() {
    curl -s "$API/state" | python3 -c "import json, sys; print(json.load(sys.stdin)['config']['audio'].get('input_device') or '')"
}

configure_input() {
    curl -s -X PATCH -H 'Content-Type: application/json' "$API/config" \
        -d "$(python3 -c "import json, sys; print(json.dumps({'audio': {'input_device': sys.argv[1]}}))" "$1")"
    echo
}

pw-loopback --capture-props 'media.class=Audio/Sink node.name="test_bluetooth_sink" audio.position=[ MONO ]' \
    --playback-props "media.class=Audio/Source node.name=\"$SOURCE\" node.description=\"Test Bluetooth Microphone\" audio.position=[ MONO ]" &
fake=$!
previous=$(input_device)
trap 'configure_input "$previous" >/dev/null; kill "$fake" 2>/dev/null' EXIT

for _ in $(seq 50); do
    objects=$(pw-dump)
    grep -qF "\"$SOURCE\"" <<<"$objects" && break
    sleep 0.2
done
grep -qF "\"$SOURCE\"" <<<"$(pw-dump)" || { echo "FAILED: the test Bluetooth microphone did not appear in PipeWire"; exit 1; }

curl -s -X POST -H 'Content-Type: application/json' "$API/enabled" -d '{"enabled": false}' >/dev/null
response=$(configure_input "$SOURCE")
echo "Selecting $SOURCE as the input: $response"
if python3 -c "import json, sys; sys.exit(0 if 'error' in json.loads(sys.argv[1]) else 1)" "$response"; then
    echo "FAILED: the voice changer refused a microphone whose name has colons"
    exit 1
fi

linked() {
    grep -A3 -F "$SOURCE:" <<<"$links" | grep -qF "rvc_bypass_capture"
}

for _ in $(seq 100); do
    current=$(state)
    links=$(pw-link -l)
    [[ $current == *"| "?* ]] && break
    linked && break
    sleep 0.2
done
echo "state: $current"
if [[ $current != "bypass | " ]]; then
    echo "FAILED: the voice changer did not use a microphone whose name has colons"
    exit 1
fi
if ! linked; then
    echo "FAILED: PipeWire did not link $SOURCE to the voice changer"
    echo "$links"
    exit 1
fi
echo "ok: a microphone whose name has colons feeds the RVC Virtual Microphone"
