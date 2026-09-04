---
name: run-gama
description: Build, launch, screenshot, and drive the Gama demos - the gama-demo terminal UI, the gama-apple-demo AppKit multi-window app, and the MLIR dialect emitter. Use when asked to run Gama, start the demo, take a screenshot of the TUI, drive its controls, or verify a rendering change in the actual running app rather than in tests.
---

# Run Gama

Gama is a Swift 6.5-dev retained-IR UI framework. Its runnable surfaces are
`gama-demo` (terminal UI), `gama-apple-demo` (AppKit multi-window shell), and
`gama-demo --emit-mlir` (prints the `gama` MLIR dialect and exits).

The TUI needs a real tty, so the agent path drives it inside tmux and reads
frames back with `capture-pane`. That harness is
`.agents/skills/run-gama/driver.sh`. Paths below are relative to the
repository root; run everything from there.

## Prerequisites

`tmux` is the only extra tool (`brew install tmux` - verified present at
`/opt/homebrew/bin/tmux`). The toolchain is already pinned by
`.swift-version`; every command goes through `swiftly run` and the driver
clears `TOOLCHAINS` for you.

Confirm the toolchain reports 6.5-dev before debugging anything else:

```bash
unset TOOLCHAINS && swiftly run swift --version
```

## Run: the terminal UI (agent path)

One command builds, launches, drives, asserts, and cleans up:

```bash
.agents/skills/run-gama/driver.sh smoke
```

Verified output: `PASS - launched, rendered, drove focus, and activated a
control.` It writes `before.txt`, `after.txt`, and `activated.txt` (full
text frames) to a private run directory under
`/private/tmp/gama-run-artifacts` and prints that exact path.

For step-by-step control:

```bash
.agents/skills/run-gama/driver.sh build      # pinned build of gama-demo
.agents/skills/run-gama/driver.sh launch     # detached tmux session, 100x30
.agents/skills/run-gama/driver.sh text       # print the current frame
.agents/skills/run-gama/driver.sh snap base  # save the frame to a file
.agents/skills/run-gama/driver.sh focus      # label of the focused control
.agents/skills/run-gama/driver.sh count      # the demo's counter value
.agents/skills/run-gama/driver.sh keys Tab   # any tmux send-keys argument
.agents/skills/run-gama/driver.sh quit       # Ctrl-C and kill the session
```

`keys` forwards to `tmux send-keys`, so `Tab`, `BTab`, `Enter`, `Space`,
`C-c`, and `-l "literal text"` all work.

A verified interaction, exactly as observed on `main` at 1e9fffe
(2026-09-04):

```bash
.agents/skills/run-gama/driver.sh launch
.agents/skills/run-gama/driver.sh focus        # -> −1
.agents/skills/run-gama/driver.sh keys Tab
.agents/skills/run-gama/driver.sh focus        # -> +1
.agents/skills/run-gama/driver.sh keys Enter
.agents/skills/run-gama/driver.sh count        # -> 1
.agents/skills/run-gama/driver.sh keys Space
.agents/skills/run-gama/driver.sh count        # -> 2
.agents/skills/run-gama/driver.sh quit
```

Override `GAMA_RUN_SCRATCH`, `GAMA_RUN_ARTIFACTS`, `GAMA_RUN_SESSION`,
`GAMA_RUN_WIDTH`, or `GAMA_RUN_HEIGHT` when the defaults collide with
another session. The smoke treats `GAMA_RUN_SESSION` and
`GAMA_RUN_ARTIFACTS` as prefixes and adds a private per-run suffix; the
step-by-step commands use their exact values.

## Run: direct invocation (no tty)

The MLIR path is the cheapest way to exercise the view tree, layout, and
lowering without a terminal. Verified: exit 0, 184 lines of dialect.

```bash
.agents/skills/run-gama/driver.sh mlir
```

## Run: the AppKit app

```bash
.agents/skills/run-gama/driver.sh apple
```

This opens real windows and blocks until Command-Q. Verified: it launches
and runs with no stderr output. Pixel capture is NOT available to an agent
session here (see Gotchas), so for programmatic GUI evidence run the
offscreen shell suite instead, which is verified green (6 tests):

```bash
unset TOOLCHAINS
swiftly run swift test --scratch-path /private/tmp/gama-spm --filter AppleShellTests
```

## Test

```bash
unset TOOLCHAINS && ./scripts/check-apple.sh
```

Debug build, the full Swift Testing suite, and a release build. The other
gates are `check-boundaries.sh`, `check-docs.sh`, and `check.sh` for the
whole matrix (parts of which need CI or pinned SDKs).

## Gotchas

- **Keyboard activation works, and the smoke asserts it.** The 2026-08-27
  measurement (`Enter` on `+1` left `count 0` at f52e06c) was the inline
  `@Reactive` state loss that ADR 0011 removed: `CounterPanel` is now built
  inline in the scene closure and keeps its state per surface. Measured
  2026-09-04 on `main` at 1e9fffe: `Enter` on `+1` paints `count 1`, `Space`
  paints `count 2`, `Enter` on `reset` paints `count 0`. If activation ever
  regresses, `driver.sh smoke` fails on its count assertion; check
  `FrameHost.transientStateIDs` first.
- **`capture-pane -p` strips ANSI attributes**, and the focus ring is *only*
  an attribute run (teal `48;2;72;208;208` background). A plain text capture
  therefore cannot tell you what is focused. `driver.sh focus` uses
  `capture-pane -e` and cuts the run at the next escape byte - do not pipe
  it through `cat -v`, because labels contain multibyte glyphs (the minus is
  U+2212) that `cat -v` mangles into `M-bM-`.
- **A wrong `--filter` exits 0.** `swift test --filter "AppKit scene shell"`
  (the `@Suite` display name) matches nothing, prints
  `warning: No matching test cases were run`, and still exits 0. Filter on
  the type name (`AppleShellTests`) and confirm the `Test run with N tests`
  line - an exit code alone is not evidence a test ran.
- **`cat` is aliased to `bat` on this machine**, so `... | cat -v` fails with
  a bat usage error. Use `/bin/cat`. (`ls` is likewise `eza`.)
- **Never build inside the iCloud tree without an external scratch path.**
  The canonical checkout is FileProvider-managed and in-place `swift test`
  fails codesign. Every driver command passes `--scratch-path` under
  `/private/tmp`, so it is verified to work from `~/Desktop/Gama` itself.
- **The demo frame is fixed at 72x18** and clips in a smaller pane; the
  driver pins the session to 100x30. The bottom border can overlap the last
  list row at that size - a rendering artifact, not a driver bug.
- **The app is an unbundled executable**, so it does not appear in
  `lsappinfo` and has no Dock identity. The real `.app` comes from the
  packaging scripts, not from `swift run`.
- **No pixel screenshots from an agent session.** `screencapture` needs
  Screen Recording permission, and `osascript` window enumeration fails with
  `System Events got an error: osascript is not allowed assistive access.
  (-1728)`. Use the text frames from `snap` and the offscreen AppKit suite.

## Troubleshooting

| Symptom | Fix |
|---|---|
| `driver: tmux is required` | `brew install tmux` |
| `driver: <path> missing; run build first` | `driver.sh build`, or pass the same `GAMA_RUN_SCRATCH` you built with |
| `driver: session died on launch` | The binary crashed at startup; run it directly to see stderr |
| `focus` prints nothing | The app has not drawn yet; give it a second, or confirm with `text` that a frame exists |
| `resource fork, Finder information, or similar detritus not allowed` | You built inside the iCloud tree without `--scratch-path` |
| Frame looks shifted or doubled in the pane | Relaunch; the app repaints by absolute-position diff and a scrolled pane leaves stale rows above |
