import os
import sys
import unittest
import uuid
from pathlib import Path
from unittest.mock import patch


BRIDGE_ROOT = Path(__file__).resolve().parents[1] / "apps" / "bridge"
sys.path.insert(0, str(BRIDGE_ROOT))

from api import ActionStore, AgentRouter, BridgeAPIError, authorized  # noqa: E402


class StubRouter(AgentRouter):
    def _route_openai(self, message, system_instruction):
        return f"openai:{message}"

    def _route_ollama(self, message, system_instruction):
        return f"ollama:{message}"


def request(route="openai", message="hello"):
    return {
        "request_id": str(uuid.uuid4()),
        "conversation_id": str(uuid.uuid4()),
        "route": route,
        "message": message,
        "system_instruction": "Be accurate.",
    }


class CarinaBridgeTests(unittest.TestCase):
    def test_bearer_authentication_is_constant_time_compatible(self):
        secret = b"a-secure-token-that-is-long-enough"
        self.assertTrue(authorized(f"Bearer {secret.decode()}", secret))
        self.assertFalse(authorized("Bearer wrong", secret))
        self.assertFalse(authorized("", secret))

    def test_openai_route_returns_typed_response(self):
        result = StubRouter().message(request())
        self.assertEqual(result["provider"], "openai")
        self.assertEqual(result["status"], "informational")
        self.assertEqual(result["text"], "openai:hello")

    def test_unknown_route_is_rejected(self):
        with self.assertRaisesRegex(BridgeAPIError, "unsupported route"):
            StubRouter().message(request(route="shell"))

    def test_execute_command_is_prepared_not_run(self):
        result = StubRouter().message(request(message="shortcut.run Carina Command Center"))
        action = result["prepared_action"]
        self.assertEqual(result["status"], "waiting_for_approval")
        self.assertEqual(action["command"], "shortcut.run")
        self.assertEqual(action["permission"], "execute")

    def test_approval_is_single_use(self):
        store = ActionStore()
        action = store.create("shortcut.run", "Run test", {"shortcutName": "Test"})
        store.consume(action.public_view())
        with self.assertRaisesRegex(BridgeAPIError, "already consumed"):
            store.consume(action.public_view())

    def test_modified_approval_is_rejected(self):
        store = ActionStore()
        action = store.create("shortcut.run", "Run test", {"shortcutName": "Test"})
        changed = action.public_view()
        changed["payload"] = {"shortcutName": "Different"}
        with self.assertRaisesRegex(BridgeAPIError, "modified"):
            store.consume(changed)

    def test_openclaw_falls_back_to_openai_when_configured(self):
        router = StubRouter()
        with patch.object(router, "_openclaw_url", return_value=""), patch.dict(
            os.environ,
            {"OPENAI_API_KEY": "test-key-long-enough-value"},
            clear=False,
        ):
            result = router.message(request(route="openclaw"))
        self.assertEqual(result["provider"], "openai-fallback")

    def test_openclaw_uses_responses_endpoint(self):
        router = AgentRouter()
        response = {
            "output": [
                {
                    "type": "message",
                    "content": [{"type": "output_text", "text": "ENGINE ONLINE"}],
                }
            ]
        }
        with patch.object(router, "_openclaw_url", return_value="http://127.0.0.1:18789"), patch.object(
            router, "_openclaw_token", return_value="secure-token"
        ), patch.object(router, "_post_json", return_value=response) as post_json:
            text, agent, provider, model = router._route_openclaw("hello", "Be concise.")

        self.assertEqual(text, "ENGINE ONLINE")
        self.assertEqual(agent, "OpenClaw")
        self.assertEqual(provider, "openclaw")
        self.assertEqual(model, "ollama/qwen3:8b")
        self.assertEqual(post_json.call_args.args[0], "http://127.0.0.1:18789/v1/responses")

    def test_ollama_disables_reasoning_for_mobile_latency(self):
        router = AgentRouter()
        response = {"message": {"content": "CARINA_LINK_OK"}}
        with patch.object(router, "_post_json", return_value=response) as post_json:
            result = router._route_ollama("hello", "Be concise.")

        self.assertEqual(result, "CARINA_LINK_OK")
        payload = post_json.call_args.args[1]
        self.assertFalse(payload["think"])
        self.assertEqual(payload["keep_alive"], "10m")
        self.assertEqual(payload["options"]["num_predict"], 512)


if __name__ == "__main__":
    unittest.main()
