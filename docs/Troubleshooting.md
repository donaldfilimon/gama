# Troubleshooting

Status: Current operational guide for the pinned repository workflows. The
fixes below preserve fail-closed evidence; they do not turn a missing platform
or tool into a passed gate.

## Wrong Swift toolchain

**Symptoms:** unexpected syntax errors, package-manifest failures, missing
main-development features, or a version other than Apple Swift 6.5-dev.

```bash
unset TOOLCHAINS
swiftly run swift --version
```

Use `swiftly run` for everyday commands. Do not globally switch compilers to
repair one checkout. See [Toolchain.md](Toolchain.md) for the exact snapshot,
SDK pins, Xcode exception, and Windows exception.

## FileProvider or codesign failures

**Symptoms:** resource-fork/Finder-information errors, codesign failures in
`.build`, inconsistent executable metadata, or repeated rebuild churn.

The canonical checkout is FileProvider-managed. Put scratch state outside it:

```bash
unset TOOLCHAINS
swiftly run swift test --scratch-path /private/tmp/gama-tests
```

The maintained scripts already default their heavy products to
`/private/tmp`. Do not run Git garbage collection or repacking in this
checkout.

## A filtered test exits zero but ran nothing

Swift Testing filters use source identifiers. A display name such as
`--filter "AppKit scene shell"` may print “No matching test cases were run”
and exit zero.

Use the type name:

```bash
swiftly run swift test \
  --scratch-path /private/tmp/gama-shell-tests \
  --filter AppleShellTests
```

Confirm the final test count rather than relying only on the exit status.

## The terminal demo needs a TTY

**Symptoms:** no frame, raw-mode errors, missing focus attributes, or a demo
that exits immediately under a pipe.

Use the maintained tmux driver:

```bash
.agents/skills/run-gama/driver.sh smoke
```

It pins a 100x30 pseudo-terminal, because the demo's 72x18 frame clips in a
smaller pane. `capture-pane -p` strips ANSI attributes; use the driver's
`focus` command to inspect the highlighted control.

If a stale session remains:

```bash
.agents/skills/run-gama/driver.sh quit
```

Or override `GAMA_RUN_SESSION`, `GAMA_RUN_SCRATCH`, and
`GAMA_RUN_ARTIFACTS` for an independent run.

## The macOS demo is not a packaged application

`swift run gama-apple-demo` launches an unbundled executable. It may have no
Dock identity and does not establish bundle layout, signing, notarization, or
install behavior.

Use:

- The driver for live AppKit windows.
- `AppleShellTests` for automated shell behavior.
- The packaging scripts for a staged `.app` and archive.
- The credentialed workflow for Developer ID/notarization proof.

## No programmatic pixel screenshot

Native screenshot and accessibility automation require macOS permissions not
granted to every agent/session. If `screencapture` or `System Events` reports a
permission failure, record that boundary rather than fabricating a visual
result.

Use TTY text snapshots for `gama-demo` and the offscreen AppKit suites for
programmatic native-host behavior. Manual visual/accessibility acceptance is a
separate layer.

## A stateful component resets

**Symptom:** component state returns to its initial value after an action
causes a new frame.

Building the component inline in the scene-content closure is not the cause:
`@Reactive` state is host-owned per surface and survives the rebuild. Check
these instead:

- `@Reactive` outside a struct marked `@Component` (including inside a
  class) is a compile error (`@Reactive requires a struct marked
  @Component; elsewhere its state never binds to a host`).
- A hand-written `render(in:)` in a `@Component` with `@Reactive`
  properties is a compile error (`@Component synthesizes render(in:) to bind
  @Reactive state; remove this render(in:) or the @Reactive properties`).
- Unstable structural identity: a branch flip, a positional `ForEach`
  reorder, or a different component type at the same position evicts the
  old key. Read `FrameHost.transientStateIDs` after the frame — it lists the
  nodes whose storage was reconstructed. Pin the subtree with
  `IdentifiedForEach` or `.stateScope(_:)`.
- `State` and raw `Signal` stored properties are instance-local and reset
  with the instance. Convert a raw `Signal` inside a component to
  `@Reactive`; a raw `Signal` belongs on the `App`.

See [StateAndIdentity.md](StateAndIdentity.md).

## External model changes do not repaint

**Symptom:** a signal/model changes outside a Gama action, but
`FrameHost.needsFrame` stays false.

Bound `@Reactive` state does not need this: every host-owned signal already
observes the host, so an out-of-band write sets `needsFrame` on its own.
A raw `Signal` the `App` owns must be connected to the host:

```swift
host.observe(modelSignal)
```

Or use `subscribe(in:)`, `binding(in:)`, or explicit `invalidate()`. Do not
add a process-global registry.

## Duplicate or unstable focus

**Symptoms:** focus moves to an unexpected row after insertion, or
`duplicateIDs` is nonempty.

Use `IdentifiedForEach` with stable domain IDs for mutable collections. Do not
use a current array position as durable identity. Ensure repeated interactive
subtrees do not derive the same explicit `NodeID`.

## WASM build passes but browser behavior is unknown

A Swift/WASM compile is only one layer. Run:

```bash
./scripts/check-wasm.sh
```

The gate includes the installed-host unsafe-slot policy, Node event/frame
smoke, deployable-site assembly, and headless browser behavior. Missing Chrome
or SDK artifacts must fail rather than silently skip.

## Android cross-build passes but the app is not proven

`check-android.sh` proves both ABIs and runtime-library packaging. Runtime
behavior requires `check-android-emulator.sh`, whose product assertion is an
input-driven frame change on API 36. An APK file or successful Gradle assemble
alone is not that proof.

Use the exact NDK pinned in `Toolchains.toml`; older NDK libraries do not meet
the dated Swift runtime's libc++ ABI requirements.

## MLIR text emits but the parser gate fails

The demo emission path proves deterministic text production. The gate also
requires:

```bash
mlir-opt --allow-unregistered-dialect
```

Ensure the pinned LLVM tools are on `PATH`. Do not describe emitted text as a
Swift MLIR frontend; Gama emits a textual custom dialect.

## DocC or documentation links fail

Run the fast link layer first:

```bash
python3 scripts/check-doc-links.py --self-test .
```

Then run:

```bash
./scripts/check-docs.sh
./scripts/check-doc-coverage.sh
```

DocC warnings are errors. A new public declaration needs `///` documentation;
do not expand the allowlist to make an ordinary omission pass.

## A complete matrix fails for a missing prerequisite

That is intended. The complete matrix is fail-closed. Install/use the exact
pinned prerequisite or rely on a hosted job that genuinely supplies it, then
report the local/hosted boundary. Do not edit a gate to reinterpret “missing”
as “passed.”

## Branches cannot be merged or deleted safely

Before integrating or deleting a branch:

1. Fetch and inventory local/remote refs and worktrees.
2. Check open pull requests.
3. Compare branch-only commits and patch identity against `main`.
4. Preserve dirty or unique concurrent work.
5. Merge through the protected PR workflow.
6. Delete only refs with no remaining unique history or active PR.

Branch names and age are not evidence that their contents are obsolete.
