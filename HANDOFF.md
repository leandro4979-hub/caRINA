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
- Repaired the restored-iPhone bridge timeout by making WebSocket port `51002`
  explicitly dual-stack instead of IPv6-only.
- Verified authenticated HTTP on `192.168.1.129:51001`, WebSocket connections
  over LAN IPv4, IPv4 loopback, and IPv6, and OpenClaw on `127.0.0.1:18789`.
- Verified the full Mac bridge -> OpenClaw -> `ollama/qwen3:8b` path returns
  HTTP `200` with the expected response.
- Rebuilt CARINA's SwiftUI command center and secure-link settings around a
  single high-contrast signal color, clearer hierarchy, larger controls,
  Dynamic Type-safe copy, and visible connection/approval states.
- Corrected literal Swift interpolation defects in route, port, loading, empty,
  and composer labels and added a source regression test.
- Visually verified the redesigned app on an iPhone 17 Pro Max simulator.
- Passed all 30 Python tests after the bridge and interface changes.
- Built and signed the redesigned physical-device app with automatic
  provisioning and Personal Team certificate `863R3427Q3`.
- Split CARINA's wire contract into provider routing and optional delegation so
  CARINA remains the primary identity while Maya, Hermes, and Karina work
  behind her.
- Added strict compatibility adaptation for legacy `maya`, `hermes`, and
  `karina` routes and rejection for mixed or unsupported delegate payloads.
- Passed 24 focused bridge routing tests and a generic iOS Simulator build for
  the voice-first routing milestone.
- Replaced the default command-center screen with a CARINA-first Conversation
  home using an original warm editorial design and retained network,
  transcript, provider, delegate, and approval controls under Control.
- Added native Apple speech synthesis, tap-to-talk transcription, response
  playback, interruption, Reduce Motion handling, and a deterministic voice
  state machine covering idle, listening, transcribing, thinking, speaking,
  interrupted, and failed states.
- Visually verified the voice-first home on an iPhone 17 Pro Max simulator and
  confirmed CARINA remains the permanent conversation header.
- Added an explicit Clever AI return flow that offers clipboard import only
  after CARINA becomes active again following an approved handoff.
- Bounded Clever imports to 16,000 characters, labeled imported content as
  Clever-sourced, and verified imported text cannot approve execute actions.
- Passed all 34 Python tests and a generic iOS Simulator build after the Clever
  round-trip implementation.
- Added a local Presence Layer that classifies explicitly captured microphone
  transcripts as assistant, background, or command before bridge/OpenClaw
  serialization; it does not enable continuous background listening.
- Kept room conversation off the agent channel, cleaned verbal fillers and
  wake phrases locally, and preserved permission/approval enforcement for
  classified commands.
- Passed all four focused Presence classifier tests, compiled the complete
  Swift test bundle, passed all 34 Python tests, and rebuilt the Simulator app.

## Current Task

Rebuild, install, and launch the Presence-enabled app on the connected physical
iPhone.

## Next Task

Run final live voice, bridge, delegation, and approval checks.

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
- Clever AI is not installed on the restored phone. CARINA now opens Clever's
  App Store page and copies the prepared prompt when the app is absent.
- Building inside this iCloud-backed checkout can add Finder metadata to the
  generated app and make codesign report `resource fork, Finder information,
  or similar detritus not allowed`. Use `make ios-device-build`; it places
  DerivedData in `/tmp/CARINA-DerivedData` and the signed build succeeds.
- CoreDevice currently marks the physical phone unavailable while iPhone
  Mirroring owns the locked-device session. The redesigned app is signed and
  ready at `/tmp/CARINA-DerivedData/Build/Products/Debug-iphoneos/Carina.app`.

## Last Commit

`2dea94e feat(ios): round-trip Clever responses through CARINA`

Previous bridge milestone: `7049841 fix(bridge): support iPhone IPv4 websocket
connections`

## Build Status

✅ Generic iOS Simulator Debug build succeeded with Xcode 27 beta.

✅ Signed generic iPhone Debug build succeeded with automatic provisioning.

⏳ Redesigned physical-device install is pending CoreDevice availability.

✅ Python tests: 30 passed.

✅ Focused bridge routing tests: 24 passed.

✅ Voice-first routing milestone generic Simulator build succeeded.

✅ Voice-first Conversation and Control build succeeded.

✅ Voice-first simulator launch and screenshot inspection succeeded.

✅ Clever round-trip Python suite: 34 passed.

✅ Clever round-trip generic Simulator build succeeded.

✅ Presence Layer generic Simulator build and Swift test bundle build succeeded.

✅ Presence Layer focused Swift tests: 4 passed.

✅ Current Python bridge tests: 34 passed.

⚠️ The updated Swift test bundle compiled, but Xcode 27 again stopped at the
exact runner state `waiting for workers to materialize`; the run was terminated
after the repeated toolchain failure rather than reported as passed.

⚠️ Current Swift test bundle compiled, but Xcode 27 beta again stopped at
`waiting for workers to materialize`; the most recent completed Swift run
remains 13 passed.

## Device Status

- Device: `17promax`
- Model: iPhone 17 Pro Max
- Pairing: paired and connected; Xcode lists it as a compatible destination
- Current transport: physical iPhone connection available to CoreDevice
- Developer Mode: enabled by user; CoreDevice status field is stale
- Trust: confirmed; Local Network permission allowed
- CARINA installed: yes
- Latest launch attempt: blocked only because the phone was locked; the app was
  installed successfully before that launch request
- Bridge token: saved in device Keychain without exposing it
- Appium session: restartable; foreground control requires CARINA to remain the
  active app while `Fast App Termination` is enabled

## Service Status

- OpenClaw gateway: ready
- CARINA HTTP bridge: installed on port `51001`
- CARINA WebSocket bridge: installed with dual-stack IPv4/IPv6 on port `51002`
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
