# Packaging and distribution

Status: V1 (wasm site + macOS `.app`) per
[superpowers/specs/2026-08-27-packaging-design.md](superpowers/specs/2026-08-27-packaging-design.md).
Evidence vocabulary is defined in
[Capabilities.md](Capabilities.md#status-vocabulary); every artifact claim
below names its gate, and a claim is only as strong as its last passing run.

## Artifacts

| Artifact | Script | Output |
| --- | --- | --- |
| Deployable wasm site | `scripts/bundle-web.sh` | `$GAMA_DIST_ROOT/web/` with `index.html`, `gama.js`, `gama-web-demo.wasm`; deployable to any static host |
| macOS app bundle (ad-hoc) | `scripts/bundle-macos.sh` | `$GAMA_DIST_ROOT/<name>.app` staging `gama-apple-demo`; runs on the building machine only |
| macOS app bundle (Developer ID, notarized) | `scripts/release-macos.sh` | The same `.app` re-signed with a Developer ID identity, notarized, stapled, and re-archived as `$GAMA_DIST_ROOT/<name>.zip` |

`GAMA_DIST_ROOT` defaults to `/private/tmp/gama-dist`. Bundles are never
staged inside the repo tree: the canonical checkout is FileProvider-managed
and codesign rejects bundles staged there (measured failure, `CLAUDE.md`);
`bundle-macos.sh` canonicalizes relative paths, `..`, and symlinks before it
refuses a dist root inside the repo.

## Identity manifests

`Distribution/` holds one flat-TOML manifest per shippable product
(`gama-web-demo.toml`, `gama-apple-demo.toml`, id family
`com.donaldfilimon.gama.*`) plus `macos/Info.plist.in`, the template the
bundler fills. The manifests carry identity and branding only; anything that
changes what gets compiled belongs in `Package.swift`. The reader,
`scripts/lib/manifest.sh` (`manifest_get <file> <section> <key>`), recognizes
only blank lines, comments, `[section]` headers, and `key = "value"` pairs
whose complete section and key identifiers match `[A-Za-z0-9_]+`. It fails
closed on anything else, which is the guard against the manifest growing into
a second build system. The macOS bundler sets plist values through `plutil`,
so branding characters are encoded as plist data rather than interpreted as
text-replacement syntax. The web bundler HTML-escapes `[web].title`, applies it
to the assembled page, and makes the browser smoke assert the resulting title.

An `.icns` is built with `sips` + `iconutil` when `Distribution/macos/icon.png`
exists. No icon source is committed today, so the bundle ships icon-less and
the icon path is implemented but unproven.

## Verification

| Claim | Gate | Current state |
| --- | --- | --- |
| wasm site directory works in a browser | `node scripts/browser-runtime-smoke.mjs "$DIST/web/gama-web-demo.wasm" "$DIST/web" "$WEB_TITLE"` run by `bundle-web.sh` against the assembled directory (headless Chrome: title branding, DOM, key, pointer, resize, rAF, accessibility, frames) | Locally and hosted proven; the acceptance WebAssembly job independently rebuilds, smokes, and uploads the same directory |
| GitHub Pages serves the interactive demo | `.github/workflows/pages.yml` rebuilds through `bundle-web.sh`, uploads only the verified `web/` directory, and deploys it to `https://donaldfilimon.github.io/gama/` from `main` | Hosted proven 2026-09-02 at `8157a68`: the Pages workflow built, browser-smoked, uploaded, and deployed; a separate live fetch returned the titled HTML and the 9,183,871-byte `application/wasm` payload |
| `.app` is well formed | `plutil -lint` on the generated `Info.plist` | Locally proven |
| `.app` signature is intact | `codesign --verify --deep --strict` after ad-hoc signing | Locally proven (ad-hoc identity) |
| `.app` launches and renders | `Contents/MacOS/gama-apple-demo --smoke`: boots `NSApplication` offscreen, hosts the primary scene, requires a non-empty `DrawList`, exits 0 | Locally and hosted proven by the macOS bundle step |
| CI download preserves `.app` modes | `ditto` archive before `actions/upload-artifact`; extract, require the payload executable bit, and re-run deep-strict signature verification | Locally and hosted proven by the macOS archive + upload steps |
| Notarized `.app` | `notarytool submit --wait` exit status + `stapler validate` in `release-macos.sh` | Credential-gated: implemented but unproven (see below) |
| Finder double-click on another machine | Manual; `spctl -a` is expected to reject the ad-hoc build | Not claimed for ad-hoc output |

## Credential boundary (honesty rules)

`bundle-macos.sh` needs zero credentials and ad-hoc signs (`codesign -s -`).
Ad-hoc apps run on the building machine; Gatekeeper blocks them elsewhere.
That boundary is stated by the script itself rather than papered over.

`release-macos.sh` hard-requires `GAMA_CODESIGN_IDENTITY` (a Developer ID
Application identity in the keychain) and `GAMA_NOTARY_PROFILE` (a
`notarytool store-credentials` profile). When either is missing it prints an
explicit credential-gated, not broken message and exits nonzero; it never
silently skips and never falls back to ad-hoc. CI has no signing credentials
and runs only the ad-hoc path. The credentialed path (Developer ID signing
with the hardened runtime, `ditto` submission zip, `notarytool submit --wait`,
`stapler staple`, `stapler validate`, and a final post-staple archive rebuild)
is implemented; its first passing
credentialed run must be recorded in `Capabilities.md` as locally proven
evidence before the notarized artifact is described as real. Enrolling in the
developer program, creating the certificate, and the one-time
`store-credentials` bootstrap are manual and out of scope for automation.

## Environment knobs

All scripts follow the `check-*.sh` discipline: pinned toolchains, env
overrides, `/private/tmp` scratch, fail closed on missing prerequisites.

- `GAMA_DIST_ROOT`: output root (default `/private/tmp/gama-dist`).
- `GAMA_TOOLCHAIN_ID`, `GAMA_SWIFT_64`, `GAMA_WASM_SDK_ID`,
  `GAMA_SCRATCH_ROOT`: same meanings as in the check scripts.
- `GAMA_MACOS_BUNDLE_SCRATCH_PATH`: SwiftPM scratch for the release build
  (default `/private/tmp/gama-macos-bundle-swiftpm`).
- `GAMA_CODESIGN_IDENTITY`, `GAMA_NOTARY_PROFILE`: release credentials
  (release script only).

## Later slices

Embed SDK directory, Linux static binary, Windows staged directory, Android
`assembleRelease` + keystore, the `gama` CLI veneer, and the iOS-family
`.ipa` story are deferred with rationale in the approved spec and draft.
