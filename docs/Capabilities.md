# Current capabilities and evidence

This ledger qualifies the Zig rewrite; historical Swift claims are archived. Current means implemented, native execution means actually run on this macOS host, cross-link means a foreign artifact was built, structural inspection is bounded parsing, and engine execution is separate. Hosted CI and embedded hardware remain unverified.

The maintained evidence receipt is `docs/migration/zig/evidence/source-receipt.json`. Its source scope and log hashes bind observed commands to deliberately uncommitted implementation bytes. It never requires ignored preservation archives. Final task-scoped and whole-change independent reviews are separate from implementation self-review.

| Surface | Qualification and limit |
| --- | --- |
| Portable components, state/identity, layout, drawing, Unicode, wire, plugins and services | Native debug/safe/fast suites with fixed goldens, allocation failure, teardown and handle-revocation assertions; exact final counts are in the maintained gate logs. Unicode 17 has eight intentional corrections documented in the migration guide. |
| Terminal | Native PTY process assertions plus owned tmux counter, focus and grapheme-form interaction. Exact custom Darwin action metadata is required; arbitrary unknown custom dispositions cannot be transparently captured. External exit/SIGKILL and descriptor loss after true hangup remain outside the unconditional guarantee. Supporting XNU source is not the exact beta-kernel source. |
| Plain | Actual adaptive stdout/explicit-plain execution and chronology/completion tests. Windows plain/headless is cross-linked, not executed on Windows. |
| Embedding | Actual linked native C consumer in debug/safe/fast with borrowed status and OOM checks. |
| WASM | Linked import-free modules, bounded structural/tamper inspection and Node pull-ABI execution. No browser host or hosted deployment. Structural parser is not a full opcode validator. |
| MLIR | Nine emitted scenarios per mode parsed by independent mlir-opt with unregistered dialects allowed. This proves generic syntax, not registered semantics or lowering. |
| Cortex-M4 | Three linked caller-entry ELFs with bounded structural/ARM-attribute/tamper inspection. Native tests execute the shared caller-arena workload. No board boot/vector/stack-demand/hardware proof. |
| Hosted matrix | Linked macOS aarch64, Linux x86_64/aarch64 TUI and Windows x86_64 headless demo executables. Foreign OS execution remains unverified. |
| Repository acceptance | Exact pin, empty dependencies, final source policy, formatting, corpus integrity, API/current-doc negatives, reference/skill parity, source-hash evidence and examples. CI configuration retains trusted same-repo guards and existing runner labels; no hosted run is claimed. |

Toolchain archive provenance: the official aarch64 macOS archive was observed at 53,982,588 bytes with SHA256 6823e45e4f4b9b7eab5230baa06d9e59ea9e1f19e88d3eb29946d02111bfedd4. Archived and installed compiler bytes matched SHA256 797ac1f94b20b8d32319a1602009ca142fd81638809084eab2c38fd969d8f696 and version 0.17.0-dev.2338+b46a7f3a2. No compiler replacement occurred; see the bounded public toolchain receipt.

Benchmark conditions and actual phase measurements are recorded in `docs/migration/zig/evidence/benchmark.log`, using the fixed portable workload described in [Performance](Performance.md). The new content digest checks repeatability only. No Swift-relative speed or memory improvement is claimed.

Preservation: Package.resolved remains archival and byte-exact; GEMINI stays empty. Exact legacy tracked paths were retired only after private archive/member verification. Authored archives, the lockfile and immutable corpus have hash verification. Ignored Studio/Qt cache files have aggregate file-count/byte equality observations, without individual content hashes. Operator/runner checks establish protected-name presence, and worktree registration records compare equal; these are not private-content comparisons. Retired-parent traversal may have pruned empty cache directories: exact affected paths are unknown because no earlier directory inventory exists. Private-note metadata changed concurrently, so preservation of those contents is unknown. No lost authored bytes are established by these limits. Private archive contents are not publication evidence.

Native suite accounting: 245 tests per optimization mode, 735 total across debug/safe/fast. Separate process proof comprises 12 terminal scenarios per mode (36 executions), three linked native C consumers, six Node WASM executions (production/bounded in each mode), 27 independent MLIR parses and three Cortex-M4 linked artifact inspections. Compile-fail checks reject 29 fixtures. API coverage inventories 1,356 declarations/members, with 127 documentation/reference controls. These layers are separate; a test count does not imply a foreign host ran.

Final benchmark run on macOS arm64, Zig fast, defaults 5 runs / 2,000 frames / 200 warmup: median/p95 nanoseconds were paint 57,000/58,958; DrawList.from 50,125/53,625; ANSI diff 3,792/4,125; resize 195,000/225,042. Sample counts were 10,000 per fixed phase and 500 resize. Each run's added FNV-1a content digest was f69f0fa2b40349e5. These are local measurements, not comparative speed claims; the maintained environment/command receipt supplies versions.
