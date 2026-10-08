# C embedding

`include/GamaEmbed.h` is the versioned C contract. `zig build embed` installs the native static library and header. `zig build check-abi` compiles and links `tests/embed_consumer.c` against actual native exports in all three modes.

The gama_embed_v1 family preserves baseline signatures/statuses. Context creation returns null on OOM; frame reports length -4 on OOM. Returned frame storage is borrowed until the next frame or destruction. Dirty/clean status and bounded dimension admission use shared host/wire semantics. Do not retain borrowed pointers past their stated lifetime. The C consumer is test-only; production implementation is Zig.
