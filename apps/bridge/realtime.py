from __future__ import annotations

import json
import os
import re
import urllib.error
import urllib.parse
import urllib.request
from collections.abc import Awaitable, Callable
from typing import Any, Mapping

from api import BridgeAPIError


DEFAULT_REALTIME_MODEL = "gpt-realtime-2.1"
DEFAULT_REALTIME_VOICE = "marin"
MAX_UPSTREAM_BYTES = 256_000
CLIENT_SECRET_ENDPOINT = "https://api.openai.com/v1/realtime/client_secrets"
SIDEBAND_ENDPOINT = "wss://api.openai.com/v1/realtime"
CALL_ID_PATTERN = re.compile(r"^rtc_[A-Za-z0-9_-]{8,200}$")


class RealtimeClientSecretBroker:
    """Mint short-lived Realtime client secrets without exposing the standard API key."""

    @property
    def configured(self) -> bool:
        return self._has_openai_key()

    @property
    def model(self) -> str:
        return os.environ.get("CARINA_REALTIME_MODEL", DEFAULT_REALTIME_MODEL).strip() or DEFAULT_REALTIME_MODEL

    @property
    def voice(self) -> str:
        return os.environ.get("CARINA_REALTIME_VOICE", DEFAULT_REALTIME_VOICE).strip() or DEFAULT_REALTIME_VOICE

    def create_client_secret(self, payload: Mapping[str, Any]) -> dict[str, Any]:
        # Session policy is server-owned. The iPhone may request a secret, but it
        # cannot select a model, voice, instructions, tools, or permissions.
        if payload:
            raise BridgeAPIError(400, "realtime client-secret request does not accept fields")

        key = os.environ.get("OPENAI_API_KEY", "").strip()
        if not self._has_openai_key():
            raise BridgeAPIError(503, "OpenAI Realtime is not configured on the Mac bridge")

        session: dict[str, Any] = {
            "type": "realtime",
            "model": self.model,
            "audio": {"output": {"voice": self.voice}},
            "instructions": self._instructions(),
        }
        body = {"session": session}
        headers = {
            "Authorization": f"Bearer {key}",
            "Content-Type": "application/json",
            "Accept": "application/json",
        }
        safety_identifier = os.environ.get("CARINA_REALTIME_SAFETY_IDENTIFIER", "").strip()
        if safety_identifier:
            headers["OpenAI-Safety-Identifier"] = safety_identifier

        response = self._post_json(CLIENT_SECRET_ENDPOINT, body, headers=headers, timeout=15)
        value = response.get("value")
        if not isinstance(value, str) or len(value.strip()) < 20:
            raise BridgeAPIError(502, "OpenAI returned an invalid Realtime client secret")

        result: dict[str, Any] = {
            "success": True,
            "value": value.strip(),
            "model": self.model,
            "voice": self.voice,
        }
        expires_at = response.get("expires_at")
        if isinstance(expires_at, (int, float)):
            result["expires_at"] = expires_at
        return result

    @staticmethod
    def _instructions() -> str:
        configured = os.environ.get("CARINA_REALTIME_INSTRUCTIONS", "").strip()
        if configured:
            return configured[:8_000]
        return (
            "You are CARINA, the realtime voice interface. Keep conversation natural and concise. "
            "Never claim that a device, Shortcut, file, account, or external system was changed unless the "
            "CARINA bridge confirms it. External actions remain subject to CARINA permission and approval rules."
        )

    @staticmethod
    def _has_openai_key() -> bool:
        value = os.environ.get("OPENAI_API_KEY", "").strip()
        return len(value) >= 20 and value.lower() not in {"replace_me", "your_key_here"}

    @staticmethod
    def _post_json(
        url: str,
        body: Mapping[str, Any],
        *,
        headers: Mapping[str, str],
        timeout: float,
    ) -> dict[str, Any]:
        encoded = json.dumps(body, ensure_ascii=False).encode("utf-8")
        request = urllib.request.Request(url, data=encoded, headers=dict(headers), method="POST")
        try:
            with urllib.request.urlopen(request, timeout=timeout) as response:
                raw = response.read(MAX_UPSTREAM_BYTES + 1)
                if len(raw) > MAX_UPSTREAM_BYTES:
                    raise BridgeAPIError(502, "OpenAI Realtime response exceeded safety limit")
        except urllib.error.HTTPError as exc:
            safe_message = f"OpenAI Realtime returned HTTP {exc.code}"
            try:
                error_body = json.loads(exc.read(MAX_UPSTREAM_BYTES).decode("utf-8"))
                detail = error_body.get("error")
                if isinstance(detail, Mapping):
                    safe_message = str(detail.get("message", safe_message))[:500]
                elif isinstance(detail, str):
                    safe_message = detail[:500]
            except (UnicodeDecodeError, json.JSONDecodeError):
                pass
            raise BridgeAPIError(502, safe_message) from exc
        except (OSError, urllib.error.URLError) as exc:
            raise BridgeAPIError(502, f"OpenAI Realtime connection failed: {type(exc).__name__}") from exc

        try:
            decoded = json.loads(raw.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError) as exc:
            raise BridgeAPIError(502, "OpenAI Realtime returned invalid JSON") from exc
        if not isinstance(decoded, dict):
            raise BridgeAPIError(502, "OpenAI Realtime returned an invalid object")
        return decoded


class RealtimeSidebandController:
    """Attach the Mac control plane to an existing WebRTC Realtime call.

    This channel deliberately does not execute tools yet. It establishes the
    authenticated server-side control path while leaving all side-effecting
    actions behind CARINA's existing permission and approval boundary.
    """

    @staticmethod
    def validate_call_id(value: Any) -> str:
        if not isinstance(value, str) or not CALL_ID_PATTERN.fullmatch(value):
            raise BridgeAPIError(400, "realtime call_id is invalid")
        return value

    @staticmethod
    def configured() -> bool:
        value = os.environ.get("OPENAI_API_KEY", "").strip()
        return len(value) >= 20 and value.lower() not in {"replace_me", "your_key_here"}

    async def monitor(
        self,
        call_id: str,
        notify: Callable[[str], Awaitable[None]],
    ) -> None:
        call_id = self.validate_call_id(call_id)
        key = os.environ.get("OPENAI_API_KEY", "").strip()
        if not self.configured():
            raise BridgeAPIError(503, "OpenAI Realtime sideband is not configured")

        try:
            from websockets.asyncio.client import connect
        except ImportError as exc:
            raise BridgeAPIError(503, "websockets dependency is unavailable") from exc

        query = urllib.parse.urlencode({"call_id": call_id})
        url = f"{SIDEBAND_ENDPOINT}?{query}"
        headers = {"Authorization": f"Bearer {key}"}

        try:
            async with connect(
                url,
                additional_headers=headers,
                max_size=MAX_UPSTREAM_BYTES,
                ping_interval=20,
                ping_timeout=20,
                close_timeout=5,
                open_timeout=10,
            ) as upstream:
                await notify("connected")
                async for raw in upstream:
                    if not isinstance(raw, str):
                        continue
                    try:
                        event = json.loads(raw)
                    except json.JSONDecodeError:
                        continue
                    if not isinstance(event, Mapping):
                        continue
                    event_type = event.get("type")
                    if isinstance(event_type, str) and event_type:
                        # Only surface event names to the iPhone. Conversation
                        # content and server details stay on the control plane.
                        await notify(f"event:{event_type[:120]}")
        except BridgeAPIError:
            raise
        except Exception as exc:
            raise BridgeAPIError(502, f"OpenAI Realtime sideband failed: {type(exc).__name__}") from exc
