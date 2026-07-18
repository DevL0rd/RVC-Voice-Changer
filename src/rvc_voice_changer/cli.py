from __future__ import annotations

import argparse
import json
import urllib.error
import urllib.request


BASE_URL = "http://127.0.0.1:17843/v1"


def request(method: str, path: str, payload: dict[str, object] | None = None) -> dict[str, object]:
    body = json.dumps(payload).encode() if payload is not None else None
    req = urllib.request.Request(
        BASE_URL + path,
        data=body,
        method=method,
        headers={"Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(req, timeout=5) as response:
            return json.load(response)
    except urllib.error.HTTPError as error:
        data = json.load(error)
        raise SystemExit(data.get("error", str(error))) from error
    except urllib.error.URLError as error:
        raise SystemExit(f"Daemon is unavailable: {error.reason}") from error


def main() -> None:
    parser = argparse.ArgumentParser(description="Control Linux RVC Voice Changer")
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("status")
    sub.add_parser("on")
    sub.add_parser("off")
    sub.add_parser("rescan")
    select = sub.add_parser("select")
    select.add_argument("voice", help="Voice folder name")
    args = parser.parse_args()

    if args.command == "status":
        result = request("GET", "/state")
    elif args.command in {"on", "off"}:
        result = request("POST", "/enabled", {"enabled": args.command == "on"})
    elif args.command == "rescan":
        result = request("POST", "/models/rescan", {})
    else:
        result = request("PATCH", "/config", {"model": {"selected": args.voice}})
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
