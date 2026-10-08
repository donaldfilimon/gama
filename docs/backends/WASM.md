# Freestanding WASM pull API

The import-free wasm32-freestanding module exports memory and gama_wasm_v1_init, shutdown, key, pointer, resize, needs_frame, frame, frame_ptr, frame_len. No WASI, DOM or JavaScript callback imports exist. The old browser gama_web families are retired.

init(i32,i32) returns status; successful init replaces the context and failed init preserves it. frame returns 1 published, 0 clean; errors are -1 uninitialized, -2 invalid key, -3 frame too large and -4 OOM. frame_ptr/frame_len return a borrowed GAMA v1 view valid until next frame/init/shutdown. shutdown returns void; pointer and resize share retained coordinate and dimension rules.

`zig build check-wasm` links and structurally inspects production and bounded-test variants. `zig build check-wasm-runtime` executes the pull ABI in existing Node, including bounded-memory failure. Structural parsing does not validate every opcode; engine execution is a separate layer. No browser application or accessibility host is provided.
