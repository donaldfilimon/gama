# Verification and evidence

[Capabilities](Capabilities.md) owns current qualification. `docs/migration/zig/evidence/source-receipt.json` records a fixed source scope, SHA256/lengths, tool versions, commands and log hashes. `tools/check_evidence.py` rejects missing, changed or unexpected source files and missing/changed logs. The receipt deliberately excludes its own evidence directory and plan checkbox bookkeeping to avoid self-hash cycles; docs/reference validation still checks the current accepted design.

Hash consistency is not proof of execution by itself. The logs accompany actual runs, with native, cross-link, artifact inspection and engine layers distinguished. Historical Swift records are explicitly archived and cannot qualify current Zig code. The full check reruns executable assertions; it does not rely on ignored private preservation archives.
