// --------------------------------------------------------------------------
// Part 3's init ($3808..$3927): its memory once $09CE has released the main loop, and the
// register set-up it reaches a frame later (part3.zig calls both; the shape's code is
// generated between them, part3_dots.zig).
// --------------------------------------------------------------------------
const vic = @import("vic.zig");
const data3 = @import("data3.zig");
const dotColours = @import("part3_panel.zig").dotColours;

/// The decrunched banks, then $3808..$3866: colours, screens, sprite block, erase lists, tables.
pub fn memory(ram: *[65536]u8, col: *[1024]u8, d: data3.Part3) void {
    @memcpy(ram[0x2000..0x4000], d.bank0());
    @memcpy(ram[0xC000..0x10000], d.bank3());
    dotColours(ram, col, 0); // $38B9
    dotColours(ram, col, 1); // $38D3
    @memcpy(ram[0x0800..0x0C00], ram[0xC800..0xCC00]);
    for (0..8) |i| {
        ram[0x0BF8 + i] = 0x1C;
        ram[0xCBF8 + i] = 0x1C;
    }
    @memcpy(ram[0x0700..0x073F], ram[0xC700..0xC73F]);
    for (0..256) |y| ram[0x0600 + y] = @intCast(y & 0xF8);
}

/// $3879 and $3927 on line 234 (the shape generation took the frame before): invalid mode,
/// 40 columns, bank 0, the sprites cleared and white.
pub fn regs(q: *vic.Queue) void {
    for ([_][2]u8{ .{ 0x11, 0x7B }, .{ 0x16, 0xC8 }, .{ 0x18, 0x18 }, .{ vic.BANK, 0xC7 } }, 0..) |w, k| q.w(234, @intCast(30 + 6 * k), w[0], w[1]);
    var c: u8 = 0;
    for ([_]u8{ 0x10, 0x15, 0x17, 0x1B, 0x1C, 0x1D }) |r| {
        q.w(235, c, r, 0);
        c += 4;
    }
    for (0..16) |r| q.w(236, @intCast(3 * r), @intCast(r), 0);
    for (0..8) |r| q.w(237, @intCast(6 * r), @intCast(0x27 + r), 1);
}
