# Agent checklists

## Implementation

- [ ] Approved feature ID and scope are recorded.
- [ ] Specification, security requirements, nearest instructions, and ADRs read.
- [ ] State transitions, identities, outputs, and alerts are idempotent.
- [ ] Unsafe input fails closed and preserves restricted evidence.
- [ ] Tests, documentation, and ADR updates are included.

## Security review

- [ ] No original upload is overwritten or automatically deleted.
- [ ] No raw file content or secret is logged or alerted.
- [ ] Archive extraction is sandboxed, bounded, and path-safe.
- [ ] Quarantine/outbox/audit behavior is durable and deduplicated.

## Release verification

- [ ] Required formatter, lint, compile/type, and test commands passed.
- [ ] Feature acceptance criteria have direct verification evidence.
- [ ] Documentation status, code/test locations, and verification record updated.
- [ ] No unresolved blocker remains.
