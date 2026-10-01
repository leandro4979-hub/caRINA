# ADR-003: Browser automation policy boundary

## Status

Accepted for milestone BA-001.

## Context

CARINA needs browser convenience automation without creating a generic auto-clicker or giving site-specific plugins implicit execution authority. The existing CARINA approval architecture already requires fail-closed behavior, explicit authorization, idempotency, and verification.

## Decision

The browser runtime uses the pipeline:

`context -> intent -> score -> safety -> policy -> queue -> execute -> verify`

Plugins are registered through a capability-stripped facade containing only site detection, candidate discovery, evidence signals, and post-action verification. A plugin cannot register an executor or policy override.

Policy is injected into the browser runtime and remains authoritative. Confidence cannot authorize execution. Only an explicit `ALLOW` enters the action queue. `DENY`, `APPROVAL_REQUIRED`, missing policy, and unknown policy states never execute.

Raw credentials and privileged key material remain structurally outside this runtime. Policy proposals are metadata-only and omit raw DOM references and sensitive values.

## Consequences

- New site support can be added without modifying the decision engine.
- Browser plugins cannot bypass central safety or policy.
- The browser runtime remains testable without privileged adapters.
- Safari/WebExtension integration can be added later around this core without changing the authorization model.
- The current in-memory queue provides same-context duplicate suppression only; durable cross-tab or cross-process fencing is deferred to the integration milestone.
