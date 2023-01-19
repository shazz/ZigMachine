const std = @import("std");
const builtin = std.builtin;

extern fn jsConsoleLogWrite(ptr: [*]const u8, len: usize) void;
extern fn jsConsoleLogFlush() void;
extern fn jsThrowError(ptr: [*]const u8, len: usize) void;


pub fn panic(message: []const u8, _: ?*builtin.StackTrace, _: ?usize) noreturn {
    jsThrowError(message.ptr, message.len);
}

pub const Console = struct {
    pub const Logger = struct {
        pub const Error = error{};
        pub const Writer = std.io.Writer(void, Error, write);

        fn write(_: void, bytes: []const u8) Error!usize {
            jsConsoleLogWrite(bytes.ptr, bytes.len);
            return bytes.len;
        }
    };

    const logger = Logger.Writer{ .context = {} };
    pub fn log(comptime format: []const u8, args: anytype) void {
        logger.print(format, args) catch return;
        jsConsoleLogFlush();
    }
};