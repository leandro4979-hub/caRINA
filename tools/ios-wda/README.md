# CARINA iOS WDA smoke testing and authorization

This workflow tests local device connectivity only. It **does not** grant CARINA or an agent permission to perform device actions. A healthy Appium server, signed WebDriverAgent, or established session is not a CARINA approval token.

## Modes

The existing `preinstalled` mode remains the default. It requires `CARINA_IOS_UDID` and `CARINA_WDA_APP` pointing to a previously built WDA .app directory. Managed mode is explicitly selected with `CARINA_WDA_MODE=managed` and requires `CARINA_IOS_UDID`, `CARINA_WDA_TEAM_ID`, and `CARINA_WDA_BUNDLE_ID`. Managed mode permits Appium to build/install WDA, so it requires an individually authorized operator action. Never put these environment variables in a committed secret file.

For the previously verified local configuration the WDA team is `S6FYTWBGVH` and the updated WDA base bundle ID is `com.leandrofajardo.carina.wda`. Reverify profile validity before future sessions. Do not automatically create or revoke certificates, register devices, or refresh provisioning profiles.

Run `python3 -m unittest discover -s tools/ios-wda -p 'test_wda_capabilities.py' -v` from the repository root with `PYTHONPATH=tools/ios-wda`. The smoke script uses Appium 3's root endpoint `http://127.0.0.1:4723` by default. It requires isolated Python dependencies `Appium-Python-Client` and `requests`. Its screenshot option is **off** by default and requires `CARINA_WDA_CAPTURE_SCREENSHOT=1`.

## Authorization boundary

CARINA must classify and authorize each consequential intent separately. The operator must approve WDA installation/launch, session creation, app launches, taps, text entry, screenshots, and device state changes under the existing approval boundary. Do not allow an approved *diagnostic* or *job* to authorize arbitrary subsequent commands. Fail closed if approval is absent, stale, or mismatched; do not treat a validated proposal as applied. The smoke script is a **manual operator utility**, not a CARINA command endpoint.

Perform smoke tests only on authorized test apps or an idle test device. Never automate rewards-game engagement, claiming, account switching, or anti-cheat avoidance. Preserve existing signing assets and app data. End the session using `driver.quit()` even after a failure.

## Evidence and rollback

Record the device status, server health, exact commit, pass/fail results, and whether WDA was installed. Successful session creation establishes transport and XCTest capability, **not** permission for other device interactions. Rollback is to stop using managed mode and revert to the default preinstalled mode. Keep the GitHub PR unmerged until targeted tests and an isolated smoke test pass.
