# Architecture decision records

Each record: Status / Context / Decision / Consequences. Statuses use the
vocabulary from `../Capabilities.md#status-vocabulary`; "Accepted" decisions
are locked until a superseding ADR says otherwise.

| # | Decision | Status |
| --- | --- | --- |
| [0001](0001-own-the-rendering.md) | Own the rendering: retained RenderNode IR, no platform-widget wrapping | Accepted |
| [0002](0002-toolchain-pinning.md) | Toolchains.toml is the pin authority; Windows stays on 6.4.x by exception | Accepted |
| [0003](0003-swift-testing-only.md) | Swift Testing only; XCTest is banned | Accepted |
| [0004](0004-signal-confinement.md) | Signal stays `@unchecked Sendable` under executor confinement; Synchronization is banned in GamaCore | Accepted (interim) |
| [0005](0005-drawlist-wire-format.md) | DrawList binary wire format v1 and its versioning policy | Accepted |
| [0006](0006-noncopyable-hosts.md) | FrameHost and AppRuntime are noncopyable | Accepted |
| [0007](0007-frame-pumps.md) | Four per-backend frame pumps remain, pending unification | Superseded by 0008 |
| [0008](0008-one-pump-eager-resize.md) | One canonical HostPump; resize policy is eager on every backend | Accepted |
