# 0010 — Terminal is noncopyable

Status: Accepted.

Implements the `Terminal` half of Wave 4C in
`../superpowers/plans/2026-08-27-gama-modernization-refactoring-master-plan.md`
("`Terminal` and private lifecycle tokens are strong candidates after the C
rescue work because unique ownership is semantic"). The C rescue work it
waited on is `Sources/GamaTUISignal/` and `Sources/GamaTUI/TerminalRescue.swift`.

## Context

`Terminal` is not a value. It is a handle to one process-wide resource — the
controlling tty on POSIX, the attached console on Windows — plus the saved
state needed to put that resource back: `originalTermios` and the raw flag on
POSIX; `savedInMode`, `savedOutMode`, `savedCP`, and the raw flag on Windows.

Copying it produced two owners of one tty, each holding its own `isRaw` and
its own snapshot of "the original state". The failure that follows is not a
data race and is not caught by any test that only exercises the happy path:

- The copy taken *before* `enterRawMode()` believes the terminal is not raw.
  It restores nothing, and its `exitRawModeChecked()` is a silent no-op —
  so a shell can be left in raw mode by a path that looks like it cleaned up.
- The copy taken *after* `enterRawMode()` carries a live `isRaw` and a live
  `originalTermios`. Each copy restores independently: the second
  `exitRawModeChecked()` re-emits the ANSI teardown into a terminal that has
  already moved on, calls `tcsetattr` a second time, and calls
  `TerminalRescue.disarm()` against a rescue the first restore already
  disarmed. The rescue's whole contract is that the terminal is restored
  exactly once.

This is a different hazard from [ADR 0006](0006-noncopyable-hosts.md).
There, a copied `FrameHost` silently *shared* reference state, so two
"independent" values mutated one another. Here every copy is fully
independent and that is precisely the bug: **two owners each restoring the
same tty.** Recording them under one ADR would blur two distinct arguments,
so this is a separate record rather than an amendment to 0006.

## Decision

**Both `Terminal` declarations are `~Copyable`** — the POSIX implementation
inside `#if !os(Windows)` and the Windows Console implementation in the
`#else` branch. Raw-console ownership is now noncopyable end to end:
`RawModeSession` already was, and it is the only supported way to hold a
terminal in raw mode.

Explicitly *not* part of this decision:

- **No `deinit` is added to `Terminal`.** Restoration ownership stays with
  `RawModeSession.deinit`, which is where it has always been. This ADR
  changes who may hold a terminal, not who restores it.
- **`exitRawModeChecked()` is unchanged.** It is not reducible to
  `TerminalRescue.restoreNow()`: it additionally emits the ANSI teardown
  (mouse reporting off, SGR reset, cursor shown, alternate screen left),
  restores termios from *this instance's* saved snapshot with `TCSANOW` so
  cleanup cannot block on a stalled output queue, and calls
  `TerminalRescue.disarm()` so the rescue does not restore a second time.
- **`CellBuffer` is untouched.** The same plan section prohibits it until
  profiling proves expensive accidental copies.

## Verification

Move-only enforcement runs in SIL, *after* type checking, so
`swiftc -typecheck` exits 0 on definitively illegal move-only code. Every
claim below comes from a real build, never a type-check.

Twenty-seven ownership probes were run ahead of the change on both the
pinned 6.5-dev snapshot (`org.swift.65202608211a`) and Xcode's Swift 6.4,
with zero behavioral differences between them. What they established, and
what the real build then confirmed:

- **`RawModeSession.deinit` needed no rewrite.** `var t = terminal;
  t.exitRawMode()` compiled unchanged: with a noncopyable `Terminal` the
  binding becomes a *consume* of the stored property rather than a copy,
  which is the semantics the code always wanted. A noncopyable type's
  `deinit` may consume its stored properties; what it may not do is mutate a
  stored property in place (`self` is immutable there) or pass one `inout`.
- **`withTerminal<T>(_ body: (inout Terminal) -> T)` compiled unchanged.** A
  function type may take a noncopyable parameter `inout`.
- **`UnsafeMutablePointer<T>` where `T: ~Copyable`** supports
  allocate/initialize/deinitialize/deallocate, in-place `.pointee` mutation,
  borrowing `.pointee` reads, and `assumingMemoryBound`. Only *copying out*
  of `.pointee` is rejected; `move()` is the alternative, and it
  deinitializes the memory.
- **A global `~Copyable` var may be mutated but never consumed.** This is
  the probe result that predicts
  `Sources/GamaWindowsConsoleSmoke/main.swift` — which mutates a top-level
  `var terminal = Terminal()` — needs no edit. That file is behind
  `#if os(Windows)` and was **not** compiled locally; see the Windows note
  below.

Two call-site accommodations were required, both in
`Tests/gamaTests/TerminalRescueTests.swift`:

- `ResizePollContext` gained an explicit `: ~Copyable`. A struct does not
  become noncopyable by inference from its stored properties; without the
  annotation the compiler reports that a `Copyable`-conforming struct has a
  stored property of non-`Copyable` type.
- Three `#expect(context.pointee.…)` assertions now bind the field to a local
  first. Swift Testing expands a property access into
  `__checkPropertyAccess`, whose generic parameter is implicitly `Copyable`,
  so the macro rejects a noncopyable base. This is the same accommodation
  ADR 0006's Consequences already records for hosts — the probes exercised
  the compiler, not macro expansion, and did not predict it.

No production call site needed a change. `TUIRenderer` already holds
`RawModeSession?` and constructs `Terminal()` directly into the session's
`consuming` initializer.

Gate evidence for this change: `check-apple.sh` (debug build, 230 tests in
46 suites, release build), `check-linux.sh`, `check-mlir.sh`,
`check-boundaries.sh`, `check-docs.sh`, and `check-doc-coverage.sh`.

**The Windows compiler was never run.** Nothing available locally compiles
the `#else` branch: `check-apple.sh`, `check-linux.sh`, and the boundary and
docs gates all take the POSIX side, and Xcode 6.4 is a same-*version* proxy
on a different *platform*, not a Windows build. The Windows
`Terminal: ~Copyable` and `gama-windows-console-smoke` are therefore proven
by the hosted CI Windows job alone, and must not be described as locally
verified.

## Consequences

- A copy of a `Terminal` is now a compile error rather than a second tty
  owner. Consumers pass it `consuming`, `borrowing`, or `inout`.
- This is a public API change: `Terminal` is `public`, so an external holder
  that stored or copied one must migrate. The break is pre-release and
  in-repository consumers migrate atomically.
- Swift Testing property-access `#expect` cannot see through a noncopyable
  base; tests bind first. Any future noncopyable test fixture inherits this.
- Conformances that require `Copyable` cannot be added to `Terminal` without
  superseding this record.
- Wave 4C additionally asks for an API diff, a migration guide, and a
  copy-failure compile fixture for any public ownership change. All three
  are now delivered:
  - **API diff and migration guide** —
    [../TerminalOwnershipMigration.md](../TerminalOwnershipMigration.md),
    whose `## API diff` section is the diff and whose `## Migration` section
    is the guide. It follows `../SceneMigration.md`, this repository's
    precedent for a deliberate pre-release break.
  - **Copy-failure compile fixture** — `Tests/Fixtures/Ownership/`, driven by
    `scripts/check-boundaries.sh`. `error.TerminalMustNotBeCopied.swift` is
    the copy failure itself; `error.CopyableStructCannotStoreTerminal.swift`
    and `error.GlobalTerminalCannotBeConsumed.swift` pin the two derived
    rules this record relies on; `ok.SupportedTerminalOwnership.swift`
    compiles the surface the change left working, and exists so a broken
    include path cannot make the negatives pass vacuously.
    The gate compiles them with `swiftc -c` and requires each negative to
    emit the diagnostic named in its own `// EXPECT-DIAGNOSTIC:` line.
    Measured 2026-08-28 on this committed fixture:
    `-typecheck` exits 0 with no output, `-c` exits 1 with
    `'terminal' consumed more than once`. Weakening the gate back to
    `-typecheck` therefore makes the fixture compile and trips the gate's
    "compiled but must not" branch, so the false negative cannot be
    reintroduced silently.
- **The fixture pins the POSIX declaration only.** It compiles against a
  macOS-built `GamaTUI`, so the `#else` Windows Console `Terminal:
  ~Copyable` remains proven by the hosted CI Windows job alone, exactly as
  the Verification section above states. Nothing about these artifacts
  changes that.
- **The Windows compiler is still never run locally.** This remains the one
  honestly outstanding item of the change as a whole, and no local artifact
  can close it.
