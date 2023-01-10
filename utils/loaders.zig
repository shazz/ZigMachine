// --------------------------------------------------------------------------
// Imports
// --------------------------------------------------------------------------
const std = @import("std");
const Color = @import("../zigos.zig").Color;

// --------------------------------------------------------------------------
// Loader for data u16 data files
// better than hardcore casting:         
// var table: *const [WIDTH]u16 = @ptrCast(*const [WIDTH]u16, @alignCast(2, offset_table_b));
// --------------------------------------------------------------------------
pub fn readU16Array(comptime raw: []const u8) [@divExact(raw.len, 2):0]u16 {
    comptime {
        const len = @divExact(raw.len, 2);
        var table: [len:0]u16 = undefined;
        for (table) |*out, i| {
            out.* = std.mem.readIntLittle(u16, raw[i * 2 ..][0..2]);
        }
        return table;
    }
}

// --------------------------------------------------------------------------
// Loader for u8 palette data converted to Color structs
// --------------------------------------------------------------------------
pub fn convertU8ArraytoColors(comptime contents: []const u8) [256]Color {
    comptime {
        if (contents.len != 4 * 256)
            @compileError(std.fmt.comptimePrint("Expected file to be {d} bytes, but it's {d} bytes.", .{ 4 * 256, contents.len }));
        @setEvalBranchQuota(contents.len);
        const arrays: *const [256][4]u8 = std.mem.bytesAsValue([256][4]u8, contents[0..]);
        var colors: [256]Color = undefined;
        for (arrays) |arr, i| colors[i] = .{
            .r = arr[0],
            .g = arr[1],
            .b = arr[2],
            .a = arr[3],
        };
    return colors;
    }
}
