# Testing GamaCore

Gama's test module is Swift Testing. Suites live in `Tests/gamaTests` and
run under the pinned Swift 6.5-dev toolchain via `swiftly run swift test`
(scratch path outside iCloud) or `./scripts/check-apple.sh`.

## What is covered here

Portable suites drive ``LayoutEngine``, ``Signal``,
``FrameHost``, and ``TextLayout`` without a platform UI. They prove:

- Integer cell layout, wrapping, and Unicode display width.
- ViewBuilder tuples flatten through ``RenderNode/group(children:)``, not
  ``RenderNode/overlay(alignment:children:)``. A ``ZStack`` with
  ``Alignment/topLeading`` stays an overlay inside a ``VStack``.
- Host-owned subscriptions: cancelling one ``FrameHost`` does not dirty
  another.
- Concurrent hosts do not share action tables (each task owns its ``Signal``).

## What is not XCTest

There is no XCTest suite. Macro expansion tests use
`SwiftSyntaxMacrosGenericTestSupport` and record Swift Testing issues.
AppKit and POSIX PTY tests are Swift Testing suites behind platform
availability checks.

See `docs/Testing.md` in the repository root for invocation, file map, and
sanitizer notes. Linux leak coverage uses the separate `gama-leak-check`
executable rather than this test runner: it exercises a real ``FrameHost``
lifecycle under LeakSanitizer without loading XCTest, then proves the detector
is live with a deliberately retained ``Signal`` negative control. Darwin does
not provide the corresponding LeakSanitizer proof.
