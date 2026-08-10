from __future__ import annotations

import os
import sys
from typing import Any

import requests
from appium import webdriver
from appium.options.common import AppiumOptions

from wda_capabilities import build_capabilities


APPIUM_URL = os.environ.get("APPIUM_URL", "http://127.0.0.1:4723")


def appium_server_is_alive() -> bool:
    try:
        response = requests.get(f"{APPIUM_URL}/status", timeout=5)
        return response.ok
    except requests.RequestException:
        return False


def main() -> int:
    if not appium_server_is_alive():
        print(
            f"ERROR: Appium is not responding at {APPIUM_URL}",
            file=sys.stderr,
        )
        return 2

    capabilities: dict[str, Any] = build_capabilities()
    options = AppiumOptions()
    options.load_capabilities(capabilities)

    driver = None

    try:
        print("Creating Appium/XCUITest session...")
        driver = webdriver.Remote(
            command_executor=APPIUM_URL,
            options=options,
        )

        status = driver.get_status()
        print("WDA/Appium session established.")
        print(f"Session ID: {driver.session_id}")
        print(f"Status: {status}")

        screenshot = driver.get_screenshot_as_png()
        if not screenshot:
            raise RuntimeError("WDA session exists but returned an empty screenshot.")

        output_path = "wda-smoke-test.png"
        with open(output_path, "wb") as output_file:
            output_file.write(screenshot)

        print(f"Screenshot captured successfully: {output_path}")
        return 0

    except Exception as exc:
        print(f"WDA/Appium smoke test FAILED: {exc}", file=sys.stderr)
        return 1

    finally:
        if driver is not None:
            driver.quit()


if __name__ == "__main__":
    raise SystemExit(main())
