//! Cooperative static plugin installation, command invocation, and revocation.
const std = @import("std");
const g = @import("gama");
const Plugin = struct {
    pub fn manifest(_: *@This()) g.plugins.Manifest {
        return .{ .id = "example" };
    }
    pub fn activate(_: *@This(), _: g.plugins.Context) g.Error!void {}
    pub fn commands(_: *@This()) g.Error![]const g.plugins.CommandDefinition {
        return &.{.{ .id = "refresh", .title = "Refresh", .action = refresh }};
    }
    fn refresh(context: g.plugins.Context) g.Error!void {
        try context.invalidate();
    }
};
pub fn main(init: std.process.Init) !void {
    const runtime = try g.PluginRuntime.create(init.gpa, .{}, .{});
    defer runtime.destroy() catch unreachable;
    try runtime.install(Plugin{});
    const commands = try runtime.commands(init.gpa);
    defer init.gpa.free(commands);
    if (commands.len != 1) return error.MissingCommand;
    try commands[0].perform();
    try runtime.uninstall("example");
    if (commands[0].perform()) |_| return error.StaleCommandAccepted else |err| if (err != error.InvalidHandle) return err;
    var out = std.Io.File.stdout().writer(init.io, &.{});
    try out.interface.writeAll("Plugin command executed; uninstall revoked its handle.\n");
}
