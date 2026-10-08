# Swift baseline provenance for Zig migration

This is a historical migration oracle, captured on 2026-10-03 from main at
b8ce774285c79d83a4bf3ffff7b11975d4716af2 plus the inherited MLIR builder
cleanup. It is data for parity review, not a current platform capability claim.
No baseline production implementation was changed by this capture.

The corpus lives in [manifest.json](../../../tests/parity/manifest.json).
Each entry records byte length and SHA256. JSON is UTF-8; NodeID UInt64
values are decimal strings to avoid JavaScript numeric rounding. Geometry
uses the native baseline's signed 64-bit Int. Binary `.gama` files are the
actual little-endian GAMA wire-version-1 output. ANSI escape bytes are JSON
escaped, preserving exact strings. Text row values follow Swift `rowText`,
which trims trailing blank padding. MLIR files end in the emitter's exact
newline. Swift debug spellings in diagnostic JSON identify observed cases;
consumers should compare semantic fields rather than require Zig diagnostic
spelling to include Swift module names.

| Corpus | Runtime generator and baseline reference |
| --- | --- |
| geometry-identity | Point saturation, Rect edges/inset/intersection, Size clamping, exact NodeID path hashes; Geometry.swift and RenderNode.swift |
| unicode-editing, control-key-classification | Swift Character clusters, current terminal-width policy, wrap, all editing operations with collapsed/reversed/out-of-bounds selections, letter/lowercase classification; TextLayout.swift, TextEditing.swift, CInterface.swift |
| layout-16x8, layout-9x5 | Actual border/padding/stacks/spacer layout trees and cells, paint, ANSI initial/clean/changed, plain initial/clean, DrawList binary, escaped/styled HTML and laid MLIR; Layout.swift, CellPainter.swift, CellBuffer.swift, DrawList.swift, WASMHost.swift |
| wide-cell-overwrite | Combining/wide/VS16 cells, overwrite of a continuation, bounded oversized normalization; CellBuffer.swift |
| state-lifetime | Positional versus identified reordering, two-host isolation, retained increment, subtree eviction and default reinitialization; ViewStateIdentityTests.swift and ReactiveState.swift |
| focus-actions | Field grapheme insertion/cursor movement, tab/activation/shortcut/named dispatch, disabled actions, returned interaction identities/frames; ActionIdentityTests.swift and FrameHost.swift |
| plugins and plugin MLIR | Required capability denial, deterministic installation and command order, cached command revocation, stable survivor/reinstallation IDs, exact grants and lexical paths; PluginRuntime.swift and Capability.swift |
| embed initial/increment/statuses | Built-in C diagnostic app through versioned entrypoints, dirty/clean/null/invalid-key statuses and real binary frames; CInterface.swift and EmbedABITests.swift |
| c-embed initial/increment | Separately compiled/linked C consumer's create/frame/Enter/frame/clean/destroy lifecycle; byte-identical to Swift entrypoint capture |
| structural/escaping MLIR | Real structural lowering, attribute ordering, quote/backslash/newline/tab escaping; Lowering.swift and MLIRFixtureTests.swift |

The runtime generator is [archived ZigParityCaptureTests.swift source](../../history/swift/migration/ZigParityCaptureTests.swift.txt),
with [capture-embed.c](../../../tests/parity/capture-embed.c) providing the
independent C language caller. The original HEAD archive and exporter
archive under `.superpowers/sdd/2026-10-03-zig-only-framework-rewrite/baseline`
preserve both implementations for provenance before Task12 removes Swift.
[Source hashes](source-hashes.json) freeze the exact source inputs.
[Surface inventory](surface-inventory.json) classifies every graph declaration
and records every original tracked path; only later tasks perform cutover.

Before Swift cutover, reproduce in the canonical checkout:

```sh
env -u TOOLCHAINS GAMA_PARITY_OUTPUT="$PWD/tests/parity/swift-baseline" \
  swiftly run swift test --scratch-path /private/tmp/gama-zig-oracle-swiftpm
env -u TOOLCHAINS swiftly run swift build \
  --scratch-path /private/tmp/gama-zig-oracle-swiftpm --product GamaEmbed
cc -std=c17 -Wall -Wextra -Werror -I Sources/GamaEmbedABI/include \
  -c tests/parity/capture-embed.c -o /private/tmp/gama-zig-oracle-swiftpm/capture-embed.o
env -u TOOLCHAINS swiftly run swiftc /private/tmp/gama-zig-oracle-swiftpm/capture-embed.o \
  /private/tmp/gama-zig-oracle-swiftpm/out/Products/Debug/libGamaEmbed.a \
  -o /private/tmp/gama-zig-oracle-swiftpm/capture-embed
/private/tmp/gama-zig-oracle-swiftpm/capture-embed \
  tests/parity/swift-baseline/c-embed-initial.gama \
  tests/parity/swift-baseline/c-embed-increment.gama
python3 tests/parity/verify.py
```

The compiler reported Swift 6.5-dev, LLVM 64c3046d94ae7cc, Swift 95c5142e84b82c1,
arm64-apple-macosx27.2.0. Full Swift Testing passed 407 tests in 68 suites,
including seven exporter tests. XCTest's discovery shim printed zero tests;
that shim count is not the Swift Testing count. A filtered repeat passed
seven tests in one suite and reproduced all 29 Swift files byte-for-byte.
The C consumer produced two more goldens, both byte-identical to their Swift
entrypoint counterparts. Full logs, command records, initial exporter-only
compile failure and exit codes live in the task report directory.

Coverage limits are explicit: this bounded corpus does not exhaust every
primitive/style/action combination or malformed wire input. Existing Swift
assertions remain in the preserved baseline archive. The approved Zig tasks
must add their own allocator/OOM, stale-generation, transaction, hostile
input, Unicode 17 conformance and new WASM-v1 tests. Swift Character behavior
is an observed baseline; terminal width is independently pinned and not a
claim of Unicode 17 conformance. HTML is retained as a serializer oracle,
while the browser host/export families are retired. Textual MLIR goldens do
not establish independent parser acceptance. Neither the Swift suite nor
these archives qualify foreign platform execution or hardware runtime.
