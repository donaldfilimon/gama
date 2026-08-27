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

Raw-console ownership is noncopyable: `RawModeSession` is `~Copyable`, and
owning one *is* being in raw mode. Its `deinit` restores termios, cursor
visibility, and the alternate screen even on early exits. `TUIRenderer.end()`
clears its session in a `defer`, so a throwing close (for example a dead PTY)
can never leave the renderer writing to an already-restored terminal.
`SIGTERM`/`SIGHUP` restoration hooks are a known gap, ledgered under
Slice C in `tasks/todo.md` (Provisional).

## Input

POSIX input is decoded byte-wise from termios (escape sequences, UTF-8,
mouse); Windows uses `ReadConsoleInputW`, so no ANSI input parsing exists on
that path. Ctrl-C arrives as a key event (`ISIG` is disabled) and
`FrameHost` maps Ctrl-C/Ctrl-Q to `wantsQuit`. Resize is observed by
polling the size after an event timeout; `SIGWINCH` delivery is a ledgered
Slice C item.

## Output

Frames paint through the shared `CellPainter` into `CellBuffer`, and the
terminal receives the buffer's differential ANSI stream (`presentDiff()`);
both true-color and 256-color modes are supported via
`CellBuffer.trueColor`.
