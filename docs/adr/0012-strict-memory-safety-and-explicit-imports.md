# 0012 — Strict memory safety on shipped targets; explicit import access levels everywhere

Status: Accepted.

Closes the toolchain-hardening item that `tasks/todo.md` carried since the
Swift 6.5-dev modernization: "Decide and implement `StrictMemorySafety` and
`InternalImportsByDefault` together with warning promotion." The decision is
scoped by measurement, not by preference; the numbers are recorded here so the
scope can be re-argued when they change. Delivery evidence is maintained in
`../Capabilities.md`; the language-mode rules live in `../Toolchain.md`.

## Context

Two upcoming features were open. Both are compile-time only and have no
runtime or ABI representation.

**`InternalImportsByDefault` (SE-0409).** An unannotated `import` becomes
`internal`, so a module whose types appear in a public declaration must be
`public import`ed. `../Toolchain.md` required that it be enabled *last*, after
every import carried an explicit access level, so the flip is a semantic
no-op and independently revertable. The feature has no migration mode on the
pinned snapshot (`InternalImportsByDefault:migrate` is rejected), so the
annotation set was found by iterating the compiler: enable, read the
"was not imported publicly" errors, annotate, rebuild, then remove any
`public import` the compiler reports as unused (`#UnusedImportAccess`). The
set is therefore minimal in both directions. Two facts the iteration settled:
a plain `@_exported import GamaCore` still re-exports through a downstream
`public import` (both umbrella targets compiled unchanged), and the feature
must be enabled through the manifest rather than `-Xswiftc`, because the
swift-syntax dependency does not compile under it.

**Strict memory safety (SE-0458).** `-strict-memory-safety` diagnoses every
use of an unsafe type or operation that is not spelled `unsafe`. The todo
item's caveat was measured to be exact: `-Werror StrictMemorySafety` without
`-strict-memory-safety` emits nothing, and the ordinary build never promotes
the group, so "enabling the warnings" alone changes no outcome. Measured on
2026-09-04 against the tree at `ae13761` (the per-surface state branch), the
whole package including tests builds with **142 warnings and 0 errors** under
the flag, all in the `StrictMemorySafety` group:

| Target | Diagnostics | What they are |
| --- | --- | --- |
| GamaTests | 83 | C interop in the terminal-rescue and PTY suites, the C ABI entry points, and `#expect` expansions over unsafe values |
| GamaEmbed | 23 | `Unmanaged` context handles, the `@_cdecl` entry points' raw pointers, frame-storage allocation and copy |
| GamaTUI | 11 | termios, `ioctl`, `poll`, `read`, `write`, and the C signal-arm call |
| GamaAppleDemo | 9 | Mach task and malloc-zone statistics, bitmap pixel access |
| GamaCore | 7 | `ScenePayload`'s typed erasure and the state store's `unsafeDowncast` |
| GamaBench | 4 | Mach task statistics, `fputc` to `stderr` |
| GamaAppleUI | 2 | `NSAccessibility.post` and `NSView.window` (`unowned(unsafe)`) |
| GamaAndroidDemo, GamaDemo, GamaLeakCheck | 1 each | `makeContext`'s raw pointer, `getenv`, `Unmanaged.passRetained` |
| every other target | 0 | — |

Branches the local toolchain cannot compile carry further sites found by
reading: the Windows console path of `GamaTUI` (`HANDLE` storage, the
console-mode and `ReadConsoleInputW` calls), the Glibc/Musl/Android `write`
mirrors, the wasm32 branch of `GamaWASM` (`@_extern` imports and
`withUnsafeBufferPointer`), and the Linux `fputs` path of `gama-leak-check`.

The SwiftPM spellings were verified under `swift-tools-version: 6.4` with
both the pinned snapshot's SwiftPM and Xcode's: `.strictMemorySafety()`,
`.treatWarning("StrictMemorySafety", as: .error)`, and
`.enableUpcomingFeature("InternalImportsByDefault")` all parse and map to
`-strict-memory-safety`, `-Werror StrictMemorySafety`, and
`-enable-upcoming-feature InternalImportsByDefault`. Enabling both features on
`GamaCore` produces exactly the union of their individual diagnostics.

## Decision

1. **`InternalImportsByDefault` is enabled on every Swift target** through
   `strictCore` in `Package.swift`. Every import that feeds a public
   declaration is `public import`; `GamaAppleShell` uses `package import
   GamaAppleUI` because only package-level declarations name its types. The
   annotation commit precedes the enabling commit, so the flip is a
   semantic no-op as `../Toolchain.md` required. Platform-conditional imports
   are annotated inside their `#if` blocks (`AppKit` and `UIKit` in
   `GamaAppleUI`, `GamaCore` in the wasm32 branch of `GamaWASM`); the POSIX
   and Windows system imports in `GamaTUI` stay internal because their types
   appear only in private storage and internal helpers.

2. **Strict memory safety, with the `StrictMemorySafety` group promoted to an
   error, is enabled on every shipped library and macro target** — `Gama`,
   `GamaCore`, `GamaPlugin`, `GamaPlatformServices`, `GamaMacros`,
   `GamaMacrosImpl`, `GamaDraw`, `GamaTUI`, `GamaWASM`, `GamaAppleUI`,
   `GamaAppleShell`, `GamaEmbed`, `GamaMLIR`, and the `GamaAndroidDemo`
   library product — through `strictLibrary` in `Package.swift`. Every
   memory-unsafe operation in those targets is spelled `unsafe` at its site,
   and a type whose storage is unsafe but whose API is safe (`ScenePayload`,
   `EmbedContext`, the Windows `Terminal`) is marked `@safe` with each internal
   use wrapped. Promotion to an error is the point: a new unsafe operation
   cannot land as a warning that the ordinary build ignores.

3. **Executables and the test target stay on `strictCore`** — `gama-demo`,
   `gama-web-demo`, `gama-apple-demo`, `gama-windows-console-smoke`,
   `gama-leak-check`, `gama-bench`, and `GamaTests`. They are consumers and
   harnesses of the shipped surface, not the surface; their 99 measured sites
   are C interop for measurement and PTY drivers, a deliberate leak, and
   `#expect` expansions over the C ABI. Adopting the flag there is a separate,
   measured decision, not a silent extension of this one.

4. **`NonisolatedNonsendingByDefault` is not enabled.** That is a different
   question, and the modernization master plan says to assess it, not to
   assume it.

## What this does not claim

- `unsafe` is a spelling, not a proof. Each annotated site is as safe as it
  was; the gain is that the compiler now enumerates every such site, and a new
  one fails the build until a human writes the word.
- Branches the local toolchain cannot compile were annotated by reading,
  mirroring the spelling the compiler accepted for the equivalent Darwin site.
  Their proof is the hosted job that compiles them; until that job is green on
  the merged commit they are Implemented, not proven.

## Verification

Locally proven on 2026-09-04 with the pinned snapshot, on the tree that
carries both flips and every annotation:

- `check-apple.sh`: debug build, 266 tests in 49 suites, release build, with
  no diagnostics of any kind.
- `check-embedded.sh`: the annotated `GamaCore` still compiles whole-module for
  armv7em and links relocatably at the same 631,960 bytes as before the
  annotations — `unsafe` is a spelling, not code.
- `check-c-abi.sh`: the C consumer compiles against the annotated
  `GamaEmbed`, links, and runs.
- `check-linux.sh`: the static Linux SDK builds `GamaCore` and `GamaTUI`, which
  compiles the Glibc branch of `Terminal.swift` and its by-reading `write`
  annotation.
- `check-wasm.sh`: the pinned WASM SDK builds `GamaWASM` and `gama-web-demo`
  (the wasm32 branch, including its `@_extern` imports and the `public import
  GamaCore` it needs), and the Node and headless-Chrome smokes pass.
- `check-apple-platforms.sh`: the iOS, tvOS, and visionOS simulators compile
  the UIKit branch of `GamaAppleUI`.
- `check-boundaries.sh`, `check-concurrency-negative.sh`, `check-docs.sh`,
  and `check-doc-coverage.sh` pass unchanged; the boundary gate's import
  regexes match the new access-scoped spellings.

Not compiled locally: the Windows console branch of `GamaTUI` (no Windows
toolchain here) and the Android SDK cross-compile of `GamaAndroidDemo` (no
NDK here). Both were annotated by reading, mirroring the spellings the
compiler accepted on Darwin; the hosted Windows and Android jobs are their
proof. Reading was not enough: the first hosted Windows run found three
C-union member reads in the console branch that need `unsafe` and a
`gama-bench` call to `exit` that had resolved only through another module's
import, both fixed in the follow-up commit on the same pull request. Until
those jobs are green on the merged commit those branches are Implemented,
not proven.

## Consequences

- Source change in every library target: `public import` / `package import`
  spellings and `unsafe` expressions at the measured sites. No public
  signature, symbol name, `@_cdecl` or `@_extern` string, or ABI changed.
- `scripts/check-boundaries.sh` already recognizes access-scoped import
  spellings (`public import Foundation` is still rejected in `GamaCore`), so
  the portable-import rule is unchanged by the new spellings.
- A future backend or platform branch inherits both features through
  `strictLibrary`; a new executable or test target inherits only `strictCore`
  and must opt in deliberately.
- Reverting either feature is one line in `Package.swift`; the annotations are
  harmless without it.
