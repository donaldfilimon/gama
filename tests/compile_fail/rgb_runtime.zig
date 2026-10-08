const g = @import("gama");
export fn runtime(ptr: [*]const u8, len: usize) u8 {
    return g.rgb(ptr[0..len]).r;
}
test {
    _ = &runtime;
}
