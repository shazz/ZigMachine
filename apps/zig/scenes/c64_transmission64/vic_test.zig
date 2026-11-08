// The VIC model and the 6510 clock against the rules they model (the numbers are VICE 3.9's,
// measured on Transmission64's captures: prototypes/transmission64_re/ANALYSIS.md).
//   zig test apps/zig/scenes/c64_transmission64/vic_test.zig
const std = @import("std");
const vic = @import("vic.zig");
const Clock = @import("clock.zig").Clock;

var ram: [65536]u8 = undefined;
var col: [1024]u8 = undefined;
var pix: [vic.Out.ROWS_COLS]u8 = undefined;
const rom = [_]u8{0} ** 4096;

fn setup(d011: u8, d016: u8, d018: u8) vic.Vic {
    @memset(&ram, 0);
    @memset(&col, 0);
    @memset(&pix, 0);
    var regs = [_]u8{0} ** vic.NREG;
    regs[0x11] = d011;
    regs[0x16] = d016;
    regs[0x18] = d018;
    regs[0x20] = 0x0E;
    regs[0x21] = 0x06;
    return vic.Vic.init(regs, 0xC7); // bank 0
}

fn mem() vic.Mem {
    return .{ .ram = &ram, .col = &col, .chargen = &rom };
}

fn at(line: u16, x: u16) u8 { // pixel at raster line, X (window X 24..343)
    return pix[(line - vic.FIRST_LINE) * vic.COLS + x + 16];
}

test "text: cell (0,0)'s first char row is on line 51, ink 1 + colour, paper 1 + $D021" {
    var v = setup(0x1B, 0x08, 0x18); // screen $0400, charset $2000
    ram[0x0400] = 1;
    ram[0x2008] = 0x80; // char 1, row 0: leftmost pixel
    col[0] = 2;
    var out = vic.Out{ .pix = &pix };
    _ = v.frame(&vic.Queue{}, &.{}, mem(), &out);
    try std.testing.expectEqual(@as(u8, 3), at(51, 24));
    try std.testing.expectEqual(@as(u8, 7), at(51, 25));
    try std.testing.expectEqual(@as(u8, 7), at(52, 24)); // row 1 of char 1 is empty
    try std.testing.expectEqual(@as(u8, 0), at(50, 24)); // the border above
}

test "a screen store after the row's bad line shows from the next row only (the VIC latched it)" {
    var v = setup(0x1B, 0x08, 0x18);
    for (0..8) |r| ram[0x2008 + r] = 0xFF; // char 1 solid
    var st = vic.Stores{};
    st.put(52 * vic.CYCLES, 0x0400, 1, false); // line 52: row 0 was fetched on line 51
    st.put(52 * vic.CYCLES + 1, 0x0428, 1, false); // row 1 (bad line 59): in time
    var out = vic.Out{ .pix = &pix };
    _ = v.frame(&vic.Queue{}, st.items(), mem(), &out);
    try std.testing.expectEqual(@as(u8, 7), at(53, 24)); // still char 0, paper
    try std.testing.expectEqual(@as(u8, 1), at(59, 24)); // char 1, ink black (colour 0)
}

test "multicolour bitmap: pairs 00 $D021, 01 screen high, 10 screen low, 11 colour RAM" {
    var v = setup(0x3B, 0x18, 0x18); // bitmap $2000
    ram[0x0400] = 0x52;
    col[0] = 0x0C;
    ram[0x2000] = 0b00011011;
    var out = vic.Out{ .pix = &pix };
    _ = v.frame(&vic.Queue{}, &.{}, mem(), &out);
    for ([_]u8{ 0x06, 0x05, 0x02, 0x0C }, 0..) |c, k| try std.testing.expectEqual(c + 1, at(51, @intCast(24 + 2 * k)));
}

test "multicolour text: colour bit 3 set, pairs 00 $D021, 01 $D022, 10 $D023, 11 colour & 7" {
    var v = setup(0x1B, 0x18, 0x18);
    v.reg[0x22] = 0x05;
    v.reg[0x23] = 0x02;
    ram[0x0400] = 1;
    ram[0x2008] = 0b00011011;
    col[0] = 0x0A; // multicolour, colour 2
    var out = vic.Out{ .pix = &pix };
    _ = v.frame(&vic.Queue{}, &.{}, mem(), &out);
    for ([_]u8{ 0x06, 0x05, 0x02, 0x02 }, 0..) |c, k| {
        try std.testing.expectEqual(c + 1, at(51, @intCast(24 + 2 * k)));
        try std.testing.expectEqual(c + 1, at(51, @intCast(25 + 2 * k)));
    }
}

test "extended colour text: code bits 7-6 pick the paper ($D021..$D024), bits 5-0 the char" {
    var v = setup(0x5B, 0x08, 0x18);
    v.reg[0x24] = 0x07;
    ram[0x0400] = 0xC1; // char 1 on $D024
    ram[0x2008] = 0x80;
    col[0] = 2;
    var out = vic.Out{ .pix = &pix };
    _ = v.frame(&vic.Queue{}, &.{}, mem(), &out);
    try std.testing.expectEqual(@as(u8, 3), at(51, 24));
    try std.testing.expectEqual(@as(u8, 8), at(51, 25));
}

test "a border colour written at cycle 7 colours the whole line; DEN off blanks to the border" {
    var v = setup(0x0B, 0x08, 0x18);
    var q = vic.Queue{};
    q.w(100, 7, 0x20, 0x00);
    var out = vic.Out{ .pix = &pix };
    _ = v.frame(&q, &.{}, mem(), &out);
    try std.testing.expectEqual(@as(u8, 0x0E), out.border[99 - vic.FIRST_LINE]);
    try std.testing.expectEqual(@as(u8, 0x00), out.border[100 - vic.FIRST_LINE]);
    try std.testing.expectEqual(@as(u16, 0), out.split_x[100 - vic.FIRST_LINE]);
    try std.testing.expectEqual(@as(u8, 0), at(120, 100)); // screen off: border, no pixel
}

test "a sprite at Y 100 shows on lines 101..121 at column X + 16, cut at the window" {
    var v = setup(0x1B, 0x08, 0x18);
    v.reg[0x15] = 1;
    v.reg[0x00] = 100;
    v.reg[0x01] = 100;
    v.reg[0x27] = 1;
    ram[0x07F8] = 0x1C;
    for (0..21) |r| ram[0x0700 + 3 * r] = 0x80;
    var out = vic.Out{ .pix = &pix };
    _ = v.frame(&vic.Queue{}, &.{}, mem(), &out);
    try std.testing.expectEqual(@as(u8, 2), pix[(101 - vic.FIRST_LINE) * vic.COLS + 116]);
    try std.testing.expectEqual(@as(u8, 2), pix[(121 - vic.FIRST_LINE) * vic.COLS + 116]);
    try std.testing.expect(pix[(122 - vic.FIRST_LINE) * vic.COLS + 116] != 2);
}

test "clock: a read on a bad line waits from cycle 12 to 55, a write goes through" {
    var c = Clock.at(51, 10, true);
    c.rd(2); // cycles 10, 11
    c.rd(1); // stalled to 55
    try std.testing.expectEqual(@as(u32, 51 * 63 + 56), c.time());
    var w = Clock.at(51, 12, true);
    try std.testing.expectEqual(@as(u32, 51 * 63 + 12), w.wr());
    var off = Clock.at(51, 10, false); // screen off: no bad line
    off.rd(3);
    try std.testing.expectEqual(@as(u32, 51 * 63 + 13), off.time());
}

test "clock: the IRQ is taken at an instruction boundary and the routine resumes after it" {
    var c = Clock.at(247, 60, true);
    c.irq_at = 248 * 63;
    c.irq_end = 330 * 63;
    c.inst();
    c.rd(4); // 247:60 .. 248:1
    c.inst(); // past irq_at: the handler runs
    try std.testing.expectEqual(@as(u32, 330 * 63), c.time());
    c.inst(); // once
    try std.testing.expectEqual(@as(u32, 330 * 63), c.time());
}
