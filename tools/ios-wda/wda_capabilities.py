from __future__ import annotations

import os
from typing import Any


def required_env(name: str) -> str:
    value = os.environ.get(name, "").strip()
    if not value:
        raise RuntimeError(
            f"{name} is required. Export it before starting the Appium session."
        )
    return value


def build_capabilities() -> dict[str, Any]:
    udid = required_env("CARINA_IOS_UDID")
    bundle_id = required_env("CARINA_WDA_BUNDLE_ID")

    return {
        "platformName": "iOS",
        "appium:automationName": "XCUITest",
        "appium:udid": udid,
        "appium:usePreinstalledWDA": True,
        "appium:updatedWDABundleId": bundle_id,
        "appium:updatedWDABundleIdSuffix": "",
        "appium:wdaLocalPort": 8100,
        "appium:wdaLaunchTimeout": 60_000,
        "appium:wdaConnectionTimeout": 60_000,
        "appium:autoLaunch": False,
    }
