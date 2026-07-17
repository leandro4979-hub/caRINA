# CARINA iPhone Deployment

## Verified configuration

- Xcode project: `apps/ios/Carina.xcodeproj`
- Scheme: `Carina`
- Bundle identifier: `com.leandrofajardo.carina`
- Personal Team: `S6FYTWBGVH`
- Minimum iOS: 17.0
- Connected device: `leandros 17pro max`
- Mac LAN address: `192.168.1.122`
- HTTP bridge: `51001`
- WebSocket bridge: `51002`
- Ollama: Mac loopback `11434`, accessed only through the bridge

## Architecture

```text
iPhone
  |
  v
CARINA SwiftUI + Karina App Intents
  +-- Clever AI app handoff (paid in-app account)
  |
  | authenticated HTTP / WebSocket
  v
Mac bridge (51001 / 51002)
  |
  v
OpenClaw router
  +-- OpenAI Responses API
  +-- Ollama qwen3:8b
  +-- Maya planning
  +-- Hermes read-only runtime
  +-- Karina voice / Shortcuts
```

The iPhone never receives an OpenAI key. It stores only a bridge token in the
iOS Keychain using `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` with
Keychain synchronization disabled.

The OpenAI provider uses the official HTTPS Responses API. Current OpenAI model
guidance and the text-generation guide are available at:

- <https://developers.openai.com/api/docs/models>
- <https://developers.openai.com/api/docs/guides/text>

ChatGPT Plus and OpenAI API billing are separate. A ChatGPT login is not an API
credential and CARINA does not inspect ChatGPT cookies or sessions.

Clever AI is available as an on-device CARINA route. Because its paid plan has
no documented external API, CARINA prepares the prompt, requires a single-use
approval, copies the prompt to a device-local clipboard for ten minutes, and
opens the official Clever AI app. If iOS has offloaded the app, CARINA opens its
official App Store listing (`id1667722375`). Replies remain inside Clever AI
unless that app adds a documented export, Shortcut, App Intent, or API.

## Permission model

| Level | Behavior | Examples |
|---|---|---|
| `read` | Runs after registry validation | system, bridge, OpenClaw, and agent status |
| `prepare` | Produces a preview without a side effect | prepare a Shortcut |
| `execute` | Requires trusted confirmation and a single-use approval | run an allow-listed Shortcut or open Clever AI with a prepared prompt |

Execute approvals expire after five minutes. The iPhone validates the command,
required payload, and SHA-256 fingerprint. The Mac validates the same exact
payload and consumes the approval before execution, preventing replay.

## Start the Mac bridge

```sh
cd /Users/leandrojoelfajardomatute/Documents/CARINA
./scripts/setup_carina_bridge.sh
./scripts/install_carina_bridge_launch_agent.sh
```

The LaunchAgent runtime is installed under
`~/Library/Application Support/CARINA` because macOS privacy prevents background
agents from executing Python environments inside Documents. Its logs are in
`~/Library/Logs/CARINA` and never include bearer tokens or request bodies.

Copy the pairing token without printing it:

```sh
"$HOME/Library/Application Support/CARINA/.venv/bin/python" \
  "$HOME/Library/Application Support/CARINA/bridge/carina_bridge.py" \
  --copy-pairing-token
```

On the iPhone, open CARINA Settings and enter:

- Mac address: `leandros-MacBook-Air.local` (the app default)
- Bridge token: paste from the macOS clipboard

The persistent bridge listens on dual-stack IPv4/IPv6 ports `51001` and `51002`
so the `.local` hostname remains usable when the LAN address changes.

The persistent LaunchAgent can reach Ollama and Hermes. macOS privacy blocks it
from reading the existing Maya key inside Documents. A foreground bridge can
reuse that key in place without copying it:

```sh
cd /Users/leandrojoelfajardomatute/Documents/CARINA
CARINA_OPENAI_ENV_FILE='/Users/leandrojoelfajardomatute/Documents/Documents - leandro’s MacBook Air - 1/Codex/2026-07-11/maya-listener-py/.env.local' \
  .venv/bin/python apps/bridge/carina_bridge.py --host 192.168.1.122
```

## Build and run on the iPhone

1. Open `apps/ios/Carina.xcodeproj` in Xcode beta.
2. Open Xcode Settings > Accounts and sign in to the Apple account that owns
   Personal Team `S6FYTWBGVH`.
3. Confirm Automatically manage signing for the Carina target.
4. Select `leandros 17pro max` as the run destination.
5. Unlock the iPhone and press Run.
6. Approve Local Network, Microphone, and Speech Recognition access.
7. Open CARINA Settings, enter the Mac address and bridge token, then save.
8. Tap Connect and Check Bridge.

## App Intents and Shortcuts

After installation, the Shortcuts app exposes:

- Open CARINA
- Check CARINA Bridge
- Run CARINA Command

Registered commands include `system.status`, `agent.status`, `bridge.status`,
`openclaw.status`, `shortcut.prepare`, and `shortcut.run`. Unknown commands and
missing payload fields are rejected. `shortcut.run` requests confirmation and
opens CARINA for the authenticated approval flow.

## Verification commands

```sh
export DEVELOPER_DIR="$HOME/Downloads/Xcode-beta.app/Contents/Developer"
xcodebuild -project apps/ios/Carina.xcodeproj -scheme Carina \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  -parallel-testing-enabled NO test
python3 -m unittest discover -s tests
make verify
```

## Troubleshooting

- `No Account for Team "S6FYTWBGVH"`: sign in under Xcode Settings > Apple Accounts.
- `No profiles for 'com.leandrofajardo.carina' were found`: after signing in,
  reopen Signing & Capabilities and allow Xcode to create the profile.
- OpenAI quota failure: the existing key authenticates, but its selected API
  project currently returns `You exceeded your current quota, please check your
  plan and billing details.` OpenClaw therefore reports and uses Ollama fallback.
- `127.0.0.1` on the iPhone: rejected because it points to the iPhone. Use the
  default `leandros-MacBook-Air.local` hostname.
- Tailscale reports an address but binding fails: this Mac currently runs
  Tailscale in userspace mode. Use the LAN address until a bindable Tailscale
  interface is active.
- Remove the iPhone bridge token: CARINA Settings > Remove Saved Bridge Token.
- Revoke the OpenAI key: revoke it from the OpenAI Platform project and restart
  the foreground bridge. No OpenAI key is stored in the iOS app or repository.

## Device checklist

- [ ] Apple account signed into Xcode
- [ ] Carina target shows automatic signing with team `S6FYTWBGVH`
- [ ] `leandros 17pro max` selected and unlocked
- [ ] CARINA installed and first screen visible
- [ ] Local Network, Microphone, and Speech Recognition approved
- [ ] Mac address and Keychain bridge token saved
- [ ] HTTP and WebSocket show connected
- [ ] Harmless OpenClaw request returns provider and model
- [ ] Execute request shows Approve Once and Deny
- [ ] CARINA intents appear in Shortcuts
