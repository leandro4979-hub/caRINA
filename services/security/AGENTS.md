# Security Service Rules

These restrictions add to root rules and take precedence for security code.

- Security decisions are deterministic and fail closed.
- Do not access, log, transmit, or expose raw quarantined content except through
  approved restricted evidence handling.
- Security alerts contain identifiers, reason codes, and hashes only.
- Any release or exception requires explicit approval, a recorded audit event,
  and a fresh validation/scan.
