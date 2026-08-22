const std = @import("std");
const builtin = std.builtin;

extern fn jsConsoleLogWrite(ptr: [*]const u8, len: usize) void;
extern fn jsConsoleLogFlush() void;
extern fn jsThrowError(ptr: [*]const u8, len: usize) void;


pub fn panic(message: []const u8, _: ?*builtin.StackTrace, _: ?usize) noreturn {
    jsThrowError(message.ptr, message.len);
}

pub const Console = struct {
    // Zig 0.16 removed std.io.Writer (Writergate); format into a stack buffer
    // and push it across the JS boundary. Oversized messages are truncated.
    var buf: [2048]u8 = undefined;

    pub fn log(comptime format: []const u8, args: anytype) void {
        const msg = std.fmt.bufPrint(&buf, format, args) catch buf[0..];
        jsConsoleLogWrite(msg.ptr, msg.len);
        jsConsoleLogFlush();
    }
};