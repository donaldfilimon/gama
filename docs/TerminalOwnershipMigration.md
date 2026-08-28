# Migrating to a noncopyable `Terminal`

`GamaTUI.Terminal` is now `~Copyable` on both platforms. This is an
intentional source break: Gama has no published tags or releases, and every
in-repository consumer migrates in the same change. The reasoning — two
owners of one controlling tty, each with its own `isRaw` and its own snapshot
of the original terminal state — is recorded in
[adr/0010-noncopyable-terminal-ownership.md](adr/0010-noncopyable-terminal-ownership.md).

Status: the POSIX declaration is locally proven (`check-apple.sh`,
`check-linux.sh`, `check-boundaries.sh`) and pinned by the compile fixtures in
`Tests/Fixtures/Ownership/`, which `scripts/check-boundaries.sh` drives. The
Windows Console declaration is **hosted-proven only** — nothing available
locally compiles the `#else` branch, so its `~Copyable` rests on the CI
Windows job. Evidence vocabulary is defined in
[Capabilities.md](Capabilities.md#status-vocabulary).

## API diff

One line changed on each of the two platform declarations
(`Sources/GamaTUI/Terminal.swift:85` POSIX, `:493` Windows Console):

```diff
-public struct Terminal {
+public struct Terminal: ~Copyable {
```

Nothing else in the type's public surface moved. No member was added,
removed, renamed, or re-signed; no `deinit` was introduced (restoration
ownership stays with `RawModeSession.deinit`).

### What this now forbids

| Construct | Result |
| --- | --- |
| A second binding of a `Terminal` (`let a = t; let b = t`) | `error: 't' consumed more than once` |
| Storing a `Terminal` in a `Copyable` aggregate | `error: stored property '…' of 'Copyable'-conforming struct '…' has non-Copyable type 'Terminal'` |
| `consume`-ing a global `Terminal` var | `error: missing reinitialization of inout parameter '…' after consume while accessing memory` |
| Passing a `Terminal` to a generic whose parameter is implicitly `Copyable`, or into `Array`-shaped storage that requires `Copyable` | rejected at the constraint |
| Adding a conformance whose requirements assume a copyable `Self` (`Equatable`, `Hashable`, `Codable`) | rejected; would supersede ADR 0010 |

Mutating a global `Terminal` var in place is still legal — only *consuming*
one is not. That is why `Sources/GamaWindowsConsoleSmoke/main.swift`, which
mutates a top-level `var terminal = Terminal()`, needed no edit.

### What still works unchanged

```swift
public struct RawModeSession: ~Copyable {
    public init(terminal: consuming Terminal) throws(TerminalError)
    public mutating func withTerminal<T>(_ body: (inout Terminal) -> T) -> T
    public func size() -> Size
    public mutating func write(_ string: String) throws(TerminalError)
    public mutating func nextEvent(timeoutMillis: Int) throws(TerminalError) -> InputEvent?
    public mutating func close() throws(TerminalError)
}
```

- `RawModeSession(terminal: consuming Terminal)` — the supported handoff. It
  already took the terminal `consuming`, so the call site is byte-identical.
- `withTerminal<T>(_ body: (inout Terminal) -> T)` — a function type may take
  a noncopyable parameter `inout`; the escape hatch is unaffected.
- `size()` — still non-`mutating`, so a borrowed terminal can be measured.
- `enterRawMode()`, `exitRawMode()`, `exitRawModeChecked()`, `write(_:)`,
  and `nextEvent(timeoutMillis:)` — still `mutating`, same signatures, same
  typed `TerminalError`.
- `TerminalError` is untouched and remains `Sendable`.

`Tests/Fixtures/Ownership/ok.SupportedTerminalOwnership.swift` is the
executable form of this section: it compiles every construct listed here, and
the boundaries gate fails if any of them stops compiling.

## Migration

### The one change most consumers need

A struct does **not** become noncopyable by inference from its stored
properties. Anything that stores a `Terminal` must say so:

```diff
-struct TerminalBox {
+struct TerminalBox: ~Copyable {
     var terminal: Terminal
 }
```

Without the annotation the compiler reports:

```
error: stored property 'terminal' of 'Copyable'-conforming struct
'TerminalBox' has non-Copyable type 'Terminal'
note: consider adding '~Copyable' to struct 'TerminalBox'
```

The same applies transitively: once `TerminalBox` is `~Copyable`, whatever
stores a `TerminalBox` needs the annotation too.

### Replace copies with a deliberate ownership choice

```diff
-var scratch = terminal      // second owner of the tty
-scratch.exitRawMode()
+terminal.exitRawMode()      // mutate in place, or …
```

Pass the terminal `consuming` when the callee takes ownership, `inout` when
it mutates and gives it back, `borrowing` when it only reads. If the value is
genuinely finished with, `consume` it explicitly.

### Swift Testing gotcha

`#expect` on a *property access* whose base is noncopyable does not compile.
The macro expands a property access into `__checkPropertyAccess<T>`, whose
generic parameter is implicitly `Copyable`, so it rejects a noncopyable base.
Bind to a local first:

```diff
-#expect(!context.pointee.failed)
-#expect(context.pointee.receivedSize == Size(width: 87, height: 31))
+let pollFailed = context.pointee.failed
+let observedSize = context.pointee.receivedSize
+#expect(!pollFailed)
+#expect(observedSize == Size(width: 87, height: 31))
```

This is a macro-expansion limit, not an ownership rule; the same accommodation
is already recorded for noncopyable hosts in
[adr/0006-noncopyable-hosts.md](adr/0006-noncopyable-hosts.md).
`Tests/gamaTests/TerminalRescueTests.swift` shows all three call sites.

### Pointers to a noncopyable terminal

`UnsafeMutablePointer<T>` supports `T: ~Copyable`: allocate, initialize,
deinitialize, deallocate, in-place `.pointee` mutation, borrowing `.pointee`
reads, and `assumingMemoryBound` all work. Only *copying out* of `.pointee`
is rejected — `move()` is the alternative, and it deinitializes the memory.

## Verifying a migration

```bash
unset TOOLCHAINS
./scripts/check-boundaries.sh   # drives Tests/Fixtures/Ownership/
./scripts/check-apple.sh
```

The ownership fixtures are compiled with `swiftc -c`, never `-typecheck`:
move-only enforcement runs in SIL, *after* type checking, so `-typecheck`
exits 0 on definitively illegal move-only code. If you write your own
ownership check, use a real build or it will pass while proving nothing.
