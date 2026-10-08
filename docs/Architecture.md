# Architecture

The flow is application → BuildContext → Node → integer layout → CellBuffer painting → DrawList or presenter → adapter. Input returns through Host. Retained adapters present exactly one primary scene; auxiliary descriptions do not create native windows.

Host prepares a candidate containing state, layout and registrations. Downstream preparation must complete before delivery. Successful delivery publishes the host and raster planes; errors retain the old internal publication and dirty retry. External transport may have accepted a partial write, which the framework cannot retract.

Portable modules use explicit allocators and one executor. The facade selects native executor checks only on hosted targets. TUI and hosted services depend on std APIs. Freestanding artifacts instantiate no hosted services; required unavailable services fail closed. C and WASM adapters share portable semantics and the GAMA v1 drawing wire.
