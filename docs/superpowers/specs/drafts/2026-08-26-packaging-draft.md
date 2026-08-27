# Gama umbrella — packaging & distribution (sub-project 4) — DRAFT

Date: 2026-08-26. Status: **draft for review** (nothing here is approved;
everything not labeled "exists today" is Proposed).

Parent: `docs/superpowers/specs/2026-08-26-gama-umbrella-foundation-design.md`
(sub-project decomposition, item 4: ".app/.exe/wasm bundle/embedded static
lib").

## Problem

Gama's gates prove that code *runs* on six platform families, but nothing in
the repo turns a Gama app into a thing a person can double-click, deploy to a
static host, or link into a foreign build. CI uploads evidence artifacts, not
shippable ones. This spec designs the artifact story per platform, the tooling
shape, and the metadata home — and cuts a V1 slice.

Design constraints inherited from the foundation spec and `AGENTS.md`:

- One `Package.swift`; no second build system.
- `GamaCore` stays stdlib-only (`scripts/check-boundaries.sh` enforces the
  import list) — packaging must never leak Foundation into the framework.
- Evidence vocabulary applies to artifacts too: an artifact is only "shippable"
  when its declared verification gate passes (`docs/Capabilities.md` policy).
- The canonical checkout is iCloud-managed. `CLAUDE.md` records the measured
  failure: FileProvider stamps `com.apple.FinderInfo` /
  `com.apple.fileprovider.fpfs#P` onto built bundles and codesign rejects them
  ("resource fork, Finder information, or similar detritus not allowed").
  **Any step that codesigns a bundle must stage it outside the repo tree**,
  exactly as the check scripts already route scratch paths through
  `/private/tmp` (`scripts/check-apple.sh:5`).

## 1. Inventory — what exists vs. what shipping needs

### Exists today (verified by reading, not built in this session)

| Piece | Where | State |
| --- | --- | --- |
| WASM demo binary | `wasm-artifacts` upload in `.github/workflows/ci.yml` (wasm job); `scripts/check-wasm.sh` copies it to `.build/artifacts/gama-web-demo.wasm` | Built with pinned WASM SDK, exports `gama_web_v1_{frame,key,pointer,resize}` |
| Browser host | `WebHost/index.html` + `WebHost/gama.js` (191 lines, dependency-free: WASI stubs, DOM event bridge, rAF loop) | `gama.js:151` fetches `./gama-web-demo.wasm` **relative**, so host + wasm in one directory is already a self-contained static site |
| Browser verification | `scripts/browser-runtime-smoke.mjs` — spins a local HTTP server, drives headless Chrome over CDP, asserts the `OK;frames=…;accessible=true` marker | Takes `<gama.wasm> <WebHost>` args; maps `/gama-web-demo.wasm` to the artifact path |
| Embedded objects | `embedded-artifacts` upload: `.build/artifacts/GamaCore.embedded.o` + `.linked.o` from `scripts/check-embedded.sh` | Bare-metal ARM ELF evidence, not a consumable SDK |
| C embed SDK pieces | `libGamaEmbed.a` (static product, `Package.swift` `GamaEmbed`) + `Sources/GamaEmbedABI/include/GamaEmbed.h` (versioned `gama_embed_v1_*` ABI); `scripts/check-c-abi.sh` compiles/links/runs `Examples/CEmbed/main.c` against them | All pieces proven; never assembled into one distributable directory |
| Android packaging | `scripts/check-android.sh` already does real packaging: builds `libGamaAndroidDemo.so` for x86_64 + arm64-v8a, computes the transitive Swift-runtime `.so` closure with `llvm-readelf`, stages `jniLibs/`, adds `libc++_shared.so`; Gradle app in `Examples/Android`; emulator gate asserts an input-driven frame change | The closest thing to a finished ship story in the repo — missing only release `assembleRelease` + keystore signing |
| Linux | `scripts/check-linux.sh` builds **only the `GamaCore` target** (aarch64 musl) with the static SDK; the CI linux job separately runs native tests and `check-c-abi.sh` | No app binary is produced |
| Windows | CI windows job builds and runs `gama-windows-console-smoke` (`Sources/GamaWindowsConsoleSmoke/main.swift`) with the pinned 6.4.x snapshot; the install step already locates the Swift runtime `bin` directory (`Runtimes\…\usr\bin`) | The `.exe` exists in CI scratch, is never staged with its runtime DLLs, never uploaded |
| macOS GUI host | `Examples/AppleHost/main.swift` — 20-line AppKit snippet creating an `NSWindow` with `GamaHostView` | **Not an executable target**; top-level code creates the window and falls off the end — no `NSApplication` run loop, so even compiled it would exit immediately |
| Toolchain discipline | `Toolchains.toml` + `scripts/ci-install-swift-snapshot.sh` / `ci-install-swift-sdk.sh`: every download SHA256-pinned; every script accepts env overrides and fails closed | The convention packaging scripts must follow |

### Gaps a shipping developer hits, per platform

**macOS `.app`** — needs: bundle skeleton
(`Contents/{MacOS,Resources}/`, `Info.plist`, `PkgInfo`), a *GUI* executable
(see V1 — `gama-demo` is a TUI binary; double-clicked from Finder it has no
tty, so `Terminal.enterRawMode()` fails; a TUI product ships as a plain binary
or a Homebrew formula, not a `.app`), an `.icns` icon, codesign, and the
distribution chain. Automation boundary:

- **Automatable with zero credentials:** bundle assembly, `Info.plist`
  generation, `iconutil`-based icon build, **ad-hoc** signing
  (`codesign -s -`), `codesign --verify`, launch smoke. Ad-hoc apps run on the
  building machine; Gatekeeper blocks them on other machines.
- **Automatable only with credentials present:** Developer ID signing (needs
  the cert in a keychain), notarization (`xcrun notarytool submit` needs an
  App Store Connect API key or app-specific password, plus network), stapling.
- **Never automatable:** enrolling in the developer program, creating the
  Developer ID certificate, and the one-time
  `notarytool store-credentials` bootstrap. Scripts must *gate* on
  `GAMA_CODESIGN_IDENTITY` / `GAMA_NOTARY_PROFILE` and fail closed with an
  explicit "credential-gated, not broken" message — same claim-honesty rule as
  `docs/Capabilities.md`.

**Windows `.exe`** — a Swift-built exe is not self-contained: it needs the
Swift runtime DLLs beside it (or an installer that adds the runtime). Staging =
copy exe + DLL closure into one directory; the CI job already computes the
runtime `bin` path. Icon/version resources and MSI/MSIX are later concerns.

**wasm site** — already 95% real: `index.html + gama.js + gama-web-demo.wasm`
in one directory is deployable to any static host. Missing only the assembly
step and pointing the existing smoke at the assembled output.

**Embedded static lib + header** — assembly of `libGamaEmbed.a` +
`GamaEmbed.h` (+ per-triple variants) into a versioned SDK directory. On the
static Linux SDK the result is fully self-contained; on Darwin/Android hosts
the consumer must also link/carry the Swift runtime — the SDK README has to
state that boundary honestly.

**Linux binary** — the static-musl SDK can produce a single-file, fully static
`gama-demo` (TUI works on POSIX). Today `check-linux.sh` stops at
`--target GamaCore`; shipping means `--product gama-demo` plus a
`file`/ldd-style static-ness assertion.

**Android** — `assembleRelease` + keystore signing (credential-gated, same
pattern as notarization). Everything else exists.

## 2. Tooling shape — recommendation: scripts now, `gama` CLI later; not plugins

**Recommended: (c) `scripts/bundle-*.sh` + `scripts/release-*.sh`,** following
the existing `check-*.sh` discipline (env-var overrides, pinned toolchains,
fail closed, `/private/tmp` scratch), with **(a) a `gama` CLI as the declared
end state** once Gama apps exist *outside* this repository. Explicitly **not
(b) SwiftPM command plugins**.

Why not (b), concretely:

- The plugin sandbox denies network, which kills `notarytool` outright, and
  identity-based `codesign` needs keychain access the sandbox profile does not
  grant. The one packaging step that most needs automation help is exactly the
  one a plugin cannot perform. (Reasoning from documented SwiftPM sandbox
  behavior; not measured in this repo.)
- Plugin write access is the package directory — here, the iCloud tree, i.e.
  the one place a codesigned bundle must never be staged (measured failure in
  `CLAUDE.md`).
- The verification story shells out to node + headless Chrome
  (`scripts/browser-runtime-smoke.mjs`) and Gradle; orchestrating those from a
  sandboxed plugin adds friction and zero capability.
- The repo already has a 12-script gate discipline plus CI parity; a plugin
  would be a *second* invocation convention for the same logic.

Why (c) beats (a) *today*: a `gama` CLI target in this package is only
reachable as `swift run gama …` from *this* checkout — SwiftPM does not let a
dependent package run a dependency's executable product directly, so external
Gama apps gain nothing until a distribution channel for the CLI itself exists
(brew/mint/artifact). Meanwhile every consumer of packaging in the next months
is this repo's CI and Donald. Build the substance as scripts with stable
env-var contracts; when the CLI lands (Proposed, sub-project 4.x), it becomes
a thin veneer that parses the manifest and invokes the same staged logic —
the scripts are the spec of record, not a throwaway.

Proposed script set (V1 in bold):

- **`scripts/bundle-web.sh`** — assemble + verify the wasm site directory.
- **`scripts/bundle-macos.sh`** — assemble + ad-hoc-sign + verify the `.app`.
- `scripts/release-macos.sh` — Developer ID sign + notarize + staple;
  hard-requires `GAMA_CODESIGN_IDENTITY` and `GAMA_NOTARY_PROFILE`.
- `scripts/bundle-embed.sh` — versioned embed SDK dir (lib + header + README).
- `scripts/bundle-linux.sh`, `scripts/bundle-windows.ps1`,
  Android `assembleRelease` wiring — later slices.

## 3. App metadata — a manifest that stays out of the build system

**Placement:** a repo-root `Distribution/` directory (outside `Sources/`, so
SwiftPM never sees stray resources), one file per shippable product plus
shared templates:

```
Distribution/
  gama-web-demo.toml
  gama-apple-demo.toml
  macos/Info.plist.in        # placeholder template: @BUNDLE_ID@, @NAME@, …
  macos/icon.png             # 1024×1024 source; iconutil builds the .icns
  macos/entitlements.plist   # optional; passed to codesign when present
```

**Format:** a deliberately flat TOML *subset* — only `[section]` headers and
`key = "value"` lines, one per line, no tables-in-tables, no arrays:

```toml
[app]
id = "com.donaldfilimon.gama.demo"        # matches the com.donaldfilimon.gama.*
name = "Gama Demo"                        # family already used in check-docs.sh
version = "0.1.0"

[macos]
minimum_system = "14.0"
category = "public.app-category.developer-tools"

[web]
title = "Gama"
```

**Parsing:** a ~15-line `scripts/lib/manifest.sh` helper (`manifest_get
<file> <section> <key>`) built on `sed`/`grep`, mirroring how the repo already
treats `Toolchains.toml` as data. The subset rule is enforced by the helper
failing closed on any line it does not recognize — that is the guard against
the manifest quietly growing into a second build system: **it may carry
identity and branding only; anything that changes what gets compiled belongs
in `Package.swift`.**

**Foundation boundary:** trivially satisfied — the manifest is read by bash
(later by the `gama` CLI tool, which is host tooling and may use Foundation
freely; it never links into `GamaCore`). No framework target ever parses it.
`scripts/check-boundaries.sh` keeps enforcing the import wall unchanged.

Rejected alternatives: JSON (needs `jq`/plutil on every platform incl. the
Windows runner), Info.plist-as-source-of-truth (macOS-only, and the wasm/
Android/Windows artifacts need the same identity fields), per-target files
inside `Sources/<Target>/` (SwiftPM unhandled-resource warnings).

## 4. V1 slice (Proposed)

**V1 = (a) wasm site bundle from `gama-web-demo` + (b) macOS `.app` of a new
tiny `gama-apple-demo` executable — nothing else.**

Justification from what exists:

1. **The wasm site is pure assembly.** Every part is already proven —
   `check-wasm.sh` builds the binary, `gama.js:151` loads it by relative path,
   and `browser-runtime-smoke.mjs` verifies exactly the served-directory
   layout. Zero new Swift; highest confidence, first artifact.
2. **The `.app` cannot wrap `gama-demo` as the task sketch suggested**: it is
   a TUI executable (`Sources/GamaDemo/main.swift`), and a Finder-launched
   `.app` has no tty — raw-mode entry fails and the user sees nothing. The
   honest `.app` payload is the AppleUI backend, and
   `Examples/AppleHost/main.swift` is 90% of it but exits immediately (no
   `NSApplication.shared.run()`). So V1 includes **one small new executable
   target `GamaAppleDemo`** (product `gama-apple-demo`, macOS-only via
   `#if canImport(AppKit)`, mirroring the `GamaWebDemo` pattern): app delegate,
   window + `GamaHostView`, run loop, and a `--smoke` flag (below). This is
   deliberately *not* the sub-project-3 app shell — it is a demo payload the
   bundler needs; the shell later replaces its innards, not the bundle format.
3. **Everything else is deferred** because it has no consumer yet: the embed
   SDK zip is cheap but nobody links it outside `Examples/CEmbed` (the check
   already proves the pieces); Linux/Windows staging and Android release
   signing wait until someone ships there. Deferring is recorded, not
   forgotten — see § Later slices.

V1 outputs land under `GAMA_DIST_ROOT` (default `/private/tmp/gama-dist`,
`RUNNER_TEMP` in CI) — **never inside the iCloud tree** (codesign detritus
failure, `CLAUDE.md`). CI uploads them with `actions/upload-artifact`, which
replaces today's evidence-only `wasm-artifacts` content with the actual
deployable directory.

## 5. Verification per artifact

Same rule as everywhere in this repo: an artifact claim requires a passing
gate; missing prerequisites fail closed.

| Artifact | Gate (V1 in bold) |
| --- | --- |
| **wasm site dir** | **`node scripts/browser-runtime-smoke.mjs "$DIST/web/gama-web-demo.wasm" "$DIST/web"` — the existing smoke, pointed at the assembled bundle instead of scratch paths; asserts the full `OK;frames=…;keys=…;pointers=…;resizes=…;rendered=true;accessible=true` marker in headless Chrome.** (Note: the marker's `aria-label` check is coupled to the demo's "Gama Web" text — generalizing it is part of the future `gama` CLI, not V1.) |
| **macOS `.app`** | **`plutil -lint` the generated Info.plist; `codesign --verify --deep --strict`; launch smoke: run `Contents/MacOS/gama-apple-demo --smoke`, which boots `NSApplication`, hosts the view offscreen, renders one frame (assert non-empty DrawList), and exits 0. Runs in the existing macOS CI job. A Finder double-click check stays a documented manual step — `spctl -a` is expected to reject the ad-hoc build and the script must say so rather than fake green.** |
| notarized `.app` | `release-macos.sh` only: `notarytool submit --wait` exit status + `stapler validate`. Credential-gated; absence of credentials is reported as blocked, never skipped-silently. |
| embed SDK dir | Re-point `check-c-abi.sh`'s compile/link/run at the packaged `include/` + `lib/` instead of scratch output — the consumer proves the SDK layout, not just the pieces. |
| Linux binary | Build `--product gama-demo` with the static SDK; assert static linkage (`readelf -d` shows no `NEEDED`) and run a non-interactive path (e.g. `--emit-mlir`) in the Linux job. |
| Windows dir | Stage exe + runtime DLLs; run `gama-windows-console-smoke` **from the staged directory** on the Windows runner — the run proves DLL closure. |
| Android APK | Existing emulator gate (`check-android-emulator.sh`) already asserts an input-driven frame change; release adds `apksigner verify`. |

## Later slices (all Proposed, in likely order)

1. `bundle-embed.sh` + SDK README stating the runtime-linkage boundary.
2. Linux static `gama-demo` binary (extend `check-linux.sh` product set).
3. Windows staged directory + upload.
4. `release-macos.sh` (Developer ID + notarization) once credentials exist.
5. Android `assembleRelease` + keystore gating.
6. The `gama` CLI executable target: manifest-driven veneer over the scripts;
   distribution channel for the CLI itself decided then.
7. iOS/tvOS/visionOS `.ipa` story — deliberately unscoped here (device
   signing, provisioning profiles, and App Store tooling are a spec of their
   own).

## Open questions for Donald

1. **Bundle identity + credentials.** Confirm `com.donaldfilimon.gama.*` as
   the id family (it already appears in `scripts/check-docs.sh`), and whether
   a Developer ID certificate / notary profile exists or is planned — that
   decides whether `release-macos.sh` is worth building now or stays a stub
   behind the ad-hoc boundary.
2. **Does `gama-apple-demo` belong to sub-project 4 or 3?** V1 needs *some*
   GUI payload; this spec proposes a minimal new executable target now and
   letting the app-shell spec later own its internals. Alternative: block the
   `.app` slice on sub-project 3 and ship V1 as wasm-site-only.
3. **Manifest now or with the CLI?** V1 could hardcode the demo's metadata in
   the two bundle scripts and defer `Distribution/*.toml` until a second app
   exists. This spec proposes introducing the manifest now (it is the contract
   the CLI later consumes), but it is the piece most at risk of speculative
   generality.
