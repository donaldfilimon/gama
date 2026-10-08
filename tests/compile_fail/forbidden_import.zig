comptime {
    @import("policy").requirePortableSource("const x = @import(\"std\").process;");
}
test "hosted imports are rejected" {}
