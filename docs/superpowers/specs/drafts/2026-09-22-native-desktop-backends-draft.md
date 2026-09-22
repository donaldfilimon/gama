# Native Windows and Linux desktop backends — draft

Status: Draft. Open questions, not a commitment. Nothing here is built.

Both are grouped here because they are the same shape of work — a windowed
host alongside `GamaAppleUI`/`GamaAppleShell` — and because each is gated
by something outside the repository rather than by design.

## What already exists, stated precisely

**Windows has a real console backend, and it is not a GUI.**
`Sources/GamaTUI/Terminal.swift` carries a genuine Win32 path behind
`#elseif os(Windows)`: a console input-record translator, VT output
enabled through `SetConsoleMode` (throwing if unavailable, so Windows 10
1511 is the floor), and mode/code-page restoration. `gama-windows-console-
smoke` runs — actually executes, not merely compiles — on `windows-2025`
in CI, asserting console mode and code page are restored bit-for-bit.
`docs/Capabilities.md` describes this as implemented and keeps the Windows
job required. None of it is a window, a menu, or a pointer.

**Linux is console and cross-compile, not desktop.** `GamaCore`/`GamaTUI`
are locally cross-compile proven against the static Linux SDK and an
aarch64 musl build. There is no Wayland, X11, or desktop session code of
any kind.

## The blockers, which are not design problems

**Windows: no 6.5-dev toolchain.** swift.org has published no Windows
main-development snapshot since 2026-05-20, so the Windows job is pinned to
the newest proven 6.4.x branch snapshot and `docs/Capabilities.md` says in
so many words that Windows is not 6.5-dev proven. Strict memory safety
(ADR 0012) therefore also runs on the 6.4.x exception there. A GUI backend
can be *written* against 6.4.x, but it would be the only part of the system
proven on a different compiler than everything else, and that divergence
should be a deliberate decision rather than a side effect.

**Linux: no desktop to prove it on.** There is no Linux desktop hardware
and no CI runner with a display server in the matrix. A Wayland or X11
backend could be built and would be unprovable here — which
`docs/Capabilities.md`'s vocabulary would have to record as Implemented at
best, never Locally or Hosted proven. The repository's evidence rules are
strict enough that building something unprovable has a real cost.

Both blockers are also currently masked by a third: while the account
billing lock holds, no hosted job runs at all, so even the Windows console
evidence that does exist cannot be refreshed.

## What the work would actually be

Read `GamaAppleShell` first: it owns `NSApplication`/`NSWindow` lifecycle,
multi-window, and per-shell command routing, and it is the one backend that
renders auxiliary scenes rather than only the primary one. A native desktop
backend on either platform is that role, re-implemented — window lifecycle,
input translation into `InputEvent`, and presentation of `DrawList` — not
a new application model. ADR 0001 already settled that Gama owns its
rendering rather than wrapping platform widgets, so neither backend should
reach for native controls.

The portable-import ban keeps all of this outside `GamaCore`,
`GamaDraw`, and their siblings, exactly as the Apple backends are.

## Open questions

1. Does a desktop backend need native *text* (DirectWrite, Pango) or does
   the existing cell model plus a monospaced font carry it? The cell grid
   is the framework's model everywhere else; a proportional-text desktop UI
   would be a much larger change than a backend.
2. Is Windows GUI worth starting before a 6.5-dev snapshot exists, given
   it would sit on a different compiler from the rest of the matrix?
3. For Linux, is a headless proof (a virtual display in CI) acceptable
   evidence, and what would `docs/Verification.md` call that rung? It is
   not obviously any of the eight that exist.
