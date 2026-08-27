# 0003 — Swift Testing only

Status: Accepted (2026-08-27 migration; policy in `../Testing.md`).

## Context

The suite was a 56/18 XCTest/Swift Testing mix. XCTest forced the
`SwiftSyntaxMacrosTestSupport` product on macro tests, and the Linux
XCTest runner's process-lifetime metadata retention forced
`ASAN_OPTIONS: detect_leaks=0` in CI.

## Decision

Every suite uses Swift Testing (`@Suite`/`@Test`/`#expect`); XCTest is
banned, including transitively — macro expansion asserts through the
framework-agnostic `SwiftSyntaxMacrosGenericTestSupport` with an
`Issue.record` failure handler.

## Consequences

One assertion idiom and parameterized tests; property-access `#expect`
needs value binding for noncopyable bases; `detect_leaks=1` may return once
a hosted run proves the Swift Testing runner leak-clean (open ledger item).
