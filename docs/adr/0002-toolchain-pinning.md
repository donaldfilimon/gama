# 0002 — Toolchain pinning policy

Status: Accepted.

## Context

The framework rides a rolling Swift main-development snapshot (6.5-dev) for
noncopyable generics, typed throws, and Embedded Swift, while Xcode's
integrated SwiftPM must still resolve the package and swift.org has
published no Windows main snapshot since 2026-05-20-a.

## Decision

`Toolchains.toml` is the single pin authority (snapshot selector, toolchain
id, compiler revisions, SDK URLs and SHA-256s); `.swift-version` selects the
snapshot for swiftly; the manifest deliberately stays
`swift-tools-version: 6.4`; Windows runs the proven 6.4.x installer as a
documented exception. `scripts/check-toolchain-pins.sh` fails the boundary
gate whenever CI, the check scripts, or `.swift-version` drift from the
TOML.

## Consequences

Every proof names an exact compiler; snapshot bumps are deliberate,
one-commit events touching the TOML plus its verified consumers; Windows
capability claims must carry the exception until swift.org resumes Windows
main snapshots (re-verify before re-claiming).
