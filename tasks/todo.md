# Current Zig migration todo

Implementation and retained acceptance follow the [approved design](../docs/superpowers/specs/2026-10-03-zig-only-framework-design.md). See [Capabilities](../docs/Capabilities.md) for qualified evidence. Historical Swift requirements are archived under docs/history/swift/tasks.

## Main integration — 2026-10-08

The fresh independent whole-change review found no confirmed correctness blocker. Both `scripts/check.sh` and direct `zig build check -j2 -Dmlir-opt=/opt/homebrew/opt/llvm/bin/mlir-opt --summary all` completed successfully against the retained Zig source. Donald explicitly authorized main/origin-main integration in the current maintenance request.

The retired Swift feature histories are preserved through a tree-preserving ancestry merge after the verified rewrite commit; this does not restore their implementations or extend the qualified capabilities. Clean worktrees will be aligned to the same main revision while preserving ignored private data. Foreign runtime, hardware and hosted CI acceptance remain bounded by their actual evidence.
