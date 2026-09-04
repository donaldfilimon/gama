# Verification and evidence boundaries

Status: Current gate map. Commands describe what the repository checks; a
claim is current only for the exact revision and environment whose output was
observed. Capability status remains authoritative in
[Capabilities.md](Capabilities.md).

Gama supports several platforms with different proof routes. The repository
therefore separates source presence, compilation, automated runtime behavior,
hosted execution, packaging, deployment, and manual acceptance.

## The evidence ladder

| Layer | Establishes | Does not establish |
| --- | --- | --- |
| Source/interface inspection | A declaration, import, pin, or policy exists | Compilation or behavior |
| Compiler probe | One spelling/type shape under one compiler/SDK/target | Link, ABI, runtime, another target |
| Local build/test | The named local gate passed at one revision/environment | Hosted OS, deployment, manual UI |
| Local runtime smoke | The exact local executable interaction occurred | Packaging, another machine, CI |
| Hosted CI | The exact pushed SHA passed the named job | Later local state or manual acceptance |
| Artifact verification | A staged archive/bundle contains expected files and metadata | Signing credentials, install, launch |
| Deployment check | A provider published and a live endpoint responded | Native products or future deploys |
| Manual acceptance | A named human/device/accessibility interaction occurred | Other devices, OS versions, automation |

Always report the revision, toolchain, target, and command beside a result.

## Pinned local setup

```bash
unset TOOLCHAINS
swiftly run swift --version
```

The expected compiler is the repository's complete Swift 6.5-dev snapshot.
SwiftPM scratch paths must remain outside the FileProvider checkout:

```bash
swiftly run swift test --scratch-path /private/tmp/gama-tests
```

Never treat Xcode's default Swift 6.4 toolchain as a replacement for the
pinned snapshot. It is used only by the documented xcodebuild platform gates.

## Complete acceptance matrix

`./scripts/check.sh` runs thirteen fail-closed gates in this order:

| Gate | Main proof |
| --- | --- |
| `check-apple.sh` | Pinned debug build, full Swift Testing suite, release build |
| `check-apple-platforms.sh` | iOS/tvOS/visionOS compilation |
| `check-boundaries.sh` | import/ownership/global-state/tools-version/pin contracts |
| `check-concurrency-negative.sh` | confinement failures remain compiler-enforced |
| `check-c-abi.sh` | C header compile, static link, and executable round trip |
| `check-embedded.sh` | whole-module Embedded compile and relocatable link |
| `check-linux.sh` | static Linux SDK cross-build |
| `check-wasm.sh` | WASM build, unsafe-slot policy, Node and browser smokes |
| `check-android.sh` | Android cross-build, JNI and runtime-library packaging |
| `check-android-emulator.sh` | required API 36 input-to-decoded-frame change |
| `check-mlir.sh` | emitted dialect parses under `mlir-opt` |
| `check-docs.sh` | relative links, synchronized run-gama mirrors and cleanup, all DocC catalogs with warnings as errors |
| `check-doc-coverage.sh` | every public symbol has documentation or a justified exception |

The driver intentionally fails when a required SDK, NDK, emulator, browser,
MLIR tool, or other prerequisite is absent. A skipped or unavailable gate is
not green evidence.

## Focused gates

Use the smallest gate while iterating, then widen in proportion to the change:

- Core/layout/state: focused Swift test, boundaries, concurrency negatives,
  Apple gate.
- Mac host or shell: exact Apple test type, Apple gate, platform compile if a
  shared Apple source changed.
- Draw-list/ABI: codec tests, C ABI, WASM, Android, and any affected backend.
- Documentation: link checker, DocC, public-doc coverage.
- Toolchain/pin: boundary gate plus every platform whose artifact changed.

Swift Testing filters match source type/test identifiers, not `@Suite`
display names. Confirm the `Test run with N tests` line; an unmatched filter
can warn and exit zero.

## Hosted CI map

The workflow in `.github/workflows/ci.yml` is the hosted authority:

- **macOS:** pinned Apple build/tests, Apple-family compile, boundaries,
  concurrency, documentation, MLIR, and staged macOS bundle.
- **Linux:** native tests, C ABI, AddressSanitizer, harness-free
  LeakSanitizer with negative control, ThreadSanitizer, static SDK.
- **WebAssembly:** pinned compiler/SDK, runtime/browser checks, deployable site.
- **Android:** pinned compiler/SDK/NDK, packaging, required API 36 emulator.
- **Embedded:** exact snapshot compile/link.
- **Windows:** native console route on the documented Swift 6.4.x exception.

A green PR-head run proves the tested head. A merge commit is a different SHA;
when the workflow runs again, report its result separately.

## Documentation evidence

`check-docs.sh` performs four distinct checks:

1. The standard-library-only link scanner rejects broken relative Markdown
   links in root guides, `docs/`, `Examples/`, and DocC articles.
2. The run-gama checker rejects drift or wrong self-paths between the tracked
   `.agents` and `.claude` entry points, requires executable drivers, and uses
   negative controls to prove stale-frame removal and owned-session cleanup.
3. SwiftPM emits public symbol graphs under the pinned toolchain.
4. Every discovered DocC catalog builds with warnings as errors.

`check-doc-coverage.sh` separately verifies public symbol comments. Passing
one does not imply the other.

## Packaging and deployment

The macOS staging gate verifies a structurally valid `.app` and transport
archive. Ad-hoc or unsigned CI artifacts do not prove Developer ID signing or
notarization. Credentialed release proof requires valid credentials and the
exact signing/notarization workflow.

The Pages workflow assembles and browser-smokes the WASM site before
deployment. A green deployment job should be followed by a live HTTP/browser
check when reporting provider state; an old successful run does not prove the
current endpoint.

## Performance evidence

Performance results require an optimized build, named workload, warmup, run
count, machine/OS/toolchain, digests, and raw artifacts. Time Profiler stack
percentages are inclusive and may nest. RSS and live-heap growth are not
allocation counts.

If Instruments cannot attach, report allocation counts as unmeasured. Do not
substitute another metric. The full policy and current baselines are in
[Performance.md](Performance.md).

## Manual and credential-gated evidence

The automated matrix does not currently establish:

- Real VoiceOver or UIKit screen-reader interaction.
- Dock reopen and visible macOS window-focus/close/Command-Q behavior.
- Developer ID signing and notarization with credentials.
- Physical Embedded hardware behavior.
- General physical-device acceptance on Apple platforms.
- Application-specific SwiftData migrations or Foundation Models behavior.

Record those only after the exact interaction is exercised.

## Closeout checklist

Before calling a delivery complete:

1. Record `git status --short --branch`, the exact SHA, branches, and worktrees.
2. Run the focused gate and verify the expected test count/output.
3. Run the affected broad gates with external scratch paths.
4. Run documentation and boundary gates for public or architectural changes.
5. Push through the protected PR workflow; do not force-push `main`.
6. Wait for every required exact-head check.
7. Merge, fetch, and verify local `main == origin/main`.
8. Wait for post-merge workflows when they are part of delivery evidence.
9. Delete a branch only after proving it has no open PR and no commits outside
   `main`.
10. Report local, hosted, deployed, artifact, and manual evidence separately.
