import datetime as dt
import importlib.util
import unittest
from pathlib import Path


SCRIPT = Path(__file__).resolve().parents[1] / "scripts/carina_deployment_guardian.py"
SPEC = importlib.util.spec_from_file_location("carina_deployment_guardian", SCRIPT)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("unable to load deployment guardian")
guardian = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(guardian)


class DeploymentGuardianTests(unittest.TestCase):
    def setUp(self):
        self.now = dt.datetime(2026, 7, 18, tzinfo=dt.timezone.utc)
        self.defaults = {
            "force": False,
            "installed": True,
            "app_exists": True,
            "revision": "current",
            "deployed_revision": "current",
            "profile_expires": self.now + dt.timedelta(days=5),
            "last_success": self.now - dt.timedelta(days=1),
            "now": self.now,
        }

    def reason(self, **changes):
        values = {**self.defaults, **changes}
        return guardian.deployment_reason(**values)

    def test_fresh_install_needs_no_work(self):
        self.assertIsNone(self.reason())

    def test_missing_install_triggers_deployment(self):
        self.assertEqual(self.reason(installed=False), "app-not-installed")

    def test_source_change_triggers_deployment(self):
        self.assertEqual(self.reason(deployed_revision="old"), "ios-source-changed")

    def test_expiring_profile_triggers_refresh(self):
        expiration = self.now + dt.timedelta(hours=47)
        self.assertEqual(self.reason(profile_expires=expiration), "profile-near-expiration")

    def test_four_day_refresh_window_is_enforced(self):
        last_success = self.now - dt.timedelta(days=4, seconds=1)
        self.assertEqual(self.reason(last_success=last_success), "scheduled-refresh")


if __name__ == "__main__":
    unittest.main()
