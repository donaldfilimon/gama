# Toolchain

`.zig-version` and `ZigToolchain.zon` pin 0.17.0-dev.2338+b46a7f3a2. `tools/policy.zig` independently pins the version, revision and official macOS archive URL/SHA256. `build.zig.zon` permits zero dependencies. Do not silently upgrade the development snapshot.

The compiler executable/archive receipt is under `docs/migration/zig/evidence`; [Capabilities](Capabilities.md) qualifies what was actually verified. The gate compares the executing compiler version and policy fields. Existing installations are reused; scripts never replace a compiler. Use `GAMA_ZIG` with `scripts/check.sh` or invoke the chosen binary directly for build commands.
