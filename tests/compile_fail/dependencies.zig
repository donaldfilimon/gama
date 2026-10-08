comptime {
    @import("policy").requireEmptyDependencies(.{ .foreign = .{} });
}
test "a dependency is rejected" {}
