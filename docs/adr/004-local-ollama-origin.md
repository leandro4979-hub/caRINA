# ADR-004: Pin local Ollama requests and reject redirects

## Context

The signed macOS app needs the outbound-client entitlement to reach Ollama.
That entitlement is not loopback-restricted. Previously, caller-provided base
URLs and URLSession's default redirects could broaden the configured origin.
A synthetic local probe confirmed that a 307 could forward a POST body.

## Decision

Enforce OLLAMA-NET-001 before both public health and generation sends. Permit
only literal HTTP 127.0.0.1 port 11434 with an empty/root base path and no user
information, query or fragment. Reconstruct endpoint URLs from OllamaConfig.
Use an owned session whose delegate rejects all redirects, and clear legacy
and modern proxies. Preserve test protocol configuration without reusing an
injected session's delegate. Dispose owned sessions after their transport dies.

## Consequences

Alternate Ollama hosts/ports, DNS aliases, HTTPS and redirecting gateways are
intentionally unsupported. Transport policy violations use the existing
badResponse error; cancellation and model availability retain their typed
semantics. Tests use synthetic data and two local HTTP origins, with a positive
receiver control. Custom URLProtocol injection remains trusted executable code.
The OS client entitlement is still broader than this application policy.
This decision does not grant action execution or waive owner security signoff.
