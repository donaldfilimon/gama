# Browser backend (GamaWASM)

Status: Unverified. Capability status lives in
[`Capabilities.md`](../Capabilities.md); this guide does not restate
hosted or local proof. The HTML serializer additionally compiles and
unit-tests on every host platform (it lives outside `#if arch(wasm32)`).

## Hosting model

The module is a wasi reactor: top-level code runs once at `_initialize` and
calls `GamaWeb.install(app:)`; JavaScript then drives it through versioned
exports. Frames render as an HTML grid of styled spans (one `<pre
class="gama-row">` per row) delivered to JS, which assigns it to the mount
point and asserts `role="application"` plus an `aria-label` (the
accessibility contract the browser smoke checks).

## Isolation and lifecycle

Before installation, every v2 event/frame export fails closed with `-1`; the
v1 compatibility exports remain no-ops because their published signatures
cannot return status. `GamaWeb.install(app:)` transfers the app region into a
single host. A successful reinstall replaces that host wholesale, releasing
its subscriptions, frame state, and component state; a construction failure
leaves the previously installed host in place.

The gate also builds `Tests/Fixtures/WASMFailedInstall`, whose first and only
install throws `SceneConfigurationError.noPrimaryScene`. After WASI startup,
the Node smoke requires the fixture's exact-error marker and checks both
export tiers: v1 returns void with no callbacks; v2 frame, key, pointer, and
resize return `-1` with no callbacks. Unknown key codes and invalid Unicode
scalars also return `-1` in this state, while the installed demo separately
requires `-2` for those inputs. This fixture does not exercise reinstall or
recovery after failure.

`gama-web-demo` is a showcase panel — a count/step/notify readout, a command
row, a text field and a toggle, a progress bar, and a feature list — declared
with four direct `ReactiveSlot`s, keeping the host macro plugin out of the
wasm32 dependency graph. Its `render(in:)` binds slots zero through three, in
declaration order, at the component's identity before rendering the body under
`context.child(0)`, matching the `@Component`/`@Reactive` expansion and
retaining the host's per-surface store (ADR 0011). The slot indices are half of
each storage key, so reordering those four lines is a state-identity change,
not a cosmetic one. `WebDemoStateTests` exercises the same demo on the host,
checking inline rebuilds, independent inline or hoisted `WindowGroup`
surfaces, and the two layout constraints below.

The demo's layout carries two constraints that the smokes depend on and that
are easy to break without noticing:

- **`count <n>` must be a single `Text`.** The Node smoke matches
  `/\bcount ([0-9]+)\b/` against the raw HTML, where every styled run is its
  own `<span>`. A label and a value rendered as two `Text`s put a tag between
  them and the match disappears. The browser smoke does not catch this, because
  it reads `textContent`, which concatenates spans — so only the Node smoke, and
  now a host test that serializes through `HTMLSerializer`, fail.
- **The layout must still paint the count at 40x8.** That is the grid the Node
  smoke resizes to, and it reads painted output, not the laid-out tree. Two
  border rows leave six content rows; the panel keeps the count on the third
  and uses horizontal padding only so the vertical cells go to content.
`scripts/check-wasm.sh` proves the direct-slot runtime path twice: the Node smoke
sends Enter through `gama_web_v1_key` and requires an exact `0` to `1`
transition, while the browser smoke dispatches real DOM events and requires
`state=0->0->1`. The middle zero proves that Tab, pointer, and resize coverage
did not activate the counter; the final one is attributable to Enter.
These smokes prove WASM state behavior; macro expansion is covered separately
by the host-side macro tests.

The current WASI reactor is single-threaded. That is the complete
justification for the one `nonisolated(unsafe)` declaration: the private
installed-host slot in `WASMHost.swift`. `scripts/check-wasm.sh` scans Swift
declarations while ignoring comments and string prose, mutation-tests the
scanner, and fails unless there is exactly one such declaration and it is that
exact slot. Threaded WebAssembly, multiple simultaneous hosts, or another
unsafe global requires a new isolation and versioned ABI design; the existing
exception does not authorize it.

## Export/import contract

Swift exports (called from `WebHost/gama.js`):

| Export | Meaning |
| --- | --- |
| `gama_web_v1_frame()` | Produce a frame if the host is dirty |
| `gama_web_v1_key(code, char, shift, ctrl)` | Key event (host-side keycode mapping documented in the source) |
| `gama_web_v1_pointer(col, row, pressed)` | Pointer press/release at a grid cell |
| `gama_web_v1_resize(cols, rows)` | Grid resize (clamped to ≥1) |

The v1 exports retain their original void-returning WebAssembly signatures.
Status-reporting hosts may call the argument-compatible `gama_web_v2_*`
family instead: it returns `0` when accepted, `-1` when no app host is
installed, and `-2` from `gama_web_v2_key` for an invalid key code. The
installed-host check precedes argument validation, so an invalid key code with
no host installed returns `-1`, not `-2`; `-2` reports only that an otherwise
deliverable event carried a code the backend cannot translate. Changing
the result type of a published symbol is an ABI break even when JavaScript
callers ignore the result, so new result contracts require a new symbol
family. `GamaWebDemo` and the failed-install fixture use the same eight exports as
WASI-conditioned target-local linker settings; build commands do not apply
reactor exports to host tools.

JS imports the module provides to Swift (module `"gama"`): `setHTML`,
`setTitle`, `requestFrame`.

## WebHost

`WebHost/index.html` + `WebHost/gama.js` form a dependency-free static
site: serve the directory next to the built `.wasm` (relative `fetch`) and
open it. The page is a small shell around the `#gama` surface: a status line
that reports the live grid size once the first frame lands, a boot overlay
while the module compiles, and an error overlay that names the failing stage
(fetch, instantiate, initialize, install, or first frame, and after boot a
lost host or an event-handling fault) instead of leaving a blank surface. The
failure is also written to `data-gama-failure` on the surface itself, so a
driver can read it without depending on the page around it. It follows `prefers-color-scheme` and `prefers-reduced-motion`.

**Exactly two host files ship.** `scripts/bundle-web.sh` copies `index.html`
and `gama.js` and nothing else, so every style stays inline in the page. A
third file would be missing from the deployed site while the local smoke,
which serves `WebHost/` directly, kept passing. The pointer mapping and the
usable grid both read the surface's padding back with `getComputedStyle`
rather than assuming it, so a CSS change cannot silently shift clicks by a
cell.

**The host uses only the `v2` export tier.** The demo installs with `try?`,
so a failed install is silent inside the module: `v1` calls then return
nothing and do nothing, and the page would sit on its boot overlay
indefinitely. `v2` answers `-1` from the very first call, which the host turns
into a failure named `install`, carrying whatever the module printed. A `-1`
after a successful boot is reported as a lost host. A `-2` from a key means
Gama did not accept it (F14 and above, or a lone surrogate), so the host leaves
that key to the browser rather than swallowing it and warns once in the
console; it is not a page-level error. Input that arrives before boot has
finished is dropped rather than forwarded, because a module with no exports
yet would otherwise throw, and that throw would be misread as a lost host. The
`v1` tier stays exported, unchanged, for other hosts.

`scripts/check-wasm.sh` requires each of the four `v2` calls in `gama.js`
individually and fails if any `v1` call remains. `scripts/browser-runtime-smoke.mjs`
adds two browser-level checks beyond the `0->0->1` state sequence: it fires a
key and a pointer press at the moment `WebAssembly.instantiate` is called and
requires them to be dropped without disabling later input, and with
`--failed-install` it serves the failed-install fixture through the real page
and requires the surface to report stage `install`, the failed status, and the
missing-host diagnosis. A `v1` host fails that second check by construction,
since it has no status to read. It is a UI demonstration host, not a general WASI runtime — it
implements only the reactor's process-metadata/clock/random/output imports
and returns explicit WASI errors otherwise (no filesystem). Build via
`scripts/check-wasm.sh` (requires the pinned WASM SDK from
`Toolchains.toml`). The gate first proves the single-private-unsafe-slot source
policy, then preserves the existing compile, symbol, Node-runtime, and browser
smokes. `scripts/bundle-web.sh` assembles those host files with
`gama-web-demo.wasm` and runs the browser-runtime smoke against the assembled
directory. `.github/workflows/pages.yml` repeats that exact pinned build and
publishes the verified directory from `main`; Pages deployment and a live
browser load are separate hosted evidence from the acceptance artifact upload.
