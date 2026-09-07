# Terminal backend (GamaTUI)

Status: Unverified. POSIX TUI and Windows console status live in
[`Capabilities.md`](../Capabilities.md); this guide does not restate
hosted, locally-proven, implemented, or blocked proof. Interactive
human-facing smoke remains supplemental, not automated acceptance.

## Running

```bash
unset TOOLCHAINS
swiftly run swift run gama-demo          # interactive TUI
GAMA_EMIT_MLIR=1 swiftly run swift run gama-demo --emit-mlir   # non-interactive
```

`TUIRenderer` implements the poll-style `Renderer` protocol with
`Failure == TerminalError`; `AppRuntime` (or `MyApp.main(renderer:)`) owns
the blocking loop. `gama-demo` still constructs `TUIRenderer` itself
because of its plugin loop, so interactive proof remains
`.agents/skills/run-gama/driver.sh smoke`, not a redirected `swift run`.

## Adaptive surface

Ordinary apps that should follow stdout use `App.runAdaptive()`:

```swift
let status = try MyApp.runAdaptive()
exit(status.code)
```

A terminal selects `TUIRenderer` (raw mode, differential ANSI, input loop).
A pipe, file, or CI log selects `StreamRenderer`: plain lines, no termios,
no signal dispositions, no input, layout extent fixed at 80×24.
`--gama-plain` and `--gama-tui` override detection; the last flag wins.

`StreamRenderer.waitsForInput` is `false`, so the first quiescent frame ends
the run. Async work must declare `CompletionStatus` via `complete(_:)`;
quiescence is not success, and `complete` does not exit the process.
Opt-in `FailureExitCode` accepts only `1...255` and rejects `0`, negatives,
and `256+` by failing construction (`failure(exitCode:_:)`); the unvalidated
`failure(code:_:)` factory still accepts zero.
This path is pinned by `AdaptiveSurfaceTests` and `StreamOutputTests`. It
is not hosted proven.

On Windows, detection reports a non-terminal, so `runAdaptive()` takes the
stream path unless `--gama-tui` is passed. The Windows console row in the
evidence ledger is Unverified; it is not Blocked.

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

Frames paint through the shared `CellPainter` into `CellBuffer`. An
interactive run presents through `AnsiPresenter`, which wraps
`CellBuffer.presentDiff()`; both true-color and 256-color modes are
supported via `CellBuffer.trueColor`. A stream run presents through
`StreamPresenter`: one line per row whose content changed, then a swap.
Not every terminal-family run writes differential ANSI.
