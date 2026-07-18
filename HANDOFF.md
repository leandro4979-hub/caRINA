# CARINA Deployment Status

## Execution Mode

1. Work on one objective at a time.
2. Do not add placeholder implementations.
3. Build every change before moving on.
4. Commit each completed milestone.
5. Keep this file current.
6. Prefer OpenClaw and local models for routine analysis.
7. Reserve Codex for complex implementation and verification.
8. Do not repeat context recorded here.
9. Stop only when the deployment objective is complete or a required physical
   action blocks progress.

## Current Objective

Redeploy the rebuilt CARINA experience to the restored physical iPhone and
restore its authenticated Mac connection.

## Completed

- Created backup branch `backup/pre-ios-deployment-20260716`.
- Configured `apps/ios/Carina.xcodeproj` for iOS 17.0 or later.
- Configured automatic signing for Personal Team `S6FYTWBGVH`.
- Configured bundle identifier `com.leandrofajardo.carina`.
- Added microphone, speech-recognition, local-network, App Intent, and Shortcuts
  configuration.
- Kept App Transport Security enabled with scoped local-development access.
- Replaced iPhone loopback routing with configurable Mac LAN or Tailscale host
  settings.
- Configured authenticated bridge ports: HTTP `51001`, WebSocket `51002`.
- Installed and launched CARINA on `leandros 17pro max`.
- Verified the first CARINA screen on the physical iPhone.
- Verified CARINA can connect to `carina-openclaw-bridge` from the iPhone.
- Installed loopback-only Appium/XCTest control on `127.0.0.1:4723`.
- Built and signed WebDriverAgent with Personal Team `S6FYTWBGVH`.
- Verified Mac-side CARINA screenshot capture and an accessibility-driven bridge
  health-check click.
- Verified OpenClaw gateway readiness on `127.0.0.1:18789`.
- Added deterministic, schema-validated handling for `system.status`,
  `shortcut.prepare`, and approval-gated `shortcut.run` before model routing.
- Connected `RunCarinaCommandIntent` to the authenticated bridge and preserved
  explicit confirmation for execute-level commands.
- Verified generated App Intent metadata contains Open CARINA, Check CARINA
  Bridge, Run CARINA Command, and all three allow-listed command values.
- Verified authenticated `system.status` returns the live OpenClaw/Ollama and
  agent health state without model execution.
- Verified `shortcut.prepare Get Clipboard` prepares without execution.
- Verified `shortcut.run Get Clipboard` remains waiting for approval and then
  executes exactly once through macOS Shortcuts after explicit approval.
- Verified OpenClaw routes to `ollama/qwen3:8b` and direct Ollama responds.
- Passed 28 Python unit tests and 13 Swift unit tests.
- Rebuilt the signed physical-device Debug app successfully after the final
  source changes.
- Confirmed there are no CARINA crash reports on the physical iPhone.
- Added a verified Clever AI handoff using its universal link, custom URL
  scheme, and App Store fallback after a phone restore.
- Added an iOS 26+ Apple Intelligence route using Foundation Models for private,
  on-device responses without OpenAI API usage.
- Rebuilt the iPhone interface as an adaptive native command core with Liquid
  Glass on iOS 26+ and an iOS 17 material fallback.
- Rebuilt the Mac AgentOps dashboard with the same dark command-core design and
  only real listener and repository data.
- Passed the iOS generic simulator build after the interface and local-model
  changes.
- Passed the signed generic iPhone build with the Personal Team provisioning
  profile after moving DerivedData outside iCloud Drive.
- Passed all 28 Python tests after the Mac dashboard redesign.
- Built for `DINO’s iPhone`, installed bundle `com.leandrofajardo.carina`, and
  confirmed Xcode accepts the restored phone as a physical destination.
- Switched macOS iPhone Mirroring from `Old phone ios 14` to the restored
  `17promax` iPhone selection.
- Installed and validated the personal Codex skill `build-personal-skills`.
- Created the non-destructive staging workspace at
  `~/Documents/CARINA-Workspace`.

## Current Task

Reconnect the restored iPhone to the same iCloud account as the Mac, then use
iPhone Mirroring to save CARINA's bridge token.

## Next Task

Verify CARINA's authenticated HTTP and WebSocket connection, then verify Apple
Intelligence, Clever AI, and OpenClaw routing.

## Known Issues

- App Intent registration is present in the signed build metadata, but its
  visual listing inside the physical Shortcuts app has not been observed while
  the phone remained available for automation.
- Local Network is proven by the live iPhone-to-Mac bridge connection;
  Microphone and Speech Recognition approval states still need visual readback.
- iOS Developer setting `Fast App Termination` is enabled. CARINA is terminated
  whenever another app takes foreground focus during XCTest control. This is
  not a crash; the device produced zero CARINA crash reports.
- A final simulator re-run on the Xcode/iOS 27 beta was interrupted after the
  simulator test worker failed to materialize. The same Xcode 27 runner issue
  repeated after the UI update and was stopped after 70 seconds with the exact
  state `waiting for workers to materialize`. The immediately preceding
  13-test Swift run passed, while current simulator and signed-device builds
  both compile successfully.
- The privileged RemoteXPC tunnel reconnects after device interruptions but
  must be authenticated once again after a Mac reboot.
- OpenAI is optional and currently unavailable to the LaunchAgent because
  macOS privacy blocks its external environment file. OpenClaw and Ollama are
  ready and remain the working local route.
- CoreDevice's `developerModeStatus` field remains stale at `disabled`, but
  Xcode lists `DINO’s iPhone` as a compatible destination and successfully
  built and installed CARINA on it.
- The first post-restore launch is blocked until the user trusts the Personal
  Team profile under Settings > General > VPN & Device Management.
- Clever AI is not installed on the restored phone. CARINA now opens Clever's
  App Store page and copies the prepared prompt when the app is absent.
- Restoring the phone cleared CARINA's device-only Keychain token; it must be
  pasted once after reinstalling CARINA.
- Building inside this iCloud-backed checkout can add Finder metadata to the
  generated app and make codesign report `resource fork, Finder information,
  or similar detritus not allowed`. Use `make ios-device-build`; it places
  DerivedData in `/tmp/CARINA-DerivedData` and the signed build succeeds.
- iPhone Mirroring now targets the restored phone, but currently reports:
  `iPhone Not Found To use iPhone Mirroring, make sure “17promax” is signed in
  with the same iCloud account as this Mac.`

## Last Commit

`305cc33 feat(mac): redesign live CARINA command center`

## Build Status

✅ Generic iOS Simulator Debug build succeeded with Xcode 27 beta.

✅ Signed generic iPhone Debug build succeeded with automatic provisioning.

✅ Restored-device build and installation succeeded.

⏳ First launch pending one-time trust of the Personal Team profile.

✅ Python tests: 28 passed.

✅ Swift tests: 13 passed before the later Xcode beta simulator-worker hang.

## Device Status

- Device: `DINO’s iPhone`
- Model: iPhone 17 Pro Max
- Pairing: previously paired; CoreDevice currently reports unavailable
- Current transport: iPhone Mirroring selected but blocked by iCloud account
  mismatch; Tailscale currently reports the restored phone offline
- Developer Mode: enabled by user; CoreDevice status field is stale
- Trust: confirmed
- CARINA installed: yes
- Appium session: restartable; foreground control requires CARINA to remain the
  active app while `Fast App Termination` is enabled

## Service Status

- OpenClaw gateway: ready
- CARINA HTTP bridge: installed on port `51001`
- CARINA WebSocket bridge: installed on port `51002`
- Appium: loopback only on port `4723`
- RemoteXPC: privileged retrying tunnel active

## Notes

- Keep OpenAI credentials on the Mac; the iOS app stores only the bridge token
  in the device-only Keychain.
- `127.0.0.1` on iOS points to the iPhone, not the Mac.
- Prefer `leandros-MacBook-Air.local` until a bindable Tailscale interface is
  active.
- Do not push, merge, or open a pull request without explicit authorization.
- Resume foreground control with `make device-control-start` after confirming
  the iPhone is unlocked and CARINA may remain in the foreground.
- Create future personal skills with `$build-personal-skills`; place loose
  inputs in `~/Documents/CARINA-Workspace/00-Inbox` only when intentionally
  staging them.
