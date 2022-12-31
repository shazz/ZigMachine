const std = @import("std");

pub fn consoleLog(s: []const u8) void {
    std.debug.print("Trace: {s}\n", .{s});
}