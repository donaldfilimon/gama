# ``GamaWASM``

Run a Gama application in the browser as a wasi reactor driven from
JavaScript.

## Overview

GamaWASM is the browser backend. The module is a wasi reactor: top-level
code runs once at `_initialize` and calls
`GamaWeb.install(app:columns:rows:)`; JavaScript then drives the installed
host through the versioned `gama_web_v1_*` exports (`frame`, `key`,
`pointer`, `resize`). Frames render as an HTML grid of styled spans handed
to the page through the module's `"gama"` imports (`setHTML`, `setTitle`,
`requestFrame`), and the mount point asserts `role="application"` plus an
`aria-label`, the accessibility contract the browser smoke checks.

The exports are deliberately `nonisolated` and fail closed: a call before
installation or with an invalid input code returns a negative status
instead of trapping across the ABI. Installing a second app replaces the
previous host wholesale. The experimental `Extern` feature is scoped to
this target only.

The entire hosting API (`GamaWeb` and the exports) is compiled only for
`arch(wasm32)`; on every other platform the target builds inert stubs, so
this reference contains no symbol pages outside a wasm32 build and the
API is documented here and in `docs/backends/WASM.md` (export/import
tables, the `WebHost/` static site, and the `scripts/check-wasm.sh` build
instructions).

Capability status for this backend lives in `docs/Capabilities.md` and is
currently Unverified against merge commit `98c150d`; later reactor and
smoke-driver changes have not been re-proven by a required job. This
catalog does not restate hosted proof.
