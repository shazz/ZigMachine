const std = @import("std");

pub const Console = struct {

    pub fn log(s: []const u8) void {
        std.debug.print("Trace: {s}\n", .{s});
    }
};
