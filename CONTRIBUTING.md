# Contributing

Read [AGENTS.md](AGENTS.md). Use the exact Zig pin and explicit allocators. Keep production code within Zig/std; ask before changing the dependency boundary. Add focused behavioral regressions for changes to state, Unicode, serialization, OOM and ownership. Do not edit generated Unicode data by hand.

Run `zig fmt build.zig build.zig.zon ZigToolchain.zon src tools examples tests`, then `zig build check` and `scripts/check.sh`. The check requires Python 3, Node, tmux and mlir-opt. Rust clippy does not apply to this Zig-only graph. Document public declarations and members, and update the maintained current guides when contracts change. Proof receipts must be regenerated from actual runs; do not weaken negative controls or skip required leaves.
