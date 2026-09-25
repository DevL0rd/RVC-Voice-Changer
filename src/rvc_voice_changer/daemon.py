from __future__ import annotations

import argparse
import signal
import sys
import threading

from .api import ApiServer, Application
from .config import ConfigStore
from .engine import VoiceEngine


def main() -> None:
    parser = argparse.ArgumentParser(description="Linux RVC Voice Changer daemon")
    parser.add_argument("--host", help="API bind address (localhost only)")
    parser.add_argument("--port", type=int, help="API port")
    args = parser.parse_args()

    config = ConfigStore()
    host = args.host or config.data["server"]["host"]
    port = args.port or config.data["server"]["port"]
    if host not in {"127.0.0.1", "localhost", "::1"}:
        print("Refusing to expose the unauthenticated control API beyond localhost", file=sys.stderr)
        raise SystemExit(2)

    app = Application(config, VoiceEngine())
    server = ApiServer((host, port), app)

    def stop(_signum: int, _frame: object) -> None:
        # BaseServer.shutdown must run outside the serve_forever thread.
        threading.Thread(target=server.shutdown, daemon=True).start()

    signal.signal(signal.SIGINT, stop)
    signal.signal(signal.SIGTERM, stop)
    print(f"Linux RVC Voice Changer API listening on http://{host}:{port}", flush=True)
    try:
        server.serve_forever(poll_interval=0.25)
    finally:
        server.server_close()
        app.close()


if __name__ == "__main__":
    main()
