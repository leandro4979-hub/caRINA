# Glossary

> Precise definitions of terms used throughout this codex.
> Last verified: 2026-08-07

## A

### Abstraction

A representation that exposes essential behavior while concealing implementation detail. Justified when it removes duplication or isolates volatility; unjustified when it adds indirection without either.

### Idempotence

The property whereby repeated application of an operation yields the same result as a single application. Essential for safe retries in distributed systems.

## C

### Codex

A systematically organized body of reference material, structured for retrieval rather than sequential reading.

## D

### Diff (unified)

A textual representation of changes between two file versions, expressed as context lines with `+` and `-` markers.

## I

### Idempotent migration

A schema change that may be applied multiple times without corrupting state, typically guarded by existence checks.

## S

### Scaffold

A minimal, structurally complete project skeleton containing no business logic. Its purpose is to establish conventions before implementation begins.

### Technical debt

The accumulated future cost of a present shortcut. Deliberate debt is a financing decision; accidental debt is a defect.
