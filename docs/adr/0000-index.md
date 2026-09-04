# Architecture decision records

Each record: Status / Context / Decision / Consequences. Statuses use the
vocabulary from `../Capabilities.md#status-vocabulary`; "Accepted" decisions
are locked until a superseding ADR says otherwise.

| # | Decision | Status |
| --- | --- | --- |
| [0001](0001-own-the-rendering.md) | Own the rendering: retained RenderNode IR, no platform-widget wrapping | Accepted |
| [0002](0002-toolchain-pinning.md) | Toolchains.toml is the pin authority; Windows stays on 6.4.x by exception | Accepted |
| [0003](0003-swift-testing-only.md) | Swift Testing only; XCTest is banned | Accepted |
| [0004](0004-signal-confinement.md) | Interim unchecked Signal confinement and the final declaration-layer consequences | Superseded by 0009 |
| [0005](0005-drawlist-wire-format.md) | DrawList binary wire format v1 and its versioning policy | Accepted |
| [0006](0006-noncopyable-hosts.md) | FrameHost and AppRuntime are noncopyable | Accepted |
| [0007](0007-frame-pumps.md) | Four per-backend frame pumps remain, pending unification | Superseded by 0008 |
| [0008](0008-one-pump-eager-resize.md) | One canonical HostPump; resize policy is eager on every backend | Accepted |
| [0009](0009-signal-is-not-sendable.md) | Signal and PluginRuntime are not Sendable; host confinement is compiler-checked | Accepted |
| [0010](0010-noncopyable-terminal-ownership.md) | Terminal is noncopyable; one owner restores the tty | Accepted |
| [0011](0011-reactive-state-is-per-surface.md) | @Reactive state is per-surface, host-owned and keyed by identity; a Signal on the App is shared | Accepted |
| [0012](0012-strict-memory-safety-and-explicit-imports.md) | Strict memory safety with error promotion on shipped targets; explicit import access levels everywhere | Accepted |
