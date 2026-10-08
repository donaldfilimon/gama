# Current Gama documentation

- [Getting started](GettingStarted.md) and [examples](Examples.md)
- [Architecture](Architecture.md), [state and identity](StateAndIdentity.md), [plugins](Plugins.md)
- [Terminal and plain](backends/TUI.md), [C embedding](backends/CEmbed.md), [freestanding WASM](backends/WASM.md)
- [Textual MLIR](MLIRDialect.md), [performance workload](Performance.md)
- [Testing](Testing.md), [toolchain](Toolchain.md), [verification](Verification.md), [troubleshooting](Troubleshooting.md)
- [Capabilities](Capabilities.md), [runner](SelfHostedRunner.md), [historical records](history/README.md)
- [Approved Zig design](superpowers/specs/2026-10-03-zig-only-framework-design.md)

`API.tsv` is the current parser inventory. It includes public declarations and all container/error members across the maintained source set, including generic returns, indirect types and anonymous options. This syntactic superset intentionally includes some private machinery; it is not a claim that every row is an author-facing API.

The AST gate checks nonempty documentation presence, not semantic contract quality. Contract accuracy requires source review. Generated Unicode types and table declarations are included without an exemption; their comments come from the checked-in generator. The private import and bounded factory checks additionally guard accidental table exposure.
