const std = @import("std");
const policy = @import("tools/policy.zig");
const pin = @import("ZigToolchain.zon");
const package = @import("build.zig.zon");

comptime {
    policy.requireVersion(@import("builtin").zig_version_string);
    policy.requireVersion(pin.version);
    policy.requireVersion(package.minimum_zig_version);
    policy.requireEmptyDependencies(package.dependencies);
    if (!std.mem.eql(u8, @embedFile(".zig-version"), policy.version ++ "\n") or
        !std.mem.eql(u8, pin.revision, policy.revision) or
        !std.mem.eql(u8, pin.aarch64_macos_url, policy.archive_url) or
        !std.mem.eql(u8, pin.aarch64_macos_sha256, policy.archive_sha256)) @compileError("Gama toolchain pin mismatch");
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    // Public consumers may use hosted std on macOS, where std requires libc.
    const gama = b.addModule("gama", .{ .root_source_file = b.path("src/root.zig"), .target = target, .optimize = optimize, .link_libc = target.result.os.tag == .macos });

    const test_step = b.step("test", "Execute native framework and policy tests in debug, safe, fast");
    const default_runner_path = std.Build.LazyPath.zig_lib.path(b, "compiler/test_runner.zig");
    const default_runner = b.createModule(.{ .root_source_file = default_runner_path, .target = b.graph.host });
    for ([_]std.builtin.OptimizeMode{ .debug, .safe, .fast }) |mode| {
        for ([_][]const u8{ "src/root.zig", "tools/policy.zig", "tools/verify.zig", "tools/corpus.zig", "tools/wasm_verify.zig", "tools/elf_verify.zig", "tests/mlir_tests.zig", "examples/embedded_app.zig", "examples/bench.zig", "tests/abi_tests.zig", "tests/terminal_tests.zig", "tests/plugin_tests.zig", "tests/service_tests.zig", "tests/drawing_tests.zig", "tests/native_region_regression_tests.zig", "tests/text_tests.zig", "tests/authoring_tests.zig", "tests/state_tests.zig", "tests/layout_tests.zig", "tests/pump_tests.zig", "tests/followup_regression_tests.zig", "tools/unicode/generate.zig" }) |path| {
            const module = b.createModule(.{ .root_source_file = b.path(path), .target = b.graph.host, .optimize = mode, .link_libc = b.graph.host.result.os.tag == .macos });
            module.addImport("default_runner", default_runner);
            module.addImport("gama", b.createModule(.{ .root_source_file = b.path("src/root.zig"), .target = b.graph.host, .optimize = mode, .link_libc = b.graph.host.result.os.tag == .macos }));
            const tests = b.addTest(.{
                .name = b.fmt("{s}-{s}", .{ std.fs.path.stem(path), @tagName(mode) }),
                .root_module = module,
                .test_runner = .{ .path = b.path("tools/test_runner.zig"), .mode = .simple },
                .use_llvm = true,
            });
            const run = if (std.mem.eql(u8, path, "tests/terminal_tests.zig")) blk: {
                const wrapped = b.addSystemCommand(&.{ "python3", "tests/with_pty.py" });
                wrapped.addFileArg(tests.getEmittedBin());
                wrapped.setCwd(b.path("."));
                break :blk wrapped;
            } else b.addRunArtifact(tests);
            run.expectExitCode(0);
            run.expectStdErrMatch("All ");
            _ = run.captureStdErr(.{ .basename = b.fmt("{s}-{s}.tests.log", .{ std.fs.path.stem(path), @tagName(mode) }) });
            run.has_side_effects = true;
            run.stdio_limit = .limited(1024 * 1024);
            test_step.dependOn(&run.step);
        }
    }

    const embedded_check = b.step("check-embedded", "Link Cortex-M4 core and drawing pump with caller storage; inspect exact ELF");
    const arm_target = b.resolveTargetQuery(.{ .cpu_arch = .thumb, .os_tag = .freestanding, .abi = .eabi, .cpu_model = .{ .explicit = &std.Target.arm.cpu.cortex_m4 } });
    for ([_]std.builtin.OptimizeMode{ .debug, .safe, .fast }) |mode| {
        const arm_module = b.createModule(.{ .root_source_file = b.path("examples/embedded.zig"), .target = arm_target, .optimize = mode, .link_libc = false, .link_libcpp = false, .single_threaded = true, .unwind_tables = .none });
        arm_module.addImport("gama", b.createModule(.{ .root_source_file = b.path("src/root.zig"), .target = arm_target, .optimize = mode, .link_libc = false, .link_libcpp = false, .single_threaded = true, .unwind_tables = .none }));
        const elf = b.addExecutable(.{ .name = b.fmt("gama-cortex-m4-{s}", .{@tagName(mode)}), .root_module = arm_module });
        elf.bundle_compiler_rt = true;
        elf.link_gc_sections = true;
        elf.stack_size = 16 * 1024;
        elf.entry = .{ .symbol_name = "gama_embedded_entry" };
        elf.root_module.export_symbol_names = &.{"gama_embedded_entry"};
        const install = b.addInstallFile(elf.getEmittedBin(), b.fmt("embedded/gama-cortex-m4-{s}.elf", .{@tagName(mode)}));
        embedded_check.dependOn(&install.step);
        const inspector = b.addExecutable(.{ .name = b.fmt("elf-verify-{s}", .{@tagName(mode)}), .root_module = b.createModule(.{ .root_source_file = b.path("tools/elf_verify.zig"), .target = b.graph.host, .optimize = mode }) });
        const inspection = b.addRunArtifact(inspector);
        inspection.addFileArg(elf.getEmittedBin());
        inspection.expectExitCode(0);
        inspection.expectStdErrMatch("ELF structural verification passed:");
        inspection.has_side_effects = true;
        _ = inspection.captureStdErr(.{ .basename = b.fmt("elf-{s}.tests.log", .{@tagName(mode)}) });
        embedded_check.dependOn(&inspection.step);
    }

    const mlir_check = b.step("check-mlir", "Parse real emitted MLIR with independent mlir-opt (generic syntax only)");
    const parser = b.option([]const u8, "mlir-opt", "Existing mlir-opt path; no download or installation") orelse "mlir-opt";
    for ([_]std.builtin.OptimizeMode{ .debug, .safe, .fast }) |mode| {
        const emitter_module = b.createModule(.{ .root_source_file = b.path("tests/mlir_tests.zig"), .target = b.graph.host, .optimize = mode, .link_libc = b.graph.host.result.os.tag == .macos });
        emitter_module.addImport("gama", b.createModule(.{ .root_source_file = b.path("src/root.zig"), .target = b.graph.host, .optimize = mode, .link_libc = b.graph.host.result.os.tag == .macos }));
        const emitter = b.addExecutable(.{ .name = b.fmt("mlir-emit-{s}", .{@tagName(mode)}), .root_module = emitter_module });
        for ([_][]const u8{ "escaping", "structural", "layout-16x8", "layout-9x5", "plugins-before", "plugins-after", "plugins-reinstall", "controls", "vocabulary" }) |name| {
            const emit = b.addRunArtifact(emitter);
            emit.addArg(name);
            const output = emit.addOutputFileArg(b.fmt("{s}-{s}.mlir", .{ name, @tagName(mode) }));
            emit.expectExitCode(0);
            const parse = b.addSystemCommand(&.{ parser, "--allow-unregistered-dialect" });
            parse.addFileArg(output);
            parse.expectExitCode(0);
            parse.has_side_effects = true;
            _ = parse.captureStdOut(.{ .basename = b.fmt("{s}-{s}.parsed.mlir", .{ name, @tagName(mode) }) });
            _ = parse.captureStdErr(.{ .basename = b.fmt("{s}-{s}.parser.log", .{ name, @tagName(mode) }) });
            mlir_check.dependOn(&parse.step);
        }
    }

    const embed = b.addLibrary(.{ .name = "gama", .linkage = .static, .root_module = b.createModule(.{ .root_source_file = b.path("src/c_embed.zig"), .target = target, .optimize = optimize, .link_libc = target.result.os.tag == .macos }) });
    const install_embed = b.addInstallArtifact(embed, .{});
    const install_header = b.addInstallHeaderFile(b.path("include/GamaEmbed.h"), "GamaEmbed.h");
    const embed_step = b.step("embed", "Install native embedding library and C declaration header");
    embed_step.dependOn(&install_embed.step);
    embed_step.dependOn(&install_header.step);

    const abi_check = b.step("check-abi", "Execute linked native C consumer in all modes");
    const wasm_check = b.step("check-wasm", "Link import-free WASM and inspect exact artifact and tamper rejections");
    const wasm_runtime = b.step("check-wasm-runtime", "Execute WASM pull ABI using an existing Node engine");
    for ([_]std.builtin.OptimizeMode{ .debug, .safe, .fast }) |mode| {
        const library = b.addLibrary(.{ .name = b.fmt("gama-embed-{s}", .{@tagName(mode)}), .linkage = .static, .root_module = b.createModule(.{ .root_source_file = b.path("src/c_embed.zig"), .target = b.graph.host, .optimize = mode, .link_libc = b.graph.host.result.os.tag == .macos }) });
        const c_module = b.createModule(.{ .target = b.graph.host, .optimize = mode, .link_libc = true });
        c_module.addIncludePath(b.path("include"));
        c_module.addCSourceFile(.{ .file = b.path("tests/embed_consumer.c"), .flags = &.{ "-std=c11", "-Wall", "-Wextra", "-Werror", "-Wstrict-prototypes" } });
        c_module.linkLibrary(library);
        const consumer = b.addExecutable(.{ .name = b.fmt("embed-consumer-{s}", .{@tagName(mode)}), .root_module = c_module });
        const c_run = b.addRunArtifact(consumer);
        c_run.setCwd(b.path("."));
        c_run.expectExitCode(0);
        c_run.expectStdErrMatch("linked C ABI assertions passed");
        c_run.has_side_effects = true;
        _ = c_run.captureStdErr(.{ .basename = b.fmt("c-abi-{s}.tests.log", .{@tagName(mode)}) });
        abi_check.dependOn(&c_run.step);
        const wasm_target = b.resolveTargetQuery(.{ .cpu_arch = .wasm32, .os_tag = .freestanding, .abi = .none });
        for ([_]bool{ false, true }) |bounded| {
            const wasm = b.addExecutable(.{ .name = b.fmt("gama-wasm-{s}{s}", .{ @tagName(mode), if (bounded) "-bounded-test" else "" }), .root_module = b.createModule(.{ .root_source_file = b.path("src/wasm.zig"), .target = wasm_target, .optimize = mode, .link_libc = false, .link_libcpp = false, .single_threaded = true }) });
            wasm.root_module.export_symbol_names = &.{ "gama_wasm_v1_init", "gama_wasm_v1_shutdown", "gama_wasm_v1_key", "gama_wasm_v1_pointer", "gama_wasm_v1_resize", "gama_wasm_v1_needs_frame", "gama_wasm_v1_frame", "gama_wasm_v1_frame_ptr", "gama_wasm_v1_frame_len" };
            wasm.entry = .disabled;
            wasm.export_memory = true;
            wasm.import_memory = false;
            wasm.import_symbols = false;
            wasm.import_table = false;
            if (bounded) {
                wasm.stack_size = 64 * 1024;
                wasm.max_memory = 2 * 1024 * 1024;
            }
            const inspect = b.addExecutable(.{ .name = b.fmt("wasm-verify-{s}", .{@tagName(mode)}), .root_module = b.createModule(.{ .root_source_file = b.path("tools/wasm_verify.zig"), .target = b.graph.host, .optimize = mode }) });
            const verify_run = b.addRunArtifact(inspect);
            verify_run.addFileArg(wasm.getEmittedBin());
            verify_run.expectExitCode(0);
            verify_run.expectStdErrMatch("WASM structural verification passed:");
            verify_run.has_side_effects = true;
            _ = verify_run.captureStdErr(.{ .basename = b.fmt("wasm-inspect-{s}-{s}.tests.log", .{ @tagName(mode), if (bounded) "bounded" else "production" }) });
            wasm_check.dependOn(&verify_run.step);
            const runtime = b.addSystemCommand(&.{ "node", "tests/wasm_runtime.mjs" });
            runtime.addFileArg(wasm.getEmittedBin());
            if (bounded) runtime.addArg("bounded");
            runtime.setCwd(b.path("."));
            runtime.expectExitCode(0);
            runtime.expectStdErrMatch("WASM runtime assertions passed");
            runtime.has_side_effects = true;
            _ = runtime.captureStdErr(.{ .basename = b.fmt("wasm-runtime-{s}-{s}.tests.log", .{ @tagName(mode), if (bounded) "bounded" else "production" }) });
            wasm_runtime.dependOn(&runtime.step);
            if (!bounded) {
                const install = b.addInstallFile(wasm.getEmittedBin(), b.fmt("wasm/gama-{s}.wasm", .{@tagName(mode)}));
                wasm_check.dependOn(&install.step);
            }
        }
    }
    test_step.dependOn(abi_check);

    const terminal_check = b.step("check-terminal", "Native Zig PTY parent/child scenarios (Python stdlib allocates the pair)");
    for ([_]std.builtin.OptimizeMode{ .debug, .safe, .fast }) |mode| {
        const child_module = b.createModule(.{ .root_source_file = b.path("tests/terminal_child.zig"), .target = b.graph.host, .optimize = mode, .link_libc = true });
        child_module.addImport("gama", b.createModule(.{ .root_source_file = b.path("src/root.zig"), .target = b.graph.host, .optimize = mode, .link_libc = true }));
        const child = b.addExecutable(.{ .name = b.fmt("terminal-child-{s}", .{@tagName(mode)}), .root_module = child_module });
        const parent = b.addExecutable(.{ .name = b.fmt("terminal-parent-{s}", .{@tagName(mode)}), .root_module = b.createModule(.{ .root_source_file = b.path("tests/terminal_process.zig"), .target = b.graph.host, .optimize = mode, .link_libc = true }) });
        const run = b.addSystemCommand(&.{ "python3", "tests/with_pty.py" });
        run.addFileArg(parent.getEmittedBin());
        run.addFileArg(child.getEmittedBin());
        run.setCwd(b.path("."));
        run.expectExitCode(0);
        run.expectStdErrMatch("All 12 PTY process scenarios passed");
        _ = run.captureStdErr(.{ .basename = b.fmt("terminal-process-{s}.tests.log", .{@tagName(mode)}) });
        run.has_side_effects = true;
        run.stdio_limit = .limited(1024 * 1024);
        terminal_check.dependOn(&run.step);
    }
    test_step.dependOn(terminal_check);

    const unicode_generator = hostTool(b, "gama-unicode-generator", "tools/unicode/generate.zig");
    const unicode_run = b.addRunArtifact(unicode_generator);
    unicode_run.addArg("check");
    unicode_run.setCwd(b.path("."));
    unicode_run.expectExitCode(0);
    unicode_run.expectStdErrMatch("Unicode17 tables check:");
    unicode_run.has_side_effects = true;
    _ = unicode_run.captureStdErr(.{ .basename = "unicode-integrity.tests.log" });
    unicode_run.stdio_limit = .limited(1024 * 1024);
    const unicode_check = b.step("unicode-check", "Validate frozen Unicode inputs and byte-exact generated tables");
    unicode_check.dependOn(&unicode_run.step);
    test_step.dependOn(&unicode_run.step);

    const corpus = hostTool(b, "gama-corpus", "tools/corpus.zig");
    const corpus_run = b.addRunArtifact(corpus);
    corpus_run.setCwd(b.path("."));
    corpus_run.expectExitCode(0);
    corpus_run.expectStdErrMatch("Gama corpus: 31 immutable fixtures verified");
    corpus_run.has_side_effects = true;
    _ = corpus_run.captureStdErr(.{ .basename = "corpus-integrity.tests.log" });
    corpus_run.stdio_limit = .limited(1024 * 1024);
    const corpus_check = b.step("corpus-check", "Verify pinned parity manifest, sizes, SHA256, totality and contents");
    corpus_check.dependOn(&corpus_run.step);
    test_step.dependOn(&corpus_run.step);

    const negatives = hostTool(b, "gama-compile-fail", "tools/compile_fail.zig");
    const negative_run = b.addRunArtifact(negatives);
    negative_run.addArg(b.graph.zig_exe);
    negative_run.addFileArg(default_runner_path);
    negative_run.setCwd(b.path("."));
    negative_run.expectExitCode(0);
    negative_run.expectStdErrMatch("All 29 negative fixtures rejected\n");
    negative_run.has_side_effects = true;
    _ = negative_run.captureStdErr(.{ .basename = "compile-fail.tests.log" });
    negative_run.stdio_limit = .limited(1024 * 1024);
    const compile_fail = b.step("compile-fail", "Reject policy, component, RGB and capture fixtures");
    compile_fail.dependOn(&negative_run.step);

    const verifier = hostTool(b, "gama-verify", "tools/verify.zig");
    const portable = b.step("check-portable", "Check portable imports and pins; compile libc-free roots");
    const portable_run = b.addRunArtifact(verifier);
    portable_run.addArg("portable");
    portable_run.setCwd(b.path("."));
    portable_run.expectExitCode(0);
    portable_run.expectStdErrEqual("Gama portable source/pin policies passed\n");
    portable_run.has_side_effects = true;
    portable_run.stdio_limit = .limited(1024 * 1024);
    portable.dependOn(&portable_run.step);
    // These are compile-only package foundations. Linked adapters arrive later.
    for ([_]std.Target.Query{
        .{ .cpu_arch = .wasm32, .os_tag = .freestanding, .abi = .none },
        .{ .cpu_arch = .thumb, .os_tag = .freestanding, .abi = .eabi, .cpu_model = .{ .explicit = &std.Target.arm.cpu.cortex_m4 } },
    }) |query| {
        const portable_target = b.resolveTargetQuery(query);
        const portable_gama = b.createModule(.{ .root_source_file = b.path("src/root.zig"), .target = portable_target, .optimize = .safe, .link_libc = false, .link_libcpp = false });
        const probe = b.createModule(.{ .root_source_file = b.path("tools/portable_probe.zig"), .target = portable_target, .optimize = .safe, .link_libc = false, .link_libcpp = false });
        probe.addImport("gama", portable_gama);
        const object = b.addObject(.{
            .name = b.fmt("gama-foundation-{s}", .{@tagName(query.cpu_arch.?)}),
            .root_module = probe,
        });
        // Request emitted code: depending only on the compile step can run analysis
        // without materializing an object. These remain relocatables, not linked adapters.
        const artifact = b.addInstallFile(object.getEmittedBin(), b.fmt("portable/gama-foundation-{s}.o", .{@tagName(query.cpu_arch.?)}));
        portable.dependOn(&artifact.step);
    }
    for ([_]std.Target.Query{
        .{ .cpu_arch = .x86_64, .os_tag = .windows, .abi = .gnu },
        .{ .cpu_arch = .x86_64, .os_tag = .linux, .abi = .none },
    }) |query| {
        const native_target = b.resolveTargetQuery(query);
        const module = b.createModule(.{ .root_source_file = b.path("tools/headless_probe.zig"), .target = native_target, .optimize = .safe, .link_libc = false });
        module.addImport("gama", b.createModule(.{ .root_source_file = b.path("src/root.zig"), .target = native_target, .optimize = .safe, .link_libc = false }));
        const obj = b.addObject(.{ .name = b.fmt("gama-headless-{s}", .{@tagName(query.os_tag.?)}), .root_module = module });
        const install = b.addInstallFile(obj.getEmittedBin(), b.fmt("portable/gama-headless-{s}.o", .{@tagName(query.os_tag.?)}));
        portable.dependOn(&install.step);
    }
    const matrix = b.step("check-matrix", "Link macOS native, Linux x86_64/aarch64 TUI and Windows headless demos");
    for ([_]std.Target.Query{
        .{ .cpu_arch = .aarch64, .os_tag = .macos },
        .{ .cpu_arch = .x86_64, .os_tag = .linux, .abi = .none },
        .{ .cpu_arch = .aarch64, .os_tag = .linux, .abi = .none },
        .{ .cpu_arch = .x86_64, .os_tag = .windows, .abi = .gnu },
    }) |query| {
        const t = b.resolveTargetQuery(query);
        const module = b.createModule(.{ .root_source_file = b.path("examples/demo.zig"), .target = t, .optimize = .safe, .link_libc = query.os_tag.? == .macos });
        module.addImport("gama", b.createModule(.{ .root_source_file = b.path("src/root.zig"), .target = t, .optimize = .safe, .link_libc = query.os_tag.? == .macos }));
        const exe = b.addExecutable(.{ .name = b.fmt("gama-{s}-{s}", .{ @tagName(query.os_tag.?), @tagName(query.cpu_arch.?) }), .root_module = module });
        const install = b.addInstallFile(exe.getEmittedBin(), b.fmt("matrix/{s}", .{exe.out_filename}));
        matrix.dependOn(&install.step);
    }
    const format = b.addFmt(.{ .paths = &.{ b.path("build.zig"), b.path("build.zig.zon"), b.path("ZigToolchain.zon"), b.path("src"), b.path("tools"), b.path("examples"), b.path("tests") }, .check = true });
    const format_step = b.step("fmt-check", "Check formatting of owned Zig sources");
    format_step.dependOn(&format.step);
    const policies = b.addRunArtifact(verifier);
    policies.addArg("all");
    policies.setCwd(b.path("."));
    policies.expectExitCode(0);
    policies.has_side_effects = true;
    _ = policies.captureStdErr(.{ .basename = "source-policy.tests.log" });
    policies.stdio_limit = .limited(1024 * 1024);
    const check = b.step("check", "Run pins, format, final retirement/import policy, native tests, negatives");
    check.dependOn(&policies.step);
    check.dependOn(&format.step);
    check.dependOn(test_step);
    check.dependOn(compile_fail);
    check.dependOn(portable);
    check.dependOn(wasm_check);
    check.dependOn(wasm_runtime);
    check.dependOn(embedded_check);
    check.dependOn(mlir_check);
    check.dependOn(matrix);

    const api = hostTool(b, "gama-api-docs", "tools/api_docs.zig");
    const docs_run = b.addSystemCommand(&.{ "python3", "tools/check_docs.py" });
    docs_run.addFileArg(api.getEmittedBin());
    docs_run.setCwd(b.path("."));
    docs_run.expectExitCode(0);
    docs_run.has_side_effects = true;
    _ = docs_run.captureStdOut(.{ .basename = "docs.tests.log" });
    const docs_step = b.step("check-docs", "Validate current references, API documentation and category negative controls");
    docs_step.dependOn(&docs_run.step);
    check.dependOn(docs_step);
    const evidence = b.addSystemCommand(&.{ "python3", "tools/check_evidence.py" });
    evidence.addArg(b.graph.zig_exe);
    evidence.setCwd(b.path("."));
    evidence.expectExitCode(0);
    evidence.has_side_effects = true;
    _ = evidence.captureStdOut(.{ .basename = "evidence.tests.log" });
    check.dependOn(&evidence.step);

    for ([_][]const u8{ "demo", "bench", "plugins" }) |name| {
        const module = b.createModule(.{ .root_source_file = b.path(b.fmt("examples/{s}.zig", .{name})), .target = target, .optimize = optimize, .link_libc = target.result.os.tag == .macos });
        module.addImport("gama", gama);
        const exe = b.addExecutable(.{ .name = name, .root_module = module });
        b.installArtifact(exe);
        if (std.mem.eql(u8, name, "demo")) {
            const terminal_smoke = b.addSystemCommand(&.{ "bash", ".agents/skills/run-gama/driver.sh", "smoke" });
            terminal_smoke.addFileArg(exe.getEmittedBin());
            terminal_smoke.setEnvironmentVariable("GAMA_RUN_ZIG", b.graph.zig_exe);
            terminal_smoke.setCwd(b.path("."));
            terminal_smoke.expectExitCode(0);
            terminal_smoke.expectStdOutMatch("PASS: counter, focus, editing, retained form");
            terminal_smoke.has_side_effects = true;
            _ = terminal_smoke.captureStdOut(.{ .basename = "run-gama.tests.log" });
            check.dependOn(&terminal_smoke.step);
            const driver_controls = b.addSystemCommand(&.{ "python3", "tools/check_driver.py" });
            driver_controls.setCwd(b.path("."));
            driver_controls.addFileArg(exe.getEmittedBin());
            driver_controls.expectExitCode(0);
            driver_controls.has_side_effects = true;
            _ = driver_controls.captureStdOut(.{ .basename = "driver.tests.log" });
            check.dependOn(&driver_controls.step);
        }
        const run = b.addRunArtifact(exe);
        run.addPassthruArgs();
        b.step(name, "Run example").dependOn(&run.step);
        const smoke = b.addRunArtifact(exe);
        if (std.mem.eql(u8, name, "demo")) smoke.addArg("--gama-plain");
        if (std.mem.eql(u8, name, "bench")) smoke.addArgs(&.{ "--runs", "2", "--frames", "40", "--warmup", "8" });
        smoke.expectExitCode(0);
        smoke.expectStdOutMatch(if (std.mem.eql(u8, name, "demo")) "count 0" else if (std.mem.eql(u8, name, "bench")) "BENCH" else "uninstall revoked");
        smoke.has_side_effects = true;
        _ = smoke.captureStdOut(.{ .basename = b.fmt("example-{s}.tests.log", .{name}) });
        check.dependOn(&smoke.step);
    }
}

fn hostTool(b: *std.Build, name: []const u8, path: []const u8) *std.Build.Step.Compile {
    return b.addExecutable(.{ .name = name, .root_module = b.createModule(.{ .root_source_file = b.path(path), .target = b.graph.host, .optimize = .safe }) });
}
