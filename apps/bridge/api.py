from __future__ import annotations

import hashlib
import hmac
import json
import logging
import os
import secrets
import subprocess
import threading
import time
import urllib.error
import urllib.request
import uuid
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Mapping


LOGGER = logging.getLogger("CarinaBridge.API")
MAX_MESSAGE_LENGTH = 16_000
MAX_RESPONSE_BYTES = 1_048_576
DEFAULT_OPENAI_MODEL = "gpt-5.6-terra"
DEFAULT_OLLAMA_MODEL = "qwen3:8b"
APPROVAL_LIFETIME_SECONDS = 300
MESSAGE_REQUEST_FIELDS = frozenset(
    {"request_id", "conversation_id", "route", "message", "system_instruction"}
)
EXECUTE_REQUEST_FIELDS = frozenset({"action", "conversation_id"})
SUPPORTED_ROUTES = frozenset({"openclaw", "openai", "ollama", "maya", "hermes", "karina"})


class BridgeAPIError(RuntimeError):
    def __init__(self, status: int, message: str) -> None:
        super().__init__(message)
        self.status = status


def reject_unexpected_fields(payload: Mapping[str, Any], allowed: frozenset[str], schema: str) -> None:
    if any(not isinstance(key, str) or key not in allowed for key in payload):
        raise BridgeAPIError(400, f"{schema} contains unexpected fields")


@dataclass(frozen=True)
class AgentMessageRequest:
    request_id: str
    conversation_id: str
    route: str
    message: str
    system_instruction: str

    @classmethod
    def from_payload(cls, payload: Mapping[str, Any]) -> AgentMessageRequest:
        reject_unexpected_fields(payload, MESSAGE_REQUEST_FIELDS, "agent message")
        message = AgentRouter._required_text(payload, "message", MAX_MESSAGE_LENGTH)
        route_value = payload.get("route", "openclaw")
        if not isinstance(route_value, str) or not route_value.strip():
            raise BridgeAPIError(400, "route must be a non-empty string")
        route = route_value.strip().lower()
        if route not in SUPPORTED_ROUTES:
            raise BridgeAPIError(400, f"unsupported route: {route}")
        instruction_value = payload.get("system_instruction", "")
        if not isinstance(instruction_value, str):
            raise BridgeAPIError(400, "system_instruction must be a string")
        if len(instruction_value) > 8_000:
            raise BridgeAPIError(413, "system_instruction exceeds 8000 characters")
        return cls(
            request_id=AgentRouter._uuid(payload.get("request_id"), "request_id"),
            conversation_id=AgentRouter._uuid(payload.get("conversation_id"), "conversation_id"),
            route=route,
            message=message,
            system_instruction=instruction_value.strip(),
        )


class OpenClawPayloadAdapter:
    """Builds a new OpenClaw envelope from validated canonical fields only."""

    @staticmethod
    def responses_payload(message: str, system_instruction: str) -> dict[str, Any]:
        if not isinstance(message, str) or not message:
            raise BridgeAPIError(500, "canonical message serialization failed")
        if not isinstance(system_instruction, str):
            raise BridgeAPIError(500, "canonical instruction serialization failed")
        return {
            "model": "openclaw",
            "instructions": system_instruction,
            "input": message,
            "max_output_tokens": 2_000,
            "user": "carina-iphone",
        }


def load_environment_file(path: Path) -> None:
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except FileNotFoundError:
        return
    except PermissionError:
        LOGGER.warning("macOS privacy blocked the configured environment file")
        return
    for raw_line in lines:
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        name, value = line.split("=", 1)
        name = name.strip()
        value = value.strip().strip("'\"")
        if name and value and name not in os.environ:
            os.environ[name] = value


def load_runtime_environment(project_root: Path) -> None:
    configured = os.environ.get("CARINA_OPENAI_ENV_FILE", "").strip()
    if configured:
        load_environment_file(Path(configured).expanduser().resolve())
    load_environment_file(project_root / ".env")


def canonical_fingerprint(command: str, payload: Mapping[str, str]) -> str:
    canonical = command
    for key in sorted(payload):
        canonical += f"\n{key}={payload[key]}"
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest()


@dataclass(frozen=True)
class PendingAction:
    id: str
    command: str
    summary: str
    payload: dict[str, str]
    permission: str
    fingerprint: str
    created_at: float
    expires_at: float

    def public_view(self) -> dict[str, Any]:
        return {
            "id": self.id,
            "command": self.command,
            "summary": self.summary,
            "payload": dict(self.payload),
            "permission": self.permission,
            "fingerprint": self.fingerprint,
            "created_at": iso8601(self.created_at),
            "expires_at": iso8601(self.expires_at),
        }


def iso8601(timestamp: float) -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(timestamp))


class ActionStore:
    def __init__(self) -> None:
        self._pending: dict[str, PendingAction] = {}
        self._consumed: set[str] = set()
        self._lock = threading.RLock()

    def create(self, command: str, summary: str, payload: Mapping[str, str]) -> PendingAction:
        now = time.time()
        clean_payload = {str(key): str(value) for key, value in payload.items()}
        action = PendingAction(
            id=str(uuid.uuid4()),
            command=command,
            summary=summary,
            payload=clean_payload,
            permission="execute",
            fingerprint=canonical_fingerprint(command, clean_payload),
            created_at=now,
            expires_at=now + APPROVAL_LIFETIME_SECONDS,
        )
        with self._lock:
            self._remove_expired_locked(now)
            self._pending[action.id] = action
        return action

    def consume(self, submitted: Mapping[str, Any]) -> PendingAction:
        action_id = str(submitted.get("id", ""))
        with self._lock:
            if action_id in self._consumed:
                raise BridgeAPIError(409, "approval was already consumed")
            action = self._pending.get(action_id)
            if action is None:
                raise BridgeAPIError(404, "approval request was not found")
            if time.time() >= action.expires_at:
                self._pending.pop(action_id, None)
                raise BridgeAPIError(410, "approval request expired")
            expected = action.public_view()
            normalized = dict(submitted)
            if normalized != expected:
                raise BridgeAPIError(409, "approved action payload was modified")
            self._pending.pop(action_id, None)
            self._consumed.add(action_id)
            return action

    def _remove_expired_locked(self, now: float) -> None:
        expired = [action_id for action_id, action in self._pending.items() if now >= action.expires_at]
        for action_id in expired:
            self._pending.pop(action_id, None)


class AgentRouter:
    def __init__(self, action_store: ActionStore | None = None) -> None:
        self.action_store = action_store or ActionStore()
        self.openai_model = os.environ.get("OPENAI_MODEL", DEFAULT_OPENAI_MODEL).strip()
        self.ollama_model = os.environ.get("OLLAMA_MODEL", DEFAULT_OLLAMA_MODEL).strip()

    def health(self) -> dict[str, Any]:
        openclaw_url = self._openclaw_url()
        openclaw_available = bool(
            openclaw_url
            and self._openclaw_token()
            and self._probe(f"{openclaw_url}/healthz")
        )
        return {
            "service": "carina-openclaw-bridge",
            "routes": {
                "openclaw": openclaw_available,
                "openai": self._has_openai_key(),
                "ollama": self._probe("http://127.0.0.1:11434/api/tags"),
                "maya": openclaw_available
                or self._has_openai_key()
                or self._probe("http://127.0.0.1:11434/api/tags"),
                "hermes": bool(self._hermes_command()),
                "karina": True,
            },
            "ports": {"http": 51001, "websocket": 51002},
            "authentication": "bearer",
            "execute_approval": "single-use, five-minute expiry",
        }

    def message(self, payload: Mapping[str, Any]) -> dict[str, Any]:
        request = AgentMessageRequest.from_payload(payload)
        message = request.message
        route = request.route
        request_id = request.request_id
        conversation_id = request.conversation_id
        system_instruction = request.system_instruction

        prepared = self._prepare_explicit_action(message)
        if prepared is not None:
            return self._response(
                request_id=request_id,
                conversation_id=conversation_id,
                route=route,
                agent="Karina",
                provider="permission-engine",
                model=None,
                text=f"Prepared for approval: {prepared.summary}",
                status="waiting_for_approval",
                prepared_action=prepared.public_view(),
            )

        if route == "openclaw":
            text, agent, provider, model = self._route_openclaw(message, system_instruction)
        elif route == "openai":
            text = self._route_openai(message, system_instruction)
            agent, provider, model = "CARINA", "openai", self.openai_model
        elif route == "ollama":
            text = self._route_ollama(message, system_instruction)
            agent, provider, model = "CARINA", "ollama", self.ollama_model
        elif route == "maya":
            maya_instruction = "You are Maya, CARINA's strategic planning agent. Return a concrete safe plan. " + system_instruction
            text, _, provider, model = self._route_openclaw(message, maya_instruction)
            agent = "Maya"
        elif route == "hermes":
            text = self._route_hermes_read_only(message)
            agent, provider, model = "Hermes", "hermes-local", None
        else:
            karina_instruction = "You are Karina, the voice and Shortcuts layer. Prepare a concise device-safe response without executing actions. " + system_instruction
            text = self._route_openai(message, karina_instruction) if self._has_openai_key() else message
            agent, provider, model = "Karina", "openai" if self._has_openai_key() else "local", self.openai_model if self._has_openai_key() else None

        return self._response(
            request_id=request_id,
            conversation_id=conversation_id,
            route=route,
            agent=agent,
            provider=provider,
            model=model,
            text=text,
            status="informational",
        )

    def execute(self, payload: Mapping[str, Any]) -> dict[str, Any]:
        reject_unexpected_fields(payload, EXECUTE_REQUEST_FIELDS, "execute request")
        raw_action = payload.get("action")
        if not isinstance(raw_action, Mapping):
            raise BridgeAPIError(400, "action must be a JSON object")
        conversation_id = self._uuid(payload.get("conversation_id"), "conversation_id")
        action = self.action_store.consume(raw_action)
        if action.command != "shortcut.run":
            raise BridgeAPIError(403, "command has no registered execute handler")
        shortcut_name = action.payload.get("shortcutName", "").strip()
        if not shortcut_name or len(shortcut_name) > 128:
            raise BridgeAPIError(400, "shortcutName is invalid")
        try:
            completed = subprocess.run(
                ["/usr/bin/shortcuts", "run", shortcut_name],
                capture_output=True,
                text=True,
                timeout=120,
                check=False,
            )
        except (OSError, subprocess.TimeoutExpired) as exc:
            raise BridgeAPIError(502, f"approved Shortcut failed: {type(exc).__name__}") from exc
        if completed.returncode != 0:
            raise BridgeAPIError(502, "approved Shortcut returned a failure")
        return self._response(
            request_id=str(uuid.uuid4()),
            conversation_id=conversation_id,
            route="karina",
            agent="Karina",
            provider="macos-shortcuts",
            model=None,
            text=f"Executed {shortcut_name} once after approval.",
            status="executed",
        )

    def _route_openclaw(self, message: str, system_instruction: str) -> tuple[str, str, str, str | None]:
        openclaw_url = self._openclaw_url()
        openclaw_token = self._openclaw_token()
        if openclaw_url and openclaw_token:
            body = self._post_json(
                f"{openclaw_url}/v1/responses",
                OpenClawPayloadAdapter.responses_payload(message, system_instruction),
                bearer=openclaw_token,
                timeout=120,
            )
            text_parts: list[str] = []
            for output in body.get("output", []):
                if not isinstance(output, Mapping) or output.get("type") != "message":
                    continue
                for content in output.get("content", []):
                    if isinstance(content, Mapping) and content.get("type") == "output_text":
                        text_parts.append(str(content.get("text", "")))
            text = "\n".join(part for part in text_parts if part).strip()
            if not text:
                raise BridgeAPIError(502, "OpenClaw returned no text")
            return text, "OpenClaw", "openclaw", "ollama/qwen3:8b"
        if self._has_openai_key():
            try:
                return self._route_openai(message, system_instruction), "CARINA", "openai-fallback", self.openai_model
            except BridgeAPIError as exc:
                LOGGER.warning("OpenAI fallback unavailable: status=%d", exc.status)
        if self._probe("http://127.0.0.1:11434/api/tags"):
            return self._route_ollama(message, system_instruction), "CARINA", "ollama-fallback", self.ollama_model
        raise BridgeAPIError(503, "OpenClaw is not configured and no OpenAI or Ollama fallback is available")

    @staticmethod
    def _openclaw_config() -> Mapping[str, Any]:
        configured = os.environ.get("OPENCLAW_CONFIG_PATH", "").strip()
        path = Path(configured).expanduser() if configured else Path.home() / ".openclaw/openclaw.json"
        try:
            decoded = json.loads(path.read_text(encoding="utf-8"))
        except (FileNotFoundError, PermissionError, UnicodeDecodeError, json.JSONDecodeError):
            return {}
        return decoded if isinstance(decoded, Mapping) else {}

    def _openclaw_url(self) -> str:
        configured = os.environ.get("OPENCLAW_URL", "").strip().rstrip("/")
        if configured:
            return configured
        gateway = self._openclaw_config().get("gateway", {})
        if not isinstance(gateway, Mapping) or gateway.get("mode") != "local":
            return ""
        port = gateway.get("port", 18789)
        if not isinstance(port, int) or not 1 <= port <= 65535:
            return ""
        return f"http://127.0.0.1:{port}"

    def _openclaw_token(self) -> str:
        configured = os.environ.get("OPENCLAW_TOKEN", "").strip()
        if configured:
            return configured
        gateway = self._openclaw_config().get("gateway", {})
        auth = gateway.get("auth", {}) if isinstance(gateway, Mapping) else {}
        token = auth.get("token", "") if isinstance(auth, Mapping) else ""
        return token.strip() if isinstance(token, str) else ""

    def _route_openai(self, message: str, system_instruction: str) -> str:
        key = os.environ.get("OPENAI_API_KEY", "").strip()
        if not self._has_openai_key():
            raise BridgeAPIError(503, "OpenAI is not configured on the Mac bridge")
        body = self._post_json(
            "https://api.openai.com/v1/responses",
            {
                "model": self.openai_model,
                "instructions": system_instruction,
                "input": message,
                "max_output_tokens": 2_000,
                "store": False,
            },
            bearer=key,
            timeout=45,
        )
        text_parts: list[str] = []
        for output in body.get("output", []):
            if not isinstance(output, Mapping) or output.get("type") != "message":
                continue
            for content in output.get("content", []):
                if isinstance(content, Mapping) and content.get("type") == "output_text":
                    text_parts.append(str(content.get("text", "")))
        text = "\n".join(part for part in text_parts if part).strip()
        if not text:
            raise BridgeAPIError(502, "OpenAI returned no text output")
        return text

    def _route_ollama(self, message: str, system_instruction: str) -> str:
        body = self._post_json(
            "http://127.0.0.1:11434/api/chat",
            {
                "model": self.ollama_model,
                "stream": False,
                "think": False,
                "keep_alive": "10m",
                "options": {
                    "num_predict": 512,
                    "temperature": 0.2,
                },
                "messages": [
                    {"role": "system", "content": system_instruction},
                    {"role": "user", "content": message},
                ],
            },
            timeout=90,
        )
        message_body = body.get("message", {})
        text = str(message_body.get("content", "")) if isinstance(message_body, Mapping) else ""
        if not text.strip():
            raise BridgeAPIError(502, "Ollama returned no text output")
        return text.strip()

    def _route_hermes_read_only(self, message: str) -> str:
        command = self._hermes_command()
        if not command:
            raise BridgeAPIError(503, "Hermes is not installed")
        prompt = "Read-only request. Do not modify files or external state. " + message
        try:
            completed = subprocess.run(
                [*command, "--safe-mode", "-z", prompt],
                capture_output=True,
                text=True,
                timeout=180,
                check=False,
                env=os.environ.copy(),
            )
        except (OSError, subprocess.TimeoutExpired) as exc:
            raise BridgeAPIError(502, f"Hermes failed: {type(exc).__name__}") from exc
        if completed.returncode != 0:
            raise BridgeAPIError(502, "Hermes returned a failure")
        output = completed.stdout.strip()
        if not output:
            raise BridgeAPIError(502, "Hermes returned no output")
        return output[-MAX_RESPONSE_BYTES:]

    def _prepare_explicit_action(self, message: str) -> PendingAction | None:
        prefix = "shortcut.run "
        if not message.casefold().startswith(prefix):
            return None
        name = message[len(prefix):].strip()
        if not name or len(name) > 128:
            raise BridgeAPIError(400, "shortcut.run requires a valid Shortcut name")
        return self.action_store.create(
            "shortcut.run",
            f"Run the macOS Shortcut “{name}”",
            {"shortcutName": name},
        )

    @staticmethod
    def _response(
        *,
        request_id: str,
        conversation_id: str,
        route: str,
        agent: str,
        provider: str,
        model: str | None,
        text: str,
        status: str,
        prepared_action: Mapping[str, Any] | None = None,
    ) -> dict[str, Any]:
        return {
            "request_id": request_id,
            "conversation_id": conversation_id,
            "route": route,
            "agent": agent,
            "provider": provider,
            "model": model,
            "text": text[:MAX_RESPONSE_BYTES],
            "status": status,
            "prepared_action": dict(prepared_action) if prepared_action else None,
        }

    @staticmethod
    def _required_text(payload: Mapping[str, Any], key: str, limit: int) -> str:
        value = payload.get(key)
        if not isinstance(value, str) or not value.strip():
            raise BridgeAPIError(400, f"{key} must be a non-empty string")
        clean = value.strip()
        if len(clean) > limit:
            raise BridgeAPIError(413, f"{key} exceeds {limit} characters")
        return clean

    @staticmethod
    def _uuid(value: Any, name: str) -> str:
        if not isinstance(value, str):
            raise BridgeAPIError(400, f"{name} must be a UUID string")
        try:
            return str(uuid.UUID(value))
        except (TypeError, ValueError, AttributeError) as exc:
            raise BridgeAPIError(400, f"{name} must be a UUID") from exc

    @staticmethod
    def _has_openai_key() -> bool:
        value = os.environ.get("OPENAI_API_KEY", "").strip()
        return len(value) >= 20 and value.lower() not in {"replace_me", "your_key_here"}

    @staticmethod
    def _hermes_command() -> list[str]:
        configured = os.environ.get("HERMES_COMMAND", "").strip()
        if configured:
            path = Path(configured).expanduser()
            return [str(path)] if path.is_file() else []
        path = Path.home() / ".local/bin/hermes"
        return [str(path)] if path.is_file() else []

    @staticmethod
    def _probe(url: str) -> bool:
        try:
            with urllib.request.urlopen(url, timeout=1.0) as response:
                return 200 <= response.status < 300
        except (OSError, urllib.error.URLError):
            return False

    @staticmethod
    def _post_json(
        url: str,
        body: Mapping[str, Any],
        *,
        bearer: str | None = None,
        timeout: float,
    ) -> dict[str, Any]:
        encoded = json.dumps(body, ensure_ascii=False).encode("utf-8")
        headers = {"Content-Type": "application/json", "Accept": "application/json"}
        if bearer:
            headers["Authorization"] = f"Bearer {bearer}"
        request = urllib.request.Request(url, data=encoded, headers=headers, method="POST")
        try:
            with urllib.request.urlopen(request, timeout=timeout) as response:
                raw = response.read(MAX_RESPONSE_BYTES + 1)
                if len(raw) > MAX_RESPONSE_BYTES:
                    raise BridgeAPIError(502, "upstream response exceeded safety limit")
        except urllib.error.HTTPError as exc:
            safe_message = f"upstream returned HTTP {exc.code}"
            try:
                error_body = json.loads(exc.read(MAX_RESPONSE_BYTES).decode("utf-8"))
                detail = error_body.get("error")
                if isinstance(detail, Mapping):
                    safe_message = str(detail.get("message", safe_message))[:500]
                elif isinstance(detail, str):
                    safe_message = detail[:500]
            except (UnicodeDecodeError, json.JSONDecodeError):
                pass
            raise BridgeAPIError(502, safe_message) from exc
        except (OSError, urllib.error.URLError) as exc:
            raise BridgeAPIError(502, f"upstream connection failed: {type(exc).__name__}") from exc
        try:
            decoded = json.loads(raw.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError) as exc:
            raise BridgeAPIError(502, "upstream returned invalid JSON") from exc
        if not isinstance(decoded, dict):
            raise BridgeAPIError(502, "upstream returned an invalid object")
        return decoded


def generate_shared_secret(path: Path) -> str:
    configured = os.environ.get("CARINA_BRIDGE_TOKEN", "").strip()
    if configured:
        if len(configured) < 32:
            raise RuntimeError("CARINA_BRIDGE_TOKEN must contain at least 32 characters")
        return configured
    try:
        existing = path.read_text(encoding="utf-8").strip()
    except FileNotFoundError:
        existing = ""
    if existing:
        if len(existing) < 32:
            raise RuntimeError("saved bridge token is invalid")
        return existing
    secret = secrets.token_urlsafe(48)
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(descriptor, "w", encoding="utf-8") as output:
        output.write(secret + "\n")
    return secret


def authorized(header: str, shared_secret: bytes) -> bool:
    scheme, separator, token = header.partition(" ")
    return bool(separator) and scheme.casefold() == "bearer" and hmac.compare_digest(
        token.encode("utf-8"), shared_secret
    )
