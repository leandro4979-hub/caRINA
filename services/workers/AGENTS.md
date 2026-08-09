# Worker Service Rules

These restrictions add to root rules and take precedence for worker code.

- Claim durable operation keys before side effects; honor leases and guarded
  transitions.
- Use retry only for classified transient failures. Unknown work requires
  recovery, not guessed success.
- Write outputs and notifications idempotently, and publish through the outbox.
- One job failure must not stop unrelated jobs.
