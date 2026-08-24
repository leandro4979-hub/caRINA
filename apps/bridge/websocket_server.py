from __future__ import annotations

import asyncio
import json
import logging
import socket
import uuid
from typing import Any

from api import AgentRouter, BridgeAPIError, authorized
from realtime import RealtimeSidebandController


LOGGER = logging.getLogger("CarinaBridge.WebSocket")
MAX_MESSAGE_BYTES = 256_000
PING_FIELDS = frozenset({"type"})
LEGACY_COMMAND_FIELDS = frozenset({"type", "command", "route"})
REALTIME_ATTACH_FIELDS = frozenset({"type", "call_id"})


class CarinaWebSocketServer:
    def __init__(
        self,
        host: str,
        port: int,
        shared_secret: str,
        router: AgentRouter,
        realtime_sideband: RealtimeSidebandController | None = None,
    ) -> None:
        self.host = host
        self.port = port
        self.shared_secret = shared_secret.encode("utf-8")
        self.router = router
        self.realtime_sideband = realtime_sideband or RealtimeSidebandController()

    async def serve(self) -> None:
        try:
            from websockets.asyncio.server import serve
        except ImportError as exc:
            raise RuntimeError("Install apps/bridge/requirements.txt before starting the bridge") from exc
        listener = self._listener_socket()
        try:
            async with serve(
                self._handler,
                sock=listener,
                max_size=MAX_MESSAGE_BYTES,
                ping_interval=20,
                ping_timeout=20,
                close_timeout=5,
            ):
                LOGGER.info("WebSocket listening on %s:%d", self.host, self.port)
                await asyncio.Future()
        finally:
            listener.close()

    def _listener_socket(self) -> socket.socket:
        family = socket.AF_INET6 if ":" in self.host else socket.AF_INET
        listener = socket.socket(family, socket.SOCK_STREAM)
        try:
            listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            if family == socket.AF_INET6:
                listener.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 0)
            listener.bind((self.host, self.port))
            listener.listen(socket.SOMAXCONN)
            listener.setblocking(False)
            return listener
        except Exception:
            listener.close()
            raise

    async def _handler(self, socket: Any) -> None:
        request = getattr(socket, "request", None)
        headers = getattr(request, "headers", {})
        if not authorized(str(headers.get("Authorization", "")), self.shared_secret):
            await socket.close(code=4401, reason="unauthorized")
            return

        sideband_tasks: set[asyncio.Task[None]] = set()
        await socket.send(json.dumps({"type": "status", "status": "connected", "service": "carina-openclaw-bridge"}))
        try:
            async for raw_message in socket:
                await self._handle_message(socket, raw_message, sideband_tasks)
        except Exception as exc:
            LOGGER.warning("WebSocket client closed: %s", type(exc).__name__)
        finally:
            for task in sideband_tasks:
                task.cancel()
            if sideband_tasks:
                await asyncio.gather(*sideband_tasks, return_exceptions=True)

    async def _handle_message(
        self,
        socket: Any,
        raw_message: Any,
        sideband_tasks: set[asyncio.Task[None]] | None = None,
    ) -> None:
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

        try:
            if body.get("type") == "realtime_attach":
                call_id = self.normalize_realtime_attach(body)
                tasks = sideband_tasks if sideband_tasks is not None else set()
                active = [task for task in tasks if not task.done()]
                if active:
                    raise BridgeAPIError(409, "a Realtime sideband is already attached")
                task = asyncio.create_task(self._run_realtime_sideband(socket, call_id))
                tasks.add(task)
                task.add_done_callback(tasks.discard)
                await socket.send(json.dumps({"type": "realtime_sideband", "status": "attaching", "call_id": call_id}))
                return

            request = self.normalize_envelope(body)
            if request is None:
                await socket.send(json.dumps({"type": "pong"}))
                return
            response = await asyncio.to_thread(self.router.message, request)
            await socket.send(json.dumps({"type": "agent_response", **response}, ensure_ascii=False))
        except BridgeAPIError as exc:
            await self._send_error(socket, str(exc), status=exc.status)

    async def _run_realtime_sideband(self, socket: Any, call_id: str) -> None:
        async def notify(status: str) -> None:
            if status.startswith("event:"):
                await socket.send(
                    json.dumps(
                        {
                            "type": "realtime_sideband_event",
                            "event": status.removeprefix("event:"),
                        }
                    )
                )
            else:
                await socket.send(
                    json.dumps(
                        {
                            "type": "realtime_sideband",
                            "status": status,
                            "call_id": call_id,
                        }
                    )
                )

        try:
            await self.realtime_sideband.monitor(call_id, notify)
        except asyncio.CancelledError:
            raise
        except BridgeAPIError as exc:
            try:
                await self._send_error(socket, str(exc), status=exc.status)
            except Exception:
                pass

    @staticmethod
    def normalize_realtime_attach(body: dict[str, Any]) -> str:
        if set(body) != REALTIME_ATTACH_FIELDS:
            raise BridgeAPIError(400, "realtime_attach contains unexpected fields")
        return RealtimeSidebandController.validate_call_id(body.get("call_id"))

    @staticmethod
    def normalize_envelope(body: dict[str, Any]) -> dict[str, Any] | None:
        message_type = body.get("type")
        if not isinstance(message_type, str):
            raise BridgeAPIError(400, "type must be a string")
        if message_type == "ping":
            if set(body) != PING_FIELDS:
                raise BridgeAPIError(400, "ping contains unexpected fields")
            return None
        if message_type != "command":
            raise BridgeAPIError(400, "unsupported WebSocket message type")
        if not set(body).issubset(LEGACY_COMMAND_FIELDS):
            raise BridgeAPIError(400, "legacy command contains unexpected fields")
        command = body.get("command")
        if not isinstance(command, str) or not command.strip():
            raise BridgeAPIError(400, "command must be a non-empty string")
        route = body.get("route", "openclaw")
        if not isinstance(route, str) or not route.strip():
            raise BridgeAPIError(400, "route must be a non-empty string")
        return {
            "request_id": str(uuid.uuid4()),
            "conversation_id": str(uuid.uuid4()),
            "route": route.strip().lower(),
            "message": command.strip(),
            "system_instruction": "You are CARINA, the authenticated iPhone interface for OpenClaw.",
        }

    @staticmethod
    async def _send_error(socket: Any, message: str, status: int = 400) -> None:
        await socket.send(json.dumps({"type": "error", "status": status, "error": message[:500]}))
