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

The first working build is a local dashboard generator. It reads the Markdown
files in `/Users/leandrofajardo/Documents/AgentOps`, checks local listening
services, and writes a browser-ready dashboard to `dist/dashboard.html`.

## Run

```sh
make dashboard
```

Open the generated file:

```text
dist/dashboard.html
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
`make verify` or `make dashboard` rewrites it from the current AgentOps
Markdown notes and live local listener data. Commit source and documentation
changes, not the generated dashboard file.

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
python3 src/token_counter.py --file /Users/leandrofajardo/Documents/AgentOps/skills.md
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
