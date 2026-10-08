# Acceptance

`zig build check` and `scripts/check.sh` run the retained full graph. They require the pinned Zig compiler, Python 3 for tooling and native PTY allocation, Node for WASM execution, tmux for interactive proof, and an existing mlir-opt. No dependency is downloaded or installed by the gate.

The graph includes debug/safe/fast native suites, compile-time rejection, OOM and teardown tests, frozen parity, Unicode regeneration, native terminal process scenarios, linked C consumers, linked WASM plus structural/tamper and Node tests, Cortex-M4 ELF inspection, independent generic MLIR parsing, hosted cross-link matrix, current docs/API negatives, source policies, evidence consistency and interactive examples.

A passing compile is not foreign execution. Parser acceptance with unregistered MLIR dialects is not semantic verification or lowering. Current counts and logs are recorded only in [Capabilities](Capabilities.md). Runtime receipts reference source hashes, because the migration is intentionally uncommitted; Git ancestor checks cannot establish these source bytes.
