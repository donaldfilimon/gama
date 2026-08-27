# CLAUDE.md

Read `AGENTS.md`; it is the canonical project guide.

This is the canonical checkout of `donaldfilimon/gama` — the Gama Framework
umbrella (retained UI core, macros, drawing, TUI/Apple/WASM/Embed/MLIR
backends). The Qt adapter was removed on 2026-08-26; `~/dev/active/gama-qt`
is an unrelated Qt browser app that shares only the name.

## Toolchain — this repo overrides the machine-wide Swift rule

`.swift-version` pins `main-snapshot-2026-08-21` (Apple Swift 6.5-dev,
toolchain id `org.swift.65202608211a`); the check scripts pin it explicitly.
The manifest deliberately stays `swift-tools-version: 6.4` so Xcode's
integrated SwiftPM can still resolve the package (the xcodebuild platform
gates depend on that) — the 6.5-dev identity lives in the compiler pin, not
the manifest grammar. Always `unset TOOLCHAINS` first — a stray value overrides both the swiftly shim and the scripts'
explicit `xcrun --toolchain` pins.

## iCloud constraints (measured, not theoretical)

This tree is FileProvider-managed. In-place `swift test` fails at codesign
("resource fork, Finder information, or similar detritus not allowed");
`xattr -rc` does not fix it. The check scripts already route builds through
`/private/tmp` scratch paths — use them, or pass `--scratch-path` outside
iCloud yourself. `swift build` / `swift run` work in place.

Git: prefer `.git`-internal reads; `git status` can hang here. NEVER run
`git gc`, `git prune`, `git fsck`, or `git repack` in this directory.

## Gates

`./scripts/check-apple.sh` (build/test/release), `check-boundaries.sh`,
`check-docs.sh` locally; `./scripts/check.sh` is the full matrix (parts
require Linux/CI). CI is `.github/workflows/ci.yml` — six jobs, all pinned
to the same snapshot family with SHA256-verified downloads.
