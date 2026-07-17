from __future__ import annotations

import asyncio
import json
import logging
import uuid
from typing import Any

from api import AgentRouter, BridgeAPIError, authorized


LOGGER = logging.getLogger("CarinaBridge.WebSocket")
MAX_MESSAGE_BYTES = 256_000


class CarinaWebSocketServer:
    def __init__(self, host: str, port: int, shared_secret: str, router: AgentRouter) -> None:
        self.host = host
        self.port = port
        self.shared_secret = shared_secret.encode("utf-8")
        self.router = router

    async def serve(self) -> None:
        try:
            from websockets.asyncio.server import serve
        except ImportError as exc:
            raise RuntimeError("Install apps/bridge/requirements.txt before starting the bridge") from exc
        async with serve(
            self._handler,
            self.host,
            self.port,
            max_size=MAX_MESSAGE_BYTES,
            ping_interval=20,
            ping_timeout=20,
            close_timeout=5,
        ):
            LOGGER.info("WebSocket listening on %s:%d", self.host, self.port)
            await asyncio.Future()

    async def _handler(self, socket: Any) -> None:
        request = getattr(socket, "request", None)
        headers = getattr(request, "headers", {})
        if not authorized(str(headers.get("Authorization", "")), self.shared_secret):
            await socket.close(code=4401, reason="unauthorized")
            return
        await socket.send(json.dumps({"type": "status", "status": "connected", "service": "carina-openclaw-bridge"}))
        try:
            async for raw_message in socket:
                await self._handle_message(socket, raw_message)
        except Exception as exc:
            LOGGER.warning("WebSocket client closed: %s", type(exc).__name__)

    async def _handle_message(self, socket: Any, raw_message: Any) -> None:
        if not isinstance(raw_message, str):
            await self._send_error(socket, "binary messages are not supported")
            return
        try:
            body = json.loads(raw_message)
        except json.JSONDecodeError:
            await self._send_error(socket, "message must be valid JSON")
            return
        if not isinstance(body, dict):
            await self._send_error(socket, "message must be a JSON object")
            return
        if body.get("type") == "ping":
            await socket.send(json.dumps({"type": "pong"}))
            return
        command = body.get("command")
        if not isinstance(command, str) or not command.strip():
            await self._send_error(socket, "command must be a non-empty string")
            return
        request = {
            "request_id": str(uuid.uuid4()),
            "conversation_id": str(uuid.uuid4()),
            "route": str(body.get("route", "openclaw")),
            "message": command,
            "system_instruction": "You are CARINA, the authenticated iPhone interface for OpenClaw.",
        }
        try:
            response = await asyncio.to_thread(self.router.message, request)
            await socket.send(json.dumps({"type": "agent_response", **response}, ensure_ascii=False))
        except BridgeAPIError as exc:
            await self._send_error(socket, str(exc), status=exc.status)

    @staticmethod
    async def _send_error(socket: Any, message: str, status: int = 400) -> None:
        await socket.send(json.dumps({"type": "error", "status": status, "error": message[:500]}))
