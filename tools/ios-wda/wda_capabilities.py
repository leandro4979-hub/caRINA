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
    wda_app = Path(required_env("CARINA_WDA_APP")).expanduser().resolve()

    if not wda_app.is_dir():
        raise RuntimeError(
            f"CARINA_WDA_APP does not exist or is not an app bundle: {wda_app}"
        )

    return {
        "platformName": "iOS",
        "appium:automationName": "XCUITest",
        "appium:udid": udid,
        "appium:usePreinstalledWDA": True,
        "appium:prebuiltWDAPath": str(wda_app),
        "appium:wdaLocalPort": 8100,
        "appium:wdaLaunchTimeout": 60_000,
        "appium:wdaConnectionTimeout": 60_000,
        "appium:autoLaunch": False,
    }
