# Migration

Move from the original greeting and earlier retained TUI API to the modular
framework.

## Greeting compatibility

`Gama.hello()` remains available for one compatibility cycle and preserves the
exact return value and print side effect: `Hello, world!`. It is deprecated.
New applications import `GamaCore`, optionally `GamaMacros`, and one explicit
backend product.

## Earlier TUI applications

Replace process-global action registration and invalidation with one
``FrameHost`` per application host. Express interface structure with typed
views and ``ViewBuilder``; use explicit identifiers for mutable collections.
Renderers implement the lifecycle-based ``Renderer`` contract and receive a
``LaidOutNode`` instead of owning layout or application state.

Terminal output now flows through `GamaDraw.CellBuffer` and its differential
presentation. Other backends consume the coalesced `GamaDraw.DrawList`, so
visual semantics and the foreign-host wire format no longer diverge.

## Testing

Tests migrated from XCTest to Swift Testing. New tests import `Testing` and
follow `docs/Testing.md`. Macro expansion tests no longer depend on
`SwiftSyntaxMacrosTestSupport` (XCTest); they use
`SwiftSyntaxMacrosGenericTestSupport`.
