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

Deploy CARINA to the physical iPhone and complete device runtime verification.

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
- Passed 25 repository unit tests.

## Current Task

Reconnect the physical iPhone over USB, restart the persistent RemoteXPC tunnel,
and finish the remaining harmless runtime checks.

## Next Task

Verify a harmless OpenClaw request, execute-approval UI, and CARINA App Intent
visibility in Shortcuts on the physical iPhone.

## Known Issues

- The signed Appium control session is not currently active. Unlock the iPhone,
  connect it to the Mac over USB, keep the RemoteXPC tunnel Terminal open, and
  run `make device-control-start` before additional Mac-side UI checks.
- The iPhone is currently visible through CoreDevice over `localNetwork`; the
  Appium RemoteXPC registry has no active USB tunnel.
- App Intent visibility in the Shortcuts app has not been directly verified.
- Local Network, Microphone, and Speech Recognition approval states have not
  all been read back from the physical device.
- A live harmless OpenClaw conversation request has not yet been recorded as a
  completed runtime check.
- The privileged RemoteXPC tunnel reconnects after device interruptions but
  must be authenticated once again after a Mac reboot.

## Last Commit

`ea1798f feat(ios): add signed physical-device control`

## Build Status

✅ Physical-device Debug build succeeded for the current source using automatic
signing and destination `leandros 17pro max`.

## Device Status

- Device: `leandros 17pro max`
- Model: iPhone 17 Pro Max
- Pairing: available and paired
- Current transport: local network; USB tunnel disconnected
- Developer Mode: enabled
- Trust: confirmed
- CARINA installed: yes
- Current Appium session: inactive

## Service Status

- OpenClaw gateway: ready
- CARINA HTTP bridge: installed on port `51001`
- CARINA WebSocket bridge: installed on port `51002`
- Appium: loopback only on port `4723`

## Notes

- Keep OpenAI credentials on the Mac; the iOS app stores only the bridge token
  in the device-only Keychain.
- `127.0.0.1` on iOS points to the iPhone, not the Mac.
- Prefer `leandros-MacBook-Air.local` until a bindable Tailscale interface is
  active.
- Do not push, merge, or open a pull request without explicit authorization.
