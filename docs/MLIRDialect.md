# Textual MLIR

`gama.mlir` lowers retained nodes/layout into generic operation syntax. Text is caller-owned; release it with the supplied allocator. Strings are escaped and child/result numbering is deterministic. Ordinary output is compared with frozen baseline fixtures; controls and vocabulary have explicit coverage.

`zig build check-mlir` emits nine scenarios in each native optimization mode and invokes an existing mlir-opt with --allow-unregistered-dialect. This validates generic parser syntax only. Registered dialect semantics, executable lowering and hardware execution require separate evidence.
