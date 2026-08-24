import os
import sys
import unittest
from pathlib import Path
from unittest.mock import patch


BRIDGE_ROOT = Path(__file__).resolve().parents[1] / "apps" / "bridge"
sys.path.insert(0, str(BRIDGE_ROOT))

from api import AgentRouter, BridgeAPIError  # noqa: E402
from carina_bridge import BridgeApplication  # noqa: E402
from realtime import (  # noqa: E402
    CLIENT_SECRET_ENDPOINT,
    RealtimeClientSecretBroker,
    RealtimeSidebandController,
)
from websocket_server import CarinaWebSocketServer  # noqa: E402


class CapturingBroker(RealtimeClientSecretBroker):
    def __init__(self, response=None):
        self.response = response or {"value": "ek_test_abcdefghijklmnopqrstuvwxyz", "expires_at": 12345}
        self.last_url = None
        self.last_body = None
        self.last_headers = None

    def _post_json(self, url, body, *, headers, timeout):
        self.last_url = url
        self.last_body = body
        self.last_headers = headers
        return dict(self.response)


class StubRouter(AgentRouter):
    def health(self):
        return {"service": "stub"}


class StubRealtime:
    configured = True
    model = "gpt-realtime-2.1"
    voice = "marin"

    def create_client_secret(self, payload):
        if payload:
            raise BridgeAPIError(400, "unexpected")
        return {"success": True, "value": "ephemeral-value"}


class RealtimeBridgeTests(unittest.TestCase):
    def test_client_cannot_override_server_owned_session_policy(self):
        broker = CapturingBroker()
        with patch.dict(os.environ, {"OPENAI_API_KEY": "sk-test-" + "x" * 40}, clear=False):
            with self.assertRaisesRegex(BridgeAPIError, "does not accept fields"):
                broker.create_client_secret({"model": "other-model"})

    def test_standard_key_stays_on_bridge_and_only_ephemeral_secret_is_returned(self):
        broker = CapturingBroker()
        standard_key = "sk-test-" + "x" * 40
        with patch.dict(
            os.environ,
            {
                "OPENAI_API_KEY": standard_key,
                "CARINA_REALTIME_MODEL": "gpt-realtime-2.1",
                "CARINA_REALTIME_VOICE": "marin",
            },
            clear=False,
        ):
            result = broker.create_client_secret({})

        self.assertEqual(broker.last_url, CLIENT_SECRET_ENDPOINT)
        self.assertEqual(broker.last_headers["Authorization"], f"Bearer {standard_key}")
        self.assertEqual(broker.last_body["session"]["model"], "gpt-realtime-2.1")
        self.assertEqual(broker.last_body["session"]["audio"]["output"]["voice"], "marin")
        self.assertEqual(result["value"], "ek_test_abcdefghijklmnopqrstuvwxyz")
        self.assertNotIn("api_key", result)
        self.assertNotIn(standard_key, str(result))

    def test_missing_openai_key_fails_closed(self):
        broker = CapturingBroker()
        with patch.dict(os.environ, {"OPENAI_API_KEY": ""}, clear=False):
            with self.assertRaisesRegex(BridgeAPIError, "not configured"):
                broker.create_client_secret({})

    def test_invalid_upstream_secret_is_rejected(self):
        broker = CapturingBroker(response={"value": "short"})
        with patch.dict(os.environ, {"OPENAI_API_KEY": "sk-test-" + "x" * 40}, clear=False):
            with self.assertRaisesRegex(BridgeAPIError, "invalid Realtime client secret"):
                broker.create_client_secret({})

    def test_bridge_dispatch_exposes_authenticated_realtime_route(self):
        app = BridgeApplication(
            "a-secure-bridge-secret-that-is-long-enough",
            router=StubRouter(),
            realtime=StubRealtime(),
        )
        status, response = app.dispatch("/v1/realtime/client-secret", {})
        self.assertEqual(int(status), 200)
        self.assertTrue(response["success"])
        self.assertEqual(response["value"], "ephemeral-value")

    def test_sideband_call_id_is_strictly_validated(self):
        self.assertEqual(
            RealtimeSidebandController.validate_call_id("rtc_AbCdEf123456"),
            "rtc_AbCdEf123456",
        )
        for invalid in ("", "call_12345678", "rtc_bad value", "rtc_", 123):
            with self.subTest(invalid=invalid):
                with self.assertRaisesRegex(BridgeAPIError, "call_id is invalid"):
                    RealtimeSidebandController.validate_call_id(invalid)

    def test_realtime_attach_envelope_has_no_extra_client_policy_fields(self):
        call_id = CarinaWebSocketServer.normalize_realtime_attach(
            {"type": "realtime_attach", "call_id": "rtc_1234567890"}
        )
        self.assertEqual(call_id, "rtc_1234567890")

        with self.assertRaisesRegex(BridgeAPIError, "unexpected fields"):
            CarinaWebSocketServer.normalize_realtime_attach(
                {
                    "type": "realtime_attach",
                    "call_id": "rtc_1234567890",
                    "instructions": "override server",
                }
            )

    def test_sideband_requires_server_openai_key(self):
        with patch.dict(os.environ, {"OPENAI_API_KEY": ""}, clear=False):
            self.assertFalse(RealtimeSidebandController.configured())
        with patch.dict(os.environ, {"OPENAI_API_KEY": "sk-test-" + "x" * 40}, clear=False):
            self.assertTrue(RealtimeSidebandController.configured())


if __name__ == "__main__":
    unittest.main()
