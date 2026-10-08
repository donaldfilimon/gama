# Gama Zig-only framework design
Status: Approved by Donald on 2026-10-03 for implementation; implementation proof belongs in docs/Capabilities.md.

This design is bound by the Global Constraints, Review Focus, Interfaces, and Acceptance in ../plans/2026-10-03-zig-only-framework-rewrite.md. The user-approved plan is the source of scope. Its required preservation, no-commit, main-branch, std-only, platform-retirement, Unicode, ABI, and evidence rules apply to every task.

## Structure
build.zig/build.zig.zon own the graph. src/root.zig is the gama package entrypoint. Portable code lives under src/core/, src/draw/, src/plugins/, src/mlir/. Hosted code lives under src/tui/, src/services/, src/abi/. examples/ contains runnable Zig applications. tests/parity/ retains source-independent Swift golden data; tests/compile_fail/ pins compile-time rejection; tools/ owns std-only validation and Unicode generation.
Portable imports must not instantiate std.process, hosted I/O, thread IDs, or page allocation in freestanding artifacts. All library allocation is explicit.

## Authoring and state
Components are ordinary structs with render(self: *const Self, context: *BuildContext) Error!Node; typed tuple children replace result builders. Scene descriptors contain ID, role and render callback, validate exactly one primary at host construction; only primary is presented by retained adapters.
Host(App).create(allocator, app: *App) Error!*Self. Application storage is stable and outlives all its hosts. Owning hosts are internal and exposed by exclusive borrowed pointer APIs destroy/handle/invalidate.
prepare(size) Error!?PreparedFrame stages IR, layout, registrations and newly allocated state. commit/abort closes every prepared frame once; painters/serializers finish before commit. Aborted frames retain previous presentation, release candidate resources and retain dirty retry. Input-accepted model changes persist across failed rendering.
BuildContext.state(T,slot,initial) Error!StateRef(T) keys by NodeID/slot. Reads borrow; writes clone owned values before replacing prior values. Managed values explicitly provide clone/deinit hooks. Removed state is swept after successful final frame. Type replacement is diagnosed and generation-invalidates prior references.
Action callbacks use typed captures stored in candidate frame storage. Raw temporary pointers/slices are rejected; value captures and framework handles are supported. Shared application Signal values subscribe explicitly to hosts; cancellation is host-owned and idempotent.
Generation validation rejects stale handles during owner lifetime. No handle or borrowed slice may outlive its host. Zig does not promise Swift noncopyability or Sendable enforcement. Native adapters enforce thread confinement/reentrancy, portable artifacts remain single-executor by contract.

## Rendering and foreign surfaces
Port baseline integer/per-axis layout, exact NodeID mixing, grapheme-based editing, separately pinned terminal width, bounded cell storage, presenter/serializer distinction and deterministic output.
Unicode extended grapheme segmentation uses owned generated Unicode 17.0 data and official conformance vectors. Control-key alphabetic/lowercase classification must preserve baseline behavior.
DrawList little-endian GAMA wire version 1 stays exact; maximum_cell_count is 16*1024*1024; strict bounded decode rejects malformed magic/version/counts/truncation/UTF-8/trailing bytes.
C gama_embed_v1 signatures/statuses/lifetimes retained. OOM is -4 (context_create returns null; frame writes -4 length). No callbacks retain borrowed frame storage beyond next frame/destruction.
Retire old browser gama_web families. Import-free gama_wasm_v1 exports: init(i32,i32)->i32, shutdown()->void, key(i32,i32,i32,i32)->i32, pointer(i32,i32,i32)->i32, resize(i32,i32)->i32, needs_frame()->i32, frame()->i32, frame_ptr()->u32, frame_len()->u32. frame 1 published/0 clean; errors -1 uninitialized/-2 invalid key/-3 frame too large/-4 OOM. Successful init replaces; failed init preserves installed host. Bytes are DrawList v1, borrowed until next frame/init/shutdown. Export memory. No WASI/DOM/JS imports.

## Hosted limits
Only std APIs, no handwritten OS bindings or production C. std-required libc on macOS allowed. TUI macOS/Linux; Windows plain/headless only. Signal rescue restores settings without allocation, logging or blocking output. Structured owned returns/errors and managed signals are covered; direct external process exit and uncatchable termination are not.
Tier-1 plugins remain cooperative, exact-match grants, deterministic order, lexical path checks, stable identity/revocation and per-host isolation. Hosted services receive std.Io; freestanding required-but-unavailable services fail closed.
MLIR is textual lowering; goldens are not independent parser proof. Cortex-M4 artifacts are compile/link proof, not hardware runtime.

