# Terminal backend (GamaTUI)

Status: Locally proven (PTY escape/UTF-8 and raw-mode-restore suites) and
hosted proven on the macOS job; the Windows console path runs hosted on
Swift 6.4.x (see the Windows exception in `../Toolchain.md`). Interactive
human-facing smoke remains supplemental, not automated acceptance.

## Running

```bash
unset TOOLCHAINS
swiftly run swift run gama-demo          # interactive TUI
GAMA_EMIT_MLIR=1 swiftly run swift run gama-demo --emit-mlir   # non-interactive
```

`TUIRenderer` implements the poll-style `Renderer` protocol with
`Failure == TerminalError`; `AppRuntime` (or `MyApp.main(renderer:)`) owns
the blocking loop.

## Terminal ownership and restoration

Raw-console ownership is noncopyable end to end: `Terminal` and
`RawModeSession` are both `~Copyable`, and owning a session *is* being in
raw mode. A copied terminal would be a second owner restoring the same tty
([ADR 0010](../adr/0010-noncopyable-terminal-ownership.md); consumers
migrate per [TerminalOwnershipMigration.md](../TerminalOwnershipMigration.md)).
The session's
`deinit` restores termios, cursor visibility, and the alternate screen even
on early exits. `TUIRenderer.end()`
clears its session in a `defer`, so a throwing close (for example a dead PTY)
can never leave the renderer writing to an already-restored terminal.
A clean close also returns all five managed signal dispositions to the host:
`SIGTERM`, `SIGHUP`, `SIGINT`, `SIGQUIT`, and `SIGWINCH`.

## Input

POSIX input is decoded byte-wise from termios (escape sequences, UTF-8,
mouse); Windows uses `ReadConsoleInputW`, so no ANSI input parsing exists on
that path. Ctrl-C arrives as a key event (`ISIG` is disabled) and
`FrameHost` maps Ctrl-C/Ctrl-Q to `wantsQuit`. Resize arrives via
`SIGWINCH`: the handler sets a flag, `nextEvent` drains it ahead of
buffered input, and the shared `HostPump` applies it eagerly — the same
timing as every other backend ([ADR 0008](../adr/0008-one-pump-eager-resize.md)).
It no longer waits for the poll timeout to expire.

`TerminalRescue` restores the tty on the exit paths Swift cannot see:
`SIGTERM`, `SIGHUP`, `SIGINT`, `SIGQUIT`, and `atexit`. `RawModeSession`'s
`deinit` covers every path the type system controls; without the rescue a
supervisor's `SIGTERM` would leave the terminal in raw mode with no echo
and no cursor. The rescue is process-global by necessity — signal
disposition is process-wide — but the private `GamaTUISignal` C target owns
every byte reachable from a handler: saved `termios`, file descriptors,
displaced `sigaction` records, fixed restore bytes, and lock-free
`sig_atomic_t` latches. Swift performs lifecycle calls only outside handler
context. The terminating handler uses a write-free termios-only restoration,
restores every displaced host disposition, and re-raises through the action
that was present before Gama armed rescue. A default action therefore still
terminates with a truthful signal status, while `SIG_IGN` or a host handler
that returns resumes the interrupted host code with its entry `errno` intact.

The PTY suite delivers `SIGWINCH` to a real pthread blocked in `poll`, proves
the `EINTR` path returns one resize with the PTY's new extent, and proves the
latch is drained exactly once. The same serialized suite verifies that clean
session close restores every host-installed managed disposition.

## Output

Frames paint through the shared `CellPainter` into `CellBuffer`, and the
terminal receives the buffer's differential ANSI stream (`presentDiff()`);
both true-color and 256-color modes are supported via
`CellBuffer.trueColor`.
