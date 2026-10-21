from __future__ import annotations

import importlib.util
import os
from pathlib import Path
import unittest
from unittest.mock import patch


MODULE_PATH = Path(__file__).parents[1] / "tools" / "ios-wda" / "wda_capabilities.py"
SPEC = importlib.util.spec_from_file_location("wda_capabilities", MODULE_PATH)
assert SPEC and SPEC.loader
wda_capabilities = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(wda_capabilities)


class WdaCapabilitiesTests(unittest.TestCase):
    def test_uses_installed_bundle_id_without_xctrunner_suffix(self) -> None:
        env = {
            "CARINA_IOS_UDID": "00008150-TEST",
            "CARINA_WDA_BUNDLE_ID": "com.example.WebDriverAgentRunner",
        }
        with patch.dict(os.environ, env, clear=True):
            caps = wda_capabilities.build_capabilities()

        self.assertTrue(caps["appium:usePreinstalledWDA"])
        self.assertEqual(
            caps["appium:updatedWDABundleId"],
            "com.example.WebDriverAgentRunner",
        )
        self.assertEqual(caps["appium:updatedWDABundleIdSuffix"], "")
        self.assertNotIn("appium:prebuiltWDAPath", caps)

    def test_requires_installed_bundle_id(self) -> None:
        with patch.dict(os.environ, {"CARINA_IOS_UDID": "00008150-TEST"}, clear=True):
            with self.assertRaisesRegex(RuntimeError, "CARINA_WDA_BUNDLE_ID"):
                wda_capabilities.build_capabilities()


if __name__ == "__main__":
    unittest.main()
