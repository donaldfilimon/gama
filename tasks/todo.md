# Todo

This ledger contains current work only. Completed delivery history remains in
Git, merged pull requests, dated ADRs, and `docs/superpowers/`. Capability
status is authoritative in `docs/Capabilities.md`.

## Open implementation work

- [ ] **Hosted acceptance is red on the tip of `main`.** The "Gama acceptance"
      run for the pushed merge commit `bc2fe4d` failed: five jobs green, the
      WebAssembly job failed inside `scripts/check-wasm.sh`. The Swift/WASI
      build, the libm symbol scans, and `wasm-runtime-smoke.mjs`
      (`state=0->1`) all passed; the failure is
      `scripts/browser-runtime-smoke.mjs:78`, `Chrome DevTools endpoint did
      not start`, after the 15 s (150 x 100 ms) wait for `DevToolsActivePort`.

      Evidence that this is infrastructure, not a Gama regression: the pull
      request head `bb43f6b` and the merge commit `bc2fe4d` have **identical
      trees**, and the pull-request run of the same tree passed 90 minutes
      earlier. That reasoning explains the red; it does not substitute for a
      green run on the pushed commit.

      Two separable follow-ups, neither yet accepted:

      - Re-run the WebAssembly job for `bc2fe4d` to restore hosted proof for
        that commit.
      - The gate reported the failure with an **empty** stderr string, so the
        cause is unknown rather than merely infrastructural.
        `browser-runtime-smoke.mjs` spawns Chrome with no `error` listener and
        never reports the child's exit code, so a spawn failure, an immediate
        crash, and a slow start are indistinguishable in the log. Making that
        failure legible is a diagnostics change; it must not relax the wait or
        let a missing browser pass, which would weaken a fail-closed gate.

## Manual and credential-gated acceptance

- [ ] Exercise the AppKit accessibility adapter with VoiceOver and the UIKit
      path with a screen reader. Automated tests prove the derived text and
      bridge, not real assistive-technology interaction.
- [ ] Run the Developer ID signing and notarization path with valid credentials
      before describing the notarized macOS artifact as proven.
- [ ] Run the supplemental macOS shell smoke for Dock reopen, multi-window
      focus, close behavior, and Command-Q. Automated offscreen tests remain
      the gate; this item records the separate human-facing layer.

## Deferred product scope

These are not committed implementation work. Each needs a new accepted design
before execution:

- Tier 2 dynamically loaded plugins and Tier 3 out-of-process plugins.
- A versioned network capability and stronger filesystem/symlink confinement.
- UIKit-native scene ownership, Windows GUI hosting, and physical Embedded
  hardware acceptance.
- Additional distribution formats: Embed SDK, Linux/Windows staged products,
  Android release/keystore packaging, CLI veneer, and iOS-family archives.
