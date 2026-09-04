# Toolchain

Gama is pinned to one **complete** Swift 6.5-dev main snapshot. Incomplete
dates (macOS pkg without matching WASM/Android/static-linux SDKs) are
rejected. Windows is a deliberate exception.

## Identity (re-verified 2026-09-02)

| Item | Value |
| --- | --- |
| Swiftly selector | `main-snapshot-2026-08-21` (`.swift-version`) |
| Compiler | Apple Swift 6.5-dev, Swift `95c5142e84b82c1`, LLVM `64c3046d94ae7cc` |
| Toolchain id | `org.swift.65202608211a` |
| Manifest | `swift-tools-version: 6.4` (Xcode 27 integrated SwiftPM / xcodebuild) |
| Xcode default | Xcode 27.0 (27A5252f), Swift 6.4 (`swiftlang-6.4.0.33.1`, Clang `2100.3.33.1`) for iOS/tvOS/visionOS gates only |
| Windows | `6.4.x-DEVELOPMENT-SNAPSHOT-2026-08-14-a` (no Windows main snapshot since 2026-05-20-a) |

URLs, SHA-256s, SDK ids, and revisions live in `Toolchains.toml`.
`scripts/check-toolchain-pins.sh` fails if CI, check-script defaults, or
`.swift-version` drift from that file. `check-boundaries.sh` runs it.

## How agents and humans invoke Swift

```bash
unset TOOLCHAINS
swiftly run swift build
swiftly run swift run gama-demo
swiftly run swift test --scratch-path /private/tmp/gama-framework-swiftpm
swiftly run swift --version
```

`swiftly run` reads `.swift-version`. It is the preferred everyday form.
Check scripts keep the explicit `xcrun --toolchain org.swift.65202608211a`
pin so a wrong local default cannot silently run 6.4.

This checkout is iCloud FileProvider-managed. `swift test` in-place fails
codesign; always use the check scripts or `--scratch-path` under `/private/tmp`.
Never `git gc`, `git prune`, `git fsck`, or `git repack` here.

## Language mode

All Swift targets use `.swiftLanguageMode(.v6)`, `ExistentialAny`,
`MemberImportVisibility`, and `InternalImportsByDefault` (`strictCore` in
`Package.swift`). `Extern` is experimental and scoped to `GamaWASM` only.

`InternalImportsByDefault` is **enabled** (ADR
[0012](adr/0012-strict-memory-safety-and-explicit-imports.md)). Every import
that feeds a public declaration is `public import`; `GamaAppleShell` uses
`package import GamaAppleUI`. The annotation landed one commit before the
flip, so the flip is a semantic no-op and independently revertable. The
compiler diagnoses both a missing `public import` (an error naming the
declaration) and an unused one (`#UnusedImportAccess`), so the set is checked
in both directions: annotate exactly what the compiler asks for. Platform
imports that appear only in private storage and internal helpers (`Darwin`,
`Glibc`, `Musl`, `Android`, `WinSDK` in `GamaTUI`) stay plain `import`.
`scripts/check-boundaries.sh` matches access-scoped spellings, so `public
import Foundation` is still rejected in the portable targets.

Strict memory safety (SE-0458) is **enabled with `-Werror
StrictMemorySafety`** on every shipped library and macro target through
`strictLibrary` (`Package.swift`); executables and `GamaTests` stay on
`strictCore` by measured decision (ADR 0012 records the counts). In a library
target, a memory-unsafe operation must be spelled `unsafe` at its site, and a
type with unsafe storage but a safe API is marked `@safe` with its internal
uses wrapped. Enabling only the warnings would change nothing — the ordinary
build never promotes the group — which is why the error promotion is part of
the setting, not a CI flag.

Do not enable `NonisolatedNonsendingByDefault`. That is a separate question and
the modernization master plan says to assess it, not to assume it.

## Bump policy

Bump the pin only when a newer **complete** artifact set exists (macOS pkg,
Ubuntu 24.04 tarball, static-linux / wasm / android SDKs) and local + CI
move together. See `Toolchains.toml` comments and `scripts/check-toolchain-pins.sh`.
