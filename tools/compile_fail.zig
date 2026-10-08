//! Every fixture must fail for its pinned diagnostic, rather than an incidental error.
const std = @import("std");
const Fixture = struct { path: []const u8, diagnostic: []const u8, runtime: bool = false, single_threaded: bool = false };
const fixtures = [_]Fixture{
    .{ .path = "tests/compile_fail/plugin_capture_spoof.zig", .diagnostic = "action.capture-must-be-owned-value" },
    .{ .path = "tests/compile_fail/plugin_capture_pointer.zig", .diagnostic = "action.capture-must-be-owned-value" },
    .{ .path = "tests/compile_fail/plugin_capture_slice.zig", .diagnostic = "action.capture-must-be-owned-value" },
    .{ .path = "tests/compile_fail/signal_optional_pointer_vector.zig", .diagnostic = "state.value-requires-clone-and-deinit" },
    .{ .path = "tests/compile_fail/signal_optional_pointer_vector_nested.zig", .diagnostic = "state.value-requires-clone-and-deinit" },
    .{ .path = "tests/compile_fail/signal_pointer_vector.zig", .diagnostic = "state.value-requires-clone-and-deinit" },
    .{ .path = "tests/compile_fail/signal_pointer_vector_nested.zig", .diagnostic = "state.value-requires-clone-and-deinit" },
    .{ .path = "tests/compile_fail/state_optional_pointer_vector.zig", .diagnostic = "state.value-requires-clone-and-deinit" },
    .{ .path = "tests/compile_fail/state_optional_pointer_vector_nested.zig", .diagnostic = "state.value-requires-clone-and-deinit" },
    .{ .path = "tests/compile_fail/state_pointer_vector.zig", .diagnostic = "state.value-requires-clone-and-deinit" },
    .{ .path = "tests/compile_fail/state_pointer_vector_nested.zig", .diagnostic = "state.value-requires-clone-and-deinit" },
    .{ .path = "tests/compile_fail/state_unmanaged_slice.zig", .diagnostic = "state.value-requires-clone-and-deinit" },
    .{ .path = "tests/compile_fail/capture_spoof.zig", .diagnostic = "action.capture-must-be-owned-value" },
    .{ .path = "tests/compile_fail/native_single_threaded.zig", .diagnostic = "host.native-requires-multithreaded-build", .single_threaded = true },
    .{ .path = "tests/compile_fail/action_capture_slice.zig", .diagnostic = "action.capture-must-be-owned-value" },
    .{ .path = "tests/compile_fail/action_capture_error_union.zig", .diagnostic = "action.capture-must-be-owned-value" },
    .{ .path = "tests/compile_fail/component_receiver.zig", .diagnostic = "component.render-signature" },
    .{ .path = "tests/compile_fail/component_result.zig", .diagnostic = "component.render-signature" },
    .{ .path = "tests/compile_fail/component_missing.zig", .diagnostic = "component.render-signature" },
    .{ .path = "tests/compile_fail/component_nonstruct.zig", .diagnostic = "component.render-signature" },
    .{ .path = "tests/compile_fail/rgb_length.zig", .diagnostic = "rgb.malformed" },
    .{ .path = "tests/compile_fail/rgb_digit.zig", .diagnostic = "rgb.malformed" },
    .{ .path = "tests/compile_fail/rgb_runtime.zig", .diagnostic = "unable to evaluate comptime expression" },
    .{ .path = "tests/compile_fail/action_capture_pointer.zig", .diagnostic = "action.capture-must-be-owned-value" },
    .{ .path = "tests/compile_fail/wrong_compiler.zig", .diagnostic = "Gama requires Zig" },
    .{ .path = "tests/compile_fail/dependencies.zig", .diagnostic = "Gama forbids package dependencies" },
    .{ .path = "tests/compile_fail/forbidden_import.zig", .diagnostic = "Gama forbids hosted or foreign portable imports" },
    .{ .path = "tests/compile_fail/forbidden_source.zig", .diagnostic = "Gama forbids legacy or foreign sources" },
    .{ .path = "tests/compile_fail/zero_tests.zig", .diagnostic = "zero-test suite", .runtime = true },
};

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len != 3) return error.ExpectedCompilerAndRunner;
    for (fixtures) |fixture| {
        const root = try std.fmt.allocPrint(init.gpa, "-Mroot={s}", .{fixture.path});
        defer init.gpa.free(root);
        const runner = try std.fmt.allocPrint(init.gpa, "-Mdefault_runner={s}", .{args[2]});
        defer init.gpa.free(runner);
        const argv: []const []const u8 = if (fixture.runtime)
            &.{ args[1], "test", "-fllvm", "--test-runner", "tools/test_runner.zig", "--dep", "gama", "--dep", "policy", "--dep", "default_runner", root, "-Mpolicy=tools/policy.zig", "-Mgama=src/root.zig", runner }
        else if (fixture.single_threaded)
            &.{ args[1], "test", "--test-no-exec", "-lc", "-fsingle-threaded", "--dep", "gama", root, "-fsingle-threaded", "-Mgama=src/root.zig" }
        else
            &.{ args[1], "test", "--test-no-exec", "-fllvm", "--test-runner", "tools/test_runner.zig", "--dep", "gama", "--dep", "policy", "--dep", "default_runner", root, "-Mpolicy=tools/policy.zig", "-Mgama=src/root.zig", runner };
        const result = try std.process.run(init.gpa, init.io, .{
            .argv = argv,
            .stdout_limit = .limited(64 * 1024),
            .stderr_limit = .limited(64 * 1024),
        });
        defer init.gpa.free(result.stdout);
        defer init.gpa.free(result.stderr);
        if (result.term.success()) {
            std.debug.print("negative fixture unexpectedly compiled: {s}\n", .{fixture.path});
            return error.NegativeCompiled;
        }
        if (std.mem.indexOf(u8, result.stderr, fixture.diagnostic) == null) {
            std.debug.print("wrong failure for {s}: {s}\n", .{ fixture.path, result.stderr });
            return error.WrongNegativeDiagnostic;
        }
        std.debug.print("{s} OK: {s} ({s})\n", .{ if (fixture.runtime) "runtime-guard" else "compile-fail", fixture.path, fixture.diagnostic });
    }
    std.debug.print("All {d} negative fixtures rejected\n", .{fixtures.len});
}
