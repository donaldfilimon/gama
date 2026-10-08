# ADR 0018: Zig/std-only retained framework

Accepted scope on 2026-10-03. The active graph uses the pinned Zig compiler and no package dependencies. Shared layout/rendering, versioned drawing bytes, identity-scoped state, canonical pump/resize, per-axis flexibility and bounded cursor/collection semantics remain principles. Swift-specific enforcement, native-host exceptions in historical ADRs 0016/0017, Apple/Android/browser packaging and Studio/Qt products are retired. Historical ADRs 0004/0007 retain their original supersession narrative in the archive.

The selected boundaries and ownership contract are in the [approved design](../superpowers/specs/2026-10-03-zig-only-framework-design.md). Zig callers own allocator lifetime and stable owner storage; the language does not enforce Swift noncopyability. Qualification belongs in [Capabilities](../Capabilities.md). Separate native UI worktrees/branches are preserved without integration.
