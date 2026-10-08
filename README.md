# Gama

A Zig/std-only component framework with transactional state, integer cell layout, drawing, terminal/plain output, cooperative plugins, C embedding, freestanding WASM, and textual MLIR.

Use the compiler pinned in `.zig-version`; `build.zig.zon` has no package dependencies.

```sh
zig build
zig build demo -- --gama-plain
zig build plugins
zig build check
scripts/check.sh
```

For interactive counter and form editing, run `.agents/skills/run-gama/driver.sh smoke` or `zig-out/bin/demo` in a terminal. The runtime chooses plain output for redirected stdout. Windows supports plain/headless operation.

[Getting started](docs/GettingStarted.md) · [API and ownership](docs/StateAndIdentity.md) · [Documentation](docs/README.md) · [Capabilities and proof limits](docs/Capabilities.md)

The prior Swift, Studio, Qt, Apple-native, Android/JNI and browser-host products are retired from this graph. [Historical records](docs/history/README.md) preserve their decisions; `Package.resolved` is archival locked data.
