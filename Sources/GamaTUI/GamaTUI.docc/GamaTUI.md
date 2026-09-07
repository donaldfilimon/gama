# ``GamaTUI``

Host a Gama application in a terminal with typed errors and enforced
restoration.

## Overview

GamaTUI is the terminal backend: ``TUIRenderer`` implements GamaCore's
poll-style `Renderer` protocol with `Failure == TerminalError`, paints each
laid-out frame through the shared `CellPainter` from GamaDraw, and writes
the differential ANSI update. One code path drives POSIX and Windows
Console terminals alike — ``Terminal`` owns the platform split — and, like
every backend, it only carries events in and frames out; application
semantics stay in GamaCore.

`App.runAdaptive()` selects the surface from stdout:
a terminal gets ``TUIRenderer``; a pipe, file, or CI log gets
``StreamRenderer`` (plain lines, no termios, no input). ``SurfaceMode``
records that choice; `--gama-plain` and `--gama-tui` override detection,
and the last flag wins. `gama-demo` still constructs ``TUIRenderer`` itself
because of its plugin loop — drive it with the `run-gama` skill, not a
redirected `swift run`.

Raw-console ownership is noncopyable: owning a ``RawModeSession`` *is* being
in raw mode, and its `deinit` restores termios state, cursor visibility, and
the alternate screen even on early exits. Every throwing operation uses a
typed ``TerminalError``, so a terminal failure never surfaces as an untyped
error.

Per the evidence ledger (`docs/Capabilities.md`), the POSIX path is locally
proven by PTY escape/UTF-8 and raw-mode-restore suites; the Windows console
path is implemented, and the required Swift 6.4.x job runs input-translator
tests plus the native console mode, UTF-8, and restoration smoke. The evidence
ledger records verified runs; Windows is not 6.5-dev proven, and interactive
terminal acceptance remains a separate manual check.
Running instructions and the input/output details live in
`docs/backends/TUI.md`.

## Topics

### Rendering

- ``TUIRenderer``
- ``StreamRenderer``
- ``SurfaceMode``

### Stream output

- ``StreamSink``
- ``StandardOutputSink``

### Terminal ownership

- ``Terminal``
- ``RawModeSession``
- ``TerminalError``
