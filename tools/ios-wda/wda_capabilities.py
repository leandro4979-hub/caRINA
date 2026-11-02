from __future__ import annotations

import os
from pathlib import Path
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
    mode = os.environ.get("CARINA_WDA_MODE", "preinstalled").strip().lower()
    if mode not in {"preinstalled", "managed"}:
        raise RuntimeError("CARINA_WDA_MODE must be 'preinstalled' or 'managed'.")

    capabilities: dict[str, Any] = {
        "platformName": "iOS",
        "appium:automationName": "XCUITest",
        "appium:udid": udid,
        "appium:wdaLocalPort": 8100,
        "appium:wdaLaunchTimeout": 60_000,
        "appium:wdaConnectionTimeout": 60_000,
        "appium:noReset": True,
        "appium:fullReset": False,
    }

    if mode == "preinstalled":
        wda_app = Path(required_env("CARINA_WDA_APP")).expanduser().resolve()
        if not wda_app.is_dir():
            raise RuntimeError(
                f"CARINA_WDA_APP does not exist or is not an app bundle: {wda_app}"
            )
        capabilities.update({
            "appium:usePreinstalledWDA": True,
            "appium:prebuiltWDAPath": str(wda_app),
            "appium:autoLaunch": False,
        })
    else:
        # Opt-in only: Appium may build and install its own WDA runner.
        capabilities.update({
            "appium:xcodeOrgId": required_env("CARINA_WDA_TEAM_ID"),
            "appium:xcodeSigningId": "Apple Development",
            "appium:updatedWDABundleId": required_env("CARINA_WDA_BUNDLE_ID"),
            "appium:wdaStartupRetries": 1,
        })

    return capabilities
