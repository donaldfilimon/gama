# Browser backend (GamaWASM)

Status: Locally runtime proven with the pinned WASM SDK (Node event/frame
smoke plus headless-Chrome DOM/key/pointer/resize/rAF/accessibility smoke)
and hosted proven on the WebAssembly job. The HTML serializer additionally
compiles and unit-tests on every host platform (it lives outside
`#if arch(wasm32)`).

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
installed, and `-2` from `gama_web_v2_key` for an invalid key code. Changing
the result type of a published symbol is an ABI break even when JavaScript
callers ignore the result, so new result contracts require a new symbol
family.

JS imports the module provides to Swift (module `"gama"`): `setHTML`,
`setTitle`, `requestFrame`.

## WebHost

`WebHost/index.html` + `WebHost/gama.js` form a dependency-free static
site: serve the directory next to the built `.wasm` (relative `fetch`) and
open it. It is a UI demonstration host, not a general WASI runtime — it
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
