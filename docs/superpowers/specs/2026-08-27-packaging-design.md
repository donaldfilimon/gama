# Gama umbrella — packaging & distribution (sub-project 4)

Date: 2026-08-27. Status: **approved**. Delivery evidence is maintained in
`docs/Capabilities.md`; approval alone is not an implementation claim.

This specification finalizes the 2026-08-26 draft
(`drafts/2026-08-26-packaging-draft.md`, kept for the inventory, tooling
rationale, and rejected alternatives — all carried forward unchanged except
where amended below). Donald resolved the draft's open questions on
2026-08-27:

1. **Bundle identity is `com.donaldfilimon.gama.*`** (confirmed), and **a
   Developer ID certificate / notary profile exists** — `release-macos.sh`
   is real V1 scope, not a stub (decision: "Developer ID exists").
2. **The `.app` and wasm-site slices proceed in parallel** (decision: "both
   in parallel"). The `.app` payload is the delivered scene-first shell's
   `gama-apple-demo` executable (`Sources/GamaAppleDemo`,
   `GamaAppleShell`-based multi-window demo) — the draft's proposed new
   minimal executable is unnecessary; it already exists and is the honest
   GUI payload. Sub-project 3 owns its internals; this sub-project owns the
   bundle formats and scripts.
3. **The `Distribution/` manifest is introduced now** (draft
   recommendation adopted): identity and branding only; anything that
   changes what gets compiled stays in `Package.swift`. The flat-TOML
   subset and fail-closed `scripts/lib/manifest.sh` parser are as drafted.

## Amendments to the draft

### A1. V1 slice (supersedes draft §4)

V1 = three artifacts, two delivery tracks that may land as separate PRs:

- **Track W (wasm site)**: `scripts/bundle-web.sh` assembles
  `index.html + gama.js + gama-web-demo.wasm` into
  `$GAMA_DIST_ROOT/web/` and verifies it with the existing
  `browser-runtime-smoke.mjs` pointed at the assembled directory. CI's
  wasm job uploads the deployable directory.
- **Track M (macOS `.app`)**: `scripts/bundle-macos.sh` stages
  `Gama Demo.app` (payload `gama-apple-demo`) **outside the iCloud tree**
  (`$GAMA_DIST_ROOT`, default `/private/tmp/gama-dist`), generates
  `Info.plist` from `Distribution/macos/Info.plist.in` +
  `Distribution/gama-apple-demo.toml`, builds the `.icns` with `iconutil`
  when `Distribution/macos/icon.png` exists (skips with a notice
  otherwise), ad-hoc signs, `codesign --verify --deep --strict`, and runs
  the `--smoke` launch gate. `release-macos.sh` performs Developer ID
  signing + `notarytool submit --wait` + stapling, hard-gated on
  `GAMA_CODESIGN_IDENTITY` and `GAMA_NOTARY_PROFILE` — absent credentials
  report **blocked (credential-gated), never silently skipped**, and CI
  (which has no credentials) runs only the ad-hoc path.

`gama-apple-demo` gains a `--smoke` flag: boot `NSApplication`, host the
primary scene offscreen, render one frame (assert non-empty DrawList),
exit 0. This is the bundle's launch gate and runs in the macOS CI job.

### A2. Verification (unchanged from draft §5 for V1 rows)

wasm site → browser smoke against the assembled directory; `.app` →
`plutil -lint`, deep-strict codesign verify, `--smoke` exit 0; notarized
`.app` → `notarytool` exit status + `stapler validate` (local, credentialed
runs only — recorded in `docs/Capabilities.md` as locally-proven evidence,
never claimed from CI).

### A3. Later slices (draft order retained)

embed SDK dir, Linux static binary, Windows staged dir, Android
`assembleRelease` + keystore, the `gama` CLI veneer, iOS-family `.ipa`
(own spec). Notarization moved OUT of this list into V1 by decision 1.

## Constraints restated (normative)

- No second build system; the manifest carries identity/branding only.
- Codesigned bundles are never staged inside the iCloud tree (measured
  FileProvider xattr failure — `CLAUDE.md`).
- Every artifact claim requires its passing gate; missing prerequisites
  fail closed with an explicit "credential-gated, not broken" message.
- Scripts follow the `check-*.sh` discipline: env overrides, pinned
  toolchains, `/private/tmp` scratch, fail closed.
