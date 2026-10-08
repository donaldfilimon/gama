comptime {
    @import("policy").requireVersion("0.18.0-dev.121+9fe22a29b");
}
test "a mismatched compiler is rejected" {}
