//
// from https://github.com/luickk/zig-png-decoder
//
extern fn consoleLogJS(ptr: [*]const u8, len: usize) void;

fn consoleLog(s: []const u8) void {
    consoleLogJS(s.ptr, s.len);
}

const std = @import("std");

const MagicNumberErr = error{BitDepthColorTypeMissmatch};

pub const PngStreamStart = [_]u8{ 137, 80, 78, 71, 13, 10, 26, 10 };

pub const ChunkType = enum(u32) {
    idat = @bitCast(u32, [_]u8{ 73, 68, 65, 84 }),
    iend = @bitCast(u32, [_]u8{ 73, 69, 78, 68 }),
    ihdr = @bitCast(u32, [_]u8{ 73, 72, 68, 82 }),

    pub fn isCritical(chunk_type: u32) bool {
        if (@truncate(u1, @truncate(u8, chunk_type) >> 5) == 0)
            return true;
        return false;
    }
};

pub const ColorType = enum(u8) {
    greyscale = 0,
    truecolor = 2,
    index_colored = 3,
    greyscale_alpha = 4,
    truecolor_alpha = 6,

    pub fn checkAllowedBitDepths(self: ColorType, bit_depth: u8) !void {
        switch (self) {
            ColorType.truecolor => if (bit_depth == 8 or bit_depth == 16) return,
            ColorType.truecolor_alpha => if (bit_depth == 8 or bit_depth == 16) return,
            else => {},
        }
        consoleLog("Error: bit depth not supported");
        return MagicNumberErr.BitDepthColorTypeMissmatch;
    }
};