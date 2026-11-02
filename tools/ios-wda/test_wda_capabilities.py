"""Regression tests for CARINA's explicit WDA connection modes."""

import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from wda_capabilities import build_capabilities


class CapabilitiesTests(unittest.TestCase):
    def setUp(self):
        self.env = patch.dict(os.environ, {
            "CARINA_IOS_UDID": "TEST-DEVICE-UDID",
            "CARINA_WDA_TEAM_ID": "TESTTEAM01",
            "CARINA_WDA_BUNDLE_ID": "com.example.test.wda",
        }, clear=True)
        self.env.start()
        self.addCleanup(self.env.stop)

    def test_managed_mode_uses_explicit_signing(self):
        os.environ["CARINA_WDA_MODE"] = "managed"
        cap = build_capabilities()
        self.assertEqual(cap["appium:xcodeOrgId"], "TESTTEAM01")
        self.assertEqual(cap["appium:xcodeSigningId"], "Apple Development")
        self.assertEqual(cap["appium:updatedWDABundleId"], "com.example.test.wda")
        self.assertNotIn("appium:usePreinstalledWDA", cap)
        self.assertNotIn("appium:prebuiltWDAPath", cap)
        self.assertTrue(cap["appium:noReset"])
        self.assertFalse(cap["appium:fullReset"])

    def test_preinstalled_mode_is_default(self):
        with tempfile.TemporaryDirectory() as directory:
            os.environ["CARINA_WDA_APP"] = directory
            cap = build_capabilities()
            self.assertTrue(cap["appium:usePreinstalledWDA"])
            self.assertEqual(cap["appium:prebuiltWDAPath"], str(Path(directory).resolve()))
            self.assertFalse(cap["appium:autoLaunch"])
            self.assertNotIn("appium:xcodeOrgId", cap)

    def test_preinstalled_mode_rejects_missing_path(self):
        with self.assertRaisesRegex(RuntimeError, "CARINA_WDA_APP"):
            build_capabilities()

    def test_preinstalled_mode_rejects_nonexistent_directory(self):
        os.environ["CARINA_WDA_APP"] = "/definitely/not/a/wda/app"
        with self.assertRaisesRegex(RuntimeError, "does not exist"):
            build_capabilities()

    def test_managed_mode_requires_team(self):
        os.environ["CARINA_WDA_MODE"] = "managed"
        del os.environ["CARINA_WDA_TEAM_ID"]
        with self.assertRaisesRegex(RuntimeError, "CARINA_WDA_TEAM_ID"):
            build_capabilities()

    def test_managed_mode_requires_bundle_id(self):
        os.environ["CARINA_WDA_MODE"] = "managed"
        del os.environ["CARINA_WDA_BUNDLE_ID"]
        with self.assertRaisesRegex(RuntimeError, "CARINA_WDA_BUNDLE_ID"):
            build_capabilities()

    def test_invalid_mode_rejected(self):
        os.environ["CARINA_WDA_MODE"] = "unexpected"
        with self.assertRaisesRegex(RuntimeError, "CARINA_WDA_MODE"):
            build_capabilities()

    def test_udid_required_in_both_modes(self):
        del os.environ["CARINA_IOS_UDID"]
        for mode in ("managed", "preinstalled"):
            with self.subTest(mode=mode):
                os.environ["CARINA_WDA_MODE"] = mode
                with self.assertRaisesRegex(RuntimeError, "CARINA_IOS_UDID"):
                    build_capabilities()


if __name__ == "__main__":
    unittest.main()
