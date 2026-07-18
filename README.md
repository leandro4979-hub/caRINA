# caRINA

caRINA is the local build focus for Leandro's AgentOps setup.

## iPhone App

The native SwiftUI app is in `apps/ios/Carina.xcodeproj`. It targets iOS 17 or
later, uses automatic signing for Personal Team `S6FYTWBGVH`, and has the bundle
identifier `com.leandrofajardo.carina`.

CARINA is the iPhone client for the agent network:

```text
iPhone CARINA -> authenticated Mac bridge -> OpenClaw
                                         -> OpenAI Responses API
                                         -> Ollama
                                         -> Maya / Hermes / Karina
```

The OpenAI API key stays on the Mac. The iPhone stores only the bridge bearer
token in the device-only Keychain. ChatGPT subscriptions and OpenAI API billing
are separate; CARINA uses the official Responses API when the selected API
project has quota.

Open it with the installed Xcode beta:

```sh
open -a "$HOME/Downloads/Xcode-beta.app" apps/ios/Carina.xcodeproj
```

In Xcode, sign in to the Apple account that owns Personal Team `S6FYTWBGVH`,
select **leandros 17pro max**, and press Run. The first launch asks for local
network, microphone, and speech-recognition access.

CARINA defaults to `leandros-MacBook-Air.local`, which reaches the authenticated
bridge over the current LAN on either IPv4 or IPv6. A Tailscale address can be
entered in Settings when that interface is active. Do not enter `127.0.0.1` or
`localhost`; those addresses point back to the iPhone. CARINA always uses HTTP
port `51001` and WebSocket port `51002`.

Set up and start the Mac bridge:

```sh
./scripts/setup_carina_bridge.sh
./scripts/install_carina_bridge_launch_agent.sh
"$HOME/Library/Application Support/CARINA/.venv/bin/python" \
  "$HOME/Library/Application Support/CARINA/bridge/carina_bridge.py" \
  --copy-pairing-token
```

The final command places the bridge token on the macOS clipboard without
printing it. Paste it into CARINA Settings on the iPhone and use the Mac LAN
address shown in `docs/ios-device-deployment.md`.

Build and test from the command line:

```sh
export DEVELOPER_DIR="$HOME/Downloads/Xcode-beta.app/Contents/Developer"
xcodebuild -project apps/ios/Carina.xcodeproj -scheme Carina \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' build
xcodebuild -project apps/ios/Carina.xcodeproj -scheme Carina \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  -parallel-testing-enabled NO test
```

The project has no external Swift Package Manager dependencies. The plist keeps
global App Transport Security enabled and permits authenticated local-network
development traffic only. See `docs/ios-device-deployment.md` for routing,
permissions, deployment, and troubleshooting.

### Forge Knowledge Feed

CARINA's Forge index feeds approved project notes to the bridge without giving
raw files execution authority. It reads text only, quarantines detected secrets,
limits indexed size, and labels every retrieved excerpt as untrusted reference
material. Imported content cannot approve or increase an action's permission.

```sh
make forge
make forge-status
make forge-install
```

`make forge` refreshes the index from `~/Documents/CARINA-Workspace/00-Inbox`,
the CARINA deployment documentation, and local AgentOps notes. The background
LaunchAgent refreshes a privacy-safe snapshot and
`~/Library/Application Support/CARINA/forge/inbox` every five minutes. Use
`forge.status` or `forge.search deployment` in CARINA to query it without model
execution.

### Deployment Guardian

The guardian keeps the Personal Team build fresh without weakening Apple
signing, trust, or device security. It checks the paired `17promax` every six
hours and rebuilds only when the iOS source snapshot changes, CARINA is missing,
the development profile is within 48 hours of expiry, or four days have passed
since the last successful refresh.

```sh
make deployment-guardian-install
make deployment-guardian-status
make deployment-guardian-run
```

The LaunchAgent builds from a privacy-safe snapshot under
`~/Library/Application Support/CARINA/deployment`, so macOS Documents privacy
does not break unattended signing refreshes. Re-run
`make deployment-guardian-install` after changing iOS source to update that
snapshot. If the phone is locked, installation remains valid and launch is
deferred until the phone is unlocked.

### Hands-On iPhone Live View

Apple ends an iPhone Mirroring session as soon as the physical iPhone is used.
For a live Mac view while operating the phone itself, connect the iPhone and run:

```sh
make iphone-live-view
```

This opens the Mac's AirPlay Receiver settings and keeps the CARINA bridge
running. On the iPhone, open Control Center, tap **Screen Mirroring**, and select
the Mac. This mode displays the phone without activating Continuity Camera, but
it does not provide Mac-side remote control.

For signed Mac-side control of CARINA while the unlocked iPhone stays usable:

```sh
make device-control-install
./scripts/start_carina_appium_tunnel.sh
make device-control-start
```

The tunnel command requires local macOS authentication and must remain running.
The Appium service is restricted to `127.0.0.1:4723`, and the control session is
restricted to `com.leandrofajardo.carina`. See the deployment guide for status,
screenshot, tap, and shutdown commands.

The dashboard reads local Git metadata, AgentOps notes, listening services,
Forge ingestion history, and the deployment guardian state. It shows project
activity, dirty worktrees, seven-day commits, service readiness, signing runway,
and source-backed priorities for the next move.

## Run

```sh
make dashboard
make dashboard-install
make dashboard-status
```

`make dashboard-install` opens and keeps the live dashboard available at:

```text
http://127.0.0.1:51003/
```

You can also run the script directly:

```sh
python3 src/build_dashboard.py
```

## Verify

```sh
make verify
```

## Production Verification Gate

caRINA is intentionally lightweight. The current build uses Python standard
library modules only; `tiktoken` is optional for more accurate token counts.
Use Python 3.9 or newer. This repo is currently verified locally with Python
3.9.6.

Before committing, run:

```sh
make verify
```

The verification gate checks:

- Python syntax for the dashboard builder, archive planner, and token counter.
- Unit tests for Markdown parsing, service status mapping, folder
  classification, and token-counter fallback behavior.
- Dashboard generation to `dist/dashboard.html`.
- Token-counter smoke behavior with direct text input.

`dist/dashboard.html` is generated output and is ignored by git. Running
`make verify` or `make dashboard` rewrites it from current local sources. The
installed dashboard copies a Git project snapshot into Application Support so
macOS privacy does not break its background service, while listeners, Forge,
and signing state remain live. Re-run `make dashboard-install` after adding or
moving repositories. Commit source and documentation changes, not generated
dashboard files.

The token counter uses `tiktoken` when it is installed. If `tiktoken` is not
available, it falls back to a conservative character-based estimate so local
verification still works without extra dependencies.

Do not commit unless `make verify` passes. If verification fails:

- Read the first failing command in the output.
- Fix the smallest issue that explains that failure.
- Re-run `make verify`.
- Do not start or stop services just to make tests pass unless the failure is
  explicitly about live service state and the action has been approved.

## Archive Planning

Preview archive moves without changing anything:

```sh
make archive-dry-run
```

## Token Checks

Estimate prompt or AgentOps note size:

```sh
python3 src/token_counter.py --file "$HOME/Documents/AgentOps/skills.md"
```

The helper uses `tiktoken` when installed. Without it, it returns a conservative
character-based estimate so the dashboard workflow still verifies cleanly.

## Current Build Target

- Keep Codex as the coordinator.
- Use caRINA as the first product surface.
- Read from AgentOps notes instead of duplicating state.
- Show live service health for Codex, OpenClaw, MagnoliaOS, and Ollama.
- Suggest keep/archive/delete-candidate labels for dated Codex session folders.
- Keep all cleanup actions manual until Leandro approves them.

## Current Dashboard Sections

- Live services
- Codex folder review
- Archive manifest summary
- Build priorities
- Inbox
- Agents
- Skills
- Token registry
- Service register
- Observed TCP listeners

## Support the Project

If this tool saved you some time, feel free to buy me a coffee!

[☕ Support via PayPal](https://www.paypal.com/ncp/payment/G4JVKQBYCCYUS)
