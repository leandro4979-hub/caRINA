# Archive Service Rules

These restrictions add to root rules and take precedence for archive code.

- Never bulk-extract untrusted archives, use member names as destinations,
  accept encrypted archives by default, or treat parser/scanner/timeout/format
  errors as clean.
- Require signature preflight, metadata/parser bounds, expansion/ratio/count/
  nesting/time limits, offset/overlap validation, strict path and Windows/ADS
  checks, and security quarantine for any violation.
- Extract only in a disposable isolated sandbox with non-root/no-network/
  read-only application filesystem and CPU/memory/disk/process/time limits.
- Use generated output IDs, exclusive creation, canonical containment, actual
  byte counters, true-type validation, and malware scanning for every member.
