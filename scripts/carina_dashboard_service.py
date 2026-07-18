#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import logging
import subprocess
import threading
import time
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlsplit


LOGGER = logging.getLogger("CarinaDashboard")
REBUILD_LOCK = threading.Lock()
MAX_REBUILD_AGE_SECONDS = 20


class DashboardApplication:
    def __init__(self, runtime_root: Path) -> None:
        self.runtime_root = runtime_root.resolve()
        self.builder = self.runtime_root / "build_dashboard.py"
        self.output = self.runtime_root / "dist/dashboard.html"
        self.agentops = self.runtime_root / "sources/AgentOps"
        self.codex = self.runtime_root / "sources/Codex"
        self.projects = self.runtime_root / "projects.json"

    def rebuild(self) -> None:
        with REBUILD_LOCK:
            try:
                age = time.time() - self.output.stat().st_mtime
            except OSError:
                age = MAX_REBUILD_AGE_SECONDS + 1
            if age <= MAX_REBUILD_AGE_SECONDS:
                return
            completed = subprocess.run(
                [
                    "/usr/bin/python3",
                    str(self.builder),
                    "--agentops-dir",
                    str(self.agentops),
                    "--codex-dir",
                    str(self.codex),
                    "--project-snapshot",
                    str(self.projects),
                    "--output",
                    str(self.output),
                ],
                capture_output=True,
                text=True,
                timeout=30,
                check=False,
            )
            if completed.returncode != 0:
                raise RuntimeError((completed.stderr or completed.stdout)[-4_000:])

    def dashboard(self) -> bytes:
        self.rebuild()
        return self.output.read_bytes()


class DashboardHandler(BaseHTTPRequestHandler):
    server_version = "CarinaDashboard/1.0"

    @property
    def application(self) -> DashboardApplication:
        app = getattr(self.server, "application", None)
        if not isinstance(app, DashboardApplication):
            raise RuntimeError("dashboard application is unavailable")
        return app

    def do_GET(self) -> None:
        path = urlsplit(self.path).path
        if path == "/health":
            self._write(
                HTTPStatus.OK,
                json.dumps({"success": True, "service": "carina-dashboard"}).encode("utf-8"),
                "application/json; charset=utf-8",
            )
            return
        if path not in {"/", "/dashboard.html"}:
            self._write(HTTPStatus.NOT_FOUND, b"Not found", "text/plain; charset=utf-8")
            return
        try:
            body = self.application.dashboard()
        except (OSError, RuntimeError, subprocess.TimeoutExpired) as exc:
            LOGGER.error("dashboard rebuild failed: %s", exc)
            self._write(
                HTTPStatus.SERVICE_UNAVAILABLE,
                b"Dashboard data refresh failed",
                "text/plain; charset=utf-8",
            )
            return
        self._write(HTTPStatus.OK, body, "text/html; charset=utf-8")

    def log_message(self, format_string: str, *args: object) -> None:
        LOGGER.info("%s %s", self.client_address[0], format_string % args)

    def _write(self, status: int, body: bytes, content_type: str) -> None:
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Security-Policy", "default-src 'none'; style-src 'unsafe-inline'")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("X-Frame-Options", "DENY")
        self.end_headers()
        self.wfile.write(body)


class DashboardServer(ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True

    def __init__(self, address: tuple[str, int], application: DashboardApplication) -> None:
        self.application = application
        super().__init__(address, DashboardHandler)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Local read-only CARINA dashboard server")
    parser.add_argument("--runtime-root", type=Path, required=True)
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=51003)
    return parser.parse_args()


def main() -> int:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(name)s: %(message)s")
    args = parse_args()
    if not 1 <= args.port <= 65535:
        raise ValueError("port must be between 1 and 65535")
    server = DashboardServer((args.host, args.port), DashboardApplication(args.runtime_root))
    LOGGER.info("dashboard listening on http://%s:%d", args.host, args.port)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
