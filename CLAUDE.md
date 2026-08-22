# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Read `AGENTS.md` — it is the canonical, up-to-date guide for this repo (stack, commands, architecture, gotchas). Follow it exactly.

Quick anchors:
- **Stack**: `GamaCore` (Embedded-legal view tree) + `GamaTUI` (POSIX/ANSI) + `gama demo`.
- Gate A: `./scripts/check.sh` (Xcode 6.4). Gate B: `./scripts/check-embedded.sh` (OSS snapshot).
- GUI, compiler macros, MLIR, MCU flash are **Proposed**, not Current.

