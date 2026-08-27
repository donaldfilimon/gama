# ``GamaTUI``

Host a Gama application in a terminal with typed errors and enforced
restoration.

## Overview

GamaTUI is the terminal backend: ``TUIRenderer`` implements GamaCore's
poll-style `Renderer` protocol with `Failure == TerminalError`, paints each
laid-out frame through the shared `CellPainter` from GamaDraw, and writes
only the differential ANSI update. One code path drives POSIX and Windows
Console terminals alike — ``Terminal`` owns the platform split — and, like
every backend, it only carries events in and frames out; application
semantics stay in GamaCore.

Raw-console ownership is noncopyable: owning a ``RawModeSession`` *is* being
in raw mode, and its `deinit` restores termios state, cursor visibility, and
the alternate screen even on early exits. Every throwing operation uses a
typed ``TerminalError``, so a terminal failure never surfaces as an untyped
error.

Per the evidence ledger (`docs/Capabilities.md`), the POSIX path is locally
proven by PTY escape/UTF-8 and raw-mode-restore suites; the Windows console
path is implemented and its input translators run hosted on Swift 6.4.x, but
it is not 6.5-dev proven and native console behavior is not a shipped claim.
Running instructions and the input/output details live in
`docs/backends/TUI.md`.

## Topics

### Rendering

- ``TUIRenderer``

### Terminal ownership

- ``Terminal``
- ``RawModeSession``
- ``TerminalError``
