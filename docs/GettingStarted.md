# Getting started

Use the exact version in `.zig-version`, not rolling master. `zig build` installs the demo, benchmark and plugin example. `zig build demo -- --gama-plain` prints a quiescent frame and exits. `zig-out/bin/demo` in a terminal accepts Tab, Enter, Space, text editing and Ctrl-C.

An application declares exactly one primary entry in `scenes`, with a render callback accepting `*BuildContext`. Create `Host(App)` with an explicit allocator and stable application pointer. Destroy the host before its application or allocator expires. See `examples/demo.zig` for typed state and bindings. Use the [complete gate](Testing.md) before relying on a change.
