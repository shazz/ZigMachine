//! Compiles every zigdemo module: each declaration of the umbrella is analysed, so a
//! type error in r3d.zig or in an unused generic shows here, not only in a cart.
const std = @import("std");
const zigdemo = @import("zigdemo.zig");

test "every zigdemo module compiles" {
    std.testing.refAllDecls(zigdemo);
}
