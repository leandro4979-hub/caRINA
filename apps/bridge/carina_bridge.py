from __future__ import annotations

import argparse
import asyncio
import json
import logging
import os
import signal
import socket
import subprocess
import threading
import time
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any, Mapping
from urllib.parse import urlsplit

from api import (
    AgentRouter,
    BridgeAPIError,
    authorized,
    generate_shared_secret,
    load_runtime_environment,
)
from websocket_server import CarinaWebSocketServer


PROJECT_ROOT = Path(os.environ.get("CARINA_STATE_ROOT", Path(__file__).resolve().parents[2])).expanduser().resolve()
SECRET_PATH = PROJECT_ROOT / ".bridge-secret"
MAX_REQUEST_BYTES = 256_000
REQUEST_SLOTS = threading.BoundedSemaphore(8)
LOGGER = logging.getLogger("CarinaBridge")


class BridgeApplication:
    def __init__(self, shared_secret: str, router: AgentRouter | None = None) -> None:
        self.shared_secret = shared_secret.encode("utf-8")
        self.router = router or AgentRouter()
        self.started_at = time.time()

    def authorized(self, header: str) -> bool:
        return authorized(header, self.shared_secret)

    def health(self) -> dict[str, Any]:
        return {
            "success": True,
            "uptime_seconds": round(time.time() - self.started_at, 3),
            **self.router.health(),
        }

    def dispatch(self, path: str, payload: Mapping[str, Any]) -> tuple[int, Mapping[str, Any]]:
        try:
            if path == "/v1/agent/message":
                return HTTPStatus.OK, self.router.message(payload)
            if path == "/v1/actions/execute":
                return HTTPStatus.OK, self.router.execute(payload)
            raise BridgeAPIError(404, "unknown endpoint")
        except BridgeAPIError as exc:
            return exc.status, {"success": False, "error": str(exc)}


class BridgeRequestHandler(BaseHTTPRequestHandler):
    server_version = "CarinaOpenClawBridge/1.0"

    @property
    def app(self) -> BridgeApplication:
        application = getattr(self.server, "application", None)
        if not isinstance(application, BridgeApplication):
            raise RuntimeError("bridge application is not configured")
        return application

    def do_GET(self) -> None:
        if not self.app.authorized(self.headers.get("Authorization", "")):
            self._write_json(HTTPStatus.UNAUTHORIZED, {"success": False, "error": "unauthorized"})
            return
        path = urlsplit(self.path).path
        if path in {"/health", "/v1/health"}:
            self._write_json(HTTPStatus.OK, self.app.health())
            return
        self._write_json(HTTPStatus.NOT_FOUND, {"success": False, "error": "not found"})

    def do_POST(self) -> None:
        if not self.app.authorized(self.headers.get("Authorization", "")):
            self._write_json(HTTPStatus.UNAUTHORIZED, {"success": False, "error": "unauthorized"})
            return
        try:
            content_length = int(self.headers.get("Content-Length", ""))
        except ValueError:
            self._write_json(HTTPStatus.BAD_REQUEST, {"success": False, "error": "invalid content length"})
            return
        if not 1 <= content_length <= MAX_REQUEST_BYTES:
            self._write_json(HTTPStatus.REQUEST_ENTITY_TOO_LARGE, {"success": False, "error": "request is too large"})
            return
        if not REQUEST_SLOTS.acquire(blocking=False):
            self._write_json(HTTPStatus.SERVICE_UNAVAILABLE, {"success": False, "error": "bridge is busy"})
            return
        try:
            try:
                body = json.loads(self.rfile.read(content_length).decode("utf-8"))
            except (UnicodeDecodeError, json.JSONDecodeError):
                self._write_json(HTTPStatus.BAD_REQUEST, {"success": False, "error": "body must be valid JSON"})
                return
            if not isinstance(body, Mapping):
                self._write_json(HTTPStatus.BAD_REQUEST, {"success": False, "error": "body must be a JSON object"})
                return
            status, response = self.app.dispatch(urlsplit(self.path).path, body)
            self._write_json(status, response)
        finally:
            REQUEST_SLOTS.release()

    def log_message(self, format_string: str, *args: object) -> None:
        LOGGER.info("%s %s", self.client_address[0], format_string % args)

    def _write_json(self, status: int, body: Mapping[str, Any]) -> None:
        encoded = json.dumps(body, ensure_ascii=False, default=str).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(encoded)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.end_headers()
        self.wfile.write(encoded)


class BridgeHTTPServer(ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True

    def __init__(self, address: tuple[str, int], application: BridgeApplication) -> None:
        self.application = application
        super().__init__(address, BridgeRequestHandler)


def discover_host() -> str:
    configured = os.environ.get("CARINA_BRIDGE_HOST", "").strip()
    if configured:
        return configured
    for command in (
        ["/usr/local/bin/tailscale", "ip", "-4"],
        ["/opt/homebrew/bin/tailscale", "ip", "-4"],
        ["tailscale", "ip", "-4"],
        ["/Applications/Tailscale.app/Contents/MacOS/Tailscale", "ip", "-4"],
    ):
        try:
            result = subprocess.run(command, capture_output=True, text=True, timeout=5, check=False)
        except (OSError, subprocess.TimeoutExpired):
            continue
        address = result.stdout.strip().splitlines()[0] if result.stdout.strip() else ""
        if result.returncode == 0 and address.startswith("100."):
            return address
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as probe:
        try:
            probe.connect(("192.0.2.1", 80))
            return str(probe.getsockname()[0])
        except OSError:
            return "127.0.0.1"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Authenticated CARINA OpenClaw bridge")
    parser.add_argument("--host", default=None)
    parser.add_argument("--http-port", type=int, default=51001)
    parser.add_argument("--websocket-port", type=int, default=51002)
    parser.add_argument("--copy-pairing-token", action="store_true")
    return parser.parse_args()


async def run_servers(host: str, http_port: int, websocket_port: int, secret: str) -> None:
    router = AgentRouter()
    application = BridgeApplication(secret, router)
    http_server = BridgeHTTPServer((host, http_port), application)
    http_thread = threading.Thread(target=http_server.serve_forever, name="CarinaHTTP", daemon=True)
    http_thread.start()
    LOGGER.info("HTTP listening on %s:%d", host, http_port)
    try:
        await CarinaWebSocketServer(host, websocket_port, secret, router).serve()
    finally:
        http_server.shutdown()
        http_server.server_close()
        http_thread.join(timeout=5)


def main() -> int:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(name)s: %(message)s")
    load_runtime_environment(PROJECT_ROOT)
    args = parse_args()
    if not 1 <= args.http_port <= 65535 or not 1 <= args.websocket_port <= 65535:
        raise ValueError("bridge ports must be between 1 and 65535")
    secret = generate_shared_secret(SECRET_PATH)
    if args.copy_pairing_token:
        subprocess.run(["/usr/bin/pbcopy"], input=secret, text=True, timeout=5, check=True)
        LOGGER.info("Pairing token copied to the macOS clipboard")
        return 0
    host = args.host or discover_host()
    try:
        asyncio.run(run_servers(host, args.http_port, args.websocket_port, secret))
    except KeyboardInterrupt:
        LOGGER.info("Bridge stopped")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
