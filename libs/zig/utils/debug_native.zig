const std = @import("std");

pub const Console = struct {
    pub fn log(comptime format: []const u8, args: anytype) void {
        std.debug.print(format ++ "\n", args);
    }
};
