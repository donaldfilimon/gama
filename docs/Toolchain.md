# Toolchain

`.zig-version` and `ZigToolchain.zon` pin 0.18.0-dev.120+9fe22a29b. `tools/policy.zig` independently pins the version, revision and official macOS archive URL/SHA256. `build.zig.zon` permits zero dependencies. Do not silently upgrade the development snapshot.

The compiler executable/archive receipt is under `docs/migration/zig/evidence`; [Capabilities](Capabilities.md) qualifies what was actually verified. The gate compares the executing compiler version and policy fields. Existing installations are reused; scripts never replace a compiler. Use `GAMA_ZIG` with `scripts/check.sh` or invoke the chosen binary directly for build commands.

Donald authorized the master upgrade on 2026-10-08. The original compiler receipt/logs remain under `docs/migration/zig/evidence/history/2026-10-03`.

Evidence refresh uses `zig build qualify -j2 --summary all` to run framework, policy, documentation, examples and artifact qualification while collecting fresh logs. It excludes only receipt consistency to avoid requiring the new receipt before collecting its observations. After recording the source/log receipt, run full `scripts/check.sh`; the `check` target requires both qualification and receipt validation.
