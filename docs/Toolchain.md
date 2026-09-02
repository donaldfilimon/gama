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

All library and test targets use `.swiftLanguageMode(.v6)` and
`ExistentialAny`. `Extern` is experimental and scoped to `GamaWASM` only.
`MemberImportVisibility` is enabled on `strictCore` (`Package.swift:13`,
commit `e038ad6`); the earlier text here said it was not, and was stale.

`InternalImportsByDefault` is **not enabled; its adoption remains open** in the
current toolchain-hardening item in `tasks/todo.md`. If adopted, it must be
enabled last, after every target's imports carry an explicit access level, so
the enabling change is a semantic no-op and independently revertable. Until
that flip lands, an unannotated `import` is still the default — annotate rather
than assume. The current decision reverses this file's previous blanket
prohibition: the condition that prohibition waited on, that the boundary
scripts recognize every import spelling, is met by
`scripts/check-boundaries.sh:11-15` and `:59-67`, which match plain, indented,
attributed, and access-scoped forms.

Do not enable `NonisolatedNonsendingByDefault`. That is a separate question and
the modernization master plan says to assess it, not to assume it.

## Bump policy

Bump the pin only when a newer **complete** artifact set exists (macOS pkg,
Ubuntu 24.04 tarball, static-linux / wasm / android SDKs) and local + CI
move together. See `Toolchains.toml` comments and `scripts/check-toolchain-pins.sh`.
