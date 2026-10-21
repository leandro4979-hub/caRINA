# caRINA Mac app

A deliberately small, macOS-only SwiftUI app for validating local Ollama
streaming before it is connected to any approval or action screen.

Open this folder in Xcode, select the `CarinaMacApp` scheme, and run it. The
app imports the sibling `CARINAApprovalBoundary` package, which connects only
to loopback Ollama at `127.0.0.1:11434`. It has no iPhone target, API key,
remote fallback, or permission to execute actions.

## Verification boundary

- DEBUG slow-stream cancellation passed end-to-end.
- The Release build compiled successfully and excludes the slow-stream fixture
  and its UI toggle.
- Release generation remains Mac-local through Ollama on `127.0.0.1`.
- No iPhone extension access, remote listener, or network exposure was added.

The Conversation tab is deliberately separate from the Local Test diagnostic
screen and from every approval or action-execution surface.

Conversation diagnostics record only lifecycle events (started, cancelled,
completed, or failed) in the local system log. They never include prompts or
model responses. Conversation context is bounded and drops the oldest messages
first, with a visible notice when that occurs.

## Dependability slice

The Conversation tab verifies local model availability through the existing
typed health check and shows checking, ready, unavailable, or missing-model
states. It offers **Check Ollama** only for unavailable or missing-model
states, includes the exact local pull command for a missing model, and supports
Command-Return to send and Command-Period to stop. This adds no endpoint,
listener, entitlement, or iPhone access.

### macOS SQLite linkage

The shared package uses macOS SDK SQLite through `CSQLite`, without consulting
Homebrew's `sqlite3.pc`. Linking a signed Xcode app to Homebrew SQLite can abort
in `dyld` before startup because their Team IDs differ. Keep library validation
enabled; the fix is to link `/usr/lib/libsqlite3.dylib`. Non-macOS builds retain
pkg-config discovery. After changing the manifest, rebuild the `Carina` scheme.

The Xcode `Carina` target also enables the sandbox's outgoing network client
capability so it can connect to loopback Ollama. App Sandbox and Hardened Runtime
remain enabled; no incoming network capability is added. macOS's client entitlement
is not restricted to loopback, so endpoint restrictions remain enforced by app code.

### Ollama origin and redirects

Health and generation now enforce `http://127.0.0.1:11434` before sending.
Other hosts/ports, credentials, base paths, query strings and fragments are
rejected. A dedicated production URLSession rejects all redirects and disables
proxy dictionaries and modern proxy configurations. No remote fallback is used.
Existing local streaming, cancellation and model health behavior is preserved.
The regression HTTP fixture uses `/usr/bin/python3` on macOS and synthetic data.

### Verified recovery checks

- [x] Ollama running with `llama3.2:3b` present shows green **Model ready**.
- [x] With Ollama temporarily stopped, caRINA shows **Ollama is not running**
  and exposes **Check Ollama**.
- [x] After restarting Ollama, **Check Ollama** returns to **Model ready**
  without restarting caRINA.
- [x] A temporary DEBUG-only missing-model check showed the exact
  `ollama pull nonexistent-model:0b` remediation and was reverted immediately.
- [x] Command-Return sends and Command-Period cancels a generation.

The status and retry controls have stable accessibility identifiers:
`ModelStatusIndicator` and `RetryHealthButton`.
