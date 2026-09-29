# SwiftUI embedding plan

Design: [SwiftUI embedding design](../specs/2026-09-29-swiftui-embedding-design.md).
Roadmap track 4, first half. Executed 2026-09-29 on the `feat/swiftui-embedding`
branch; this plan is a record of the order of work, not a capability claim.

## Task 1: failing test

- Write `Tests/gamaTests/SwiftUIEmbeddingTests.swift` against the API the
  design names: `GamaView(app:)`, `GamaView(_:)`, `makeHostView()`,
  `GamaView.dismantleHostView(_:)`, plus an `NSHostingView` integration case.
- Build the tests. Expected failure: the `GamaSwiftUI` module does not exist.

## Task 2: target

- Add `Sources/GamaSwiftUI/GamaView.swift` under
  `#if canImport(SwiftUI) && (canImport(AppKit) || canImport(UIKit))`.
- Register the `GamaSwiftUI` library product and target (`strictLibrary`,
  depending on `GamaCore` and `GamaAppleUI`) in `Package.swift`, and add it to
  the `GamaTests` dependencies.
- Qualify `App`, `View`, `Scene`, `Text`, and `Window` wherever SwiftUI and
  GamaCore are both imported.
- Run the suite: all five tests pass.

## Task 3: prove the teardown test can fail

- Replace the teardown call with a no-op, rerun, and confirm the dismantle
  test fails. Restore it.

## Task 4: gates and lists

- Add `Sources/GamaSwiftUI` to `platform_services_ban_dirs` in
  `scripts/check-boundaries.sh` and to the independent `TARGETS` tuple in
  `scripts/test-boundary-paths.py`.
- Add the `GamaSwiftUI` scheme to `scripts/check-apple-platforms.sh`. That
  script hardcodes shared derived-data paths, so it was edited but not run on
  this branch, and no hand compile of the scheme for iOS, tvOS, or visionOS
  was run either. The UIKit branch is uncompiled until integration runs the
  gate.
- No change to `scripts/package-graph.py`: its checks are derived.

## Task 5: documentation

- `Sources/GamaSwiftUI/GamaSwiftUI.docc/GamaSwiftUI.md` (the docs gate builds
  every catalog and requires the root article).
- `docs/backends/SwiftUI.md`, the index in `docs/README.md`, the suite row in
  `docs/Testing.md`, and the SwiftUI section of `docs/AppleIntegration.md`.
- No `docs/Capabilities.md` row: a new row needs an anchor commit, and an
  anchor on a branch that integration may rebase would point at a commit that
  no longer exists. The row is added after merge, at the layer the merged
  gates support.

## Task 6: review follow-up

- Strengthen the independence test: two hosts from one value, a `@Reactive`
  counter activated in one, the other still at zero.
- Make the `NSHostingView` case observe teardown through SwiftUI: replace the
  root, then check a model change no longer reaches the draw list.
- Document that a `GamaView` is created once and held, that a replacement
  value is ignored, and when an app `Signal` is shared.
- Restore the boundary gate's closing verdict line, dropped by accident.

## Task 7: gates

`check-apple.sh`, `check-boundaries.sh`, `check-docs.sh`,
`check-doc-coverage.sh`, `check-package-graph.sh`,
`check-evidence-freshness.sh`, each with this branch's own scratch paths.
Commit only when all pass.
