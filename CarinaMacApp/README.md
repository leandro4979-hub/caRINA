# caRINA Mac app

A deliberately small, macOS-only SwiftUI app for validating local Ollama
streaming before it is connected to any approval or action screen.

Open this folder in Xcode, select the `CarinaMacApp` scheme, and run it. The
app imports the sibling `CARINAApprovalBoundary` package, which connects only
to loopback Ollama at `127.0.0.1:11434`. It has no iPhone target, API key,
remote fallback, or permission to execute actions.

## caRINA 0.4.0 terminal

The Terminal tab is the primary tactile surface for caRINA 0.4.0. It uses a
full-screen, monospaced local-console design with visible streaming output,
status indication, clickable controls, keyboard shortcuts, selectable text,
and macOS trackpad haptic feedback.

Local console commands:

- `/status`
- `/skills`
- `/audit`
- `/standards`
- `/skill coding-standards`
- `/skill security-audit`
- `/skill off`
- `/about`
- `/clear`
- `/stop`
- `/help`

The terminal is intentionally a conversation sandbox. User text is sent only
through the existing loopback `OllamaClient`; the terminal does not execute
shell commands, expose a listener, add a remote fallback, bypass approvals, or
connect to an action executor.

### Skill layer

The prototype includes two local reasoning skills:

- **CODING STANDARDS** applies the repository's `CODING_STANDARDS.md` behavior:
  smallest safe change, explicit typed state, fail-closed security boundaries,
  secret/data protection, honest execution reporting, and verification.
- **SECURITY AUDIT** reproduces the interactive audit flow from the terminal
  reference: establish the trust-boundary change, rank the assets/worst-case
  failures, choose scope, choose deliverable, then report severity-labeled
  findings. Settings outside source control remain explicitly unverified and
  are converted into an operator checklist instead of guessed.

The active skill is visible in the terminal header. `/audit` also prints the
four-question audit interview directly into the console. A bounded in-memory
conversation context lets subsequent answers continue the same audit thread.
No skill expands the terminal's authority: these are reasoning instructions,
not shell access or execution capabilities.

Keyboard controls:

- Command-Return: send
- Command-Period: stop generation

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
