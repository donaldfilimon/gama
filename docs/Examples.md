# Examples

- `examples/demo.zig`: adaptive counter plus grapheme-aware text form. Plain mode produces one settled surface; interactive mode supports focus and editing.
- `examples/plugins.zig`: static cooperative plugin command and revoked-handle rejection.
- `tests/embed_consumer.c`: complete linked C embedding consumer, including statuses, borrowed output and allocator-failure checks.
- `examples/embedded.zig` and `examples/embedded_app.zig`: caller-bounded Cortex-M4 entry and shared two-publication workload.
- `examples/bench.zig`: retained portable rendering workload and explicitly added deterministic digest.

Commands: `zig build demo -- --gama-plain`, `zig build plugins`, `zig build check-abi`, `zig build check-embedded`, and `zig build bench -Doptimize=fast`. Runtime qualification belongs in [Capabilities](Capabilities.md).
