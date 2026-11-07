// The sprite unit against the VIC-II rules it models (the numbers are VICE's, measured on
// 1988's captures: prototypes/1988_re/ANALYSIS.md).
//   zig test apps/zig/scenes/c64_1988/vic_test.zig
const std = @import("std");
const vic = @import("vic.zig");

var bank3: [16384]u8 = undefined;
var bank0: [2048]u8 = .{0} ** 2048;
var pix: [vic.Out.ROWS_COLS]u8 = undefined;
var foreign: u32 = 0;

const mem = vic.Mem{ .bank3 = &bank3, .bank0_2000 = &bank0, .foreign = &foreign };

// Block 1: row r has its leftmost pixel set and (as a row number) bits for r in byte 2.
fn setup() vic.Vic {
    @memset(&bank3, 0);
    for (0..21) |r| {
        bank3[64 + 3 * r] = 0x80;
        bank3[64 + 3 * r + 2] = @intCast(r);
    }
    @memset(&pix, 0);
    var regs = [_]u8{0} ** vic.NREG;
    regs[0x11] = 0x18; // screen on, 25 rows
    regs[0x15] = 0x01;
    regs[0x27] = 0x01; // white
    var v = vic.Vic.init(regs);
    v.bank3 = true; // the blocks above are in bank 3
    return v;
}

fn rowsLit(out: *const vic.Out, col: usize) [2]i32 {
    var first: i32 = -1;
    var last: i32 = -1;
    for (0..vic.ROWS) |r| if (out.pix[r * 400 + col] != 0) {
        if (first < 0) first = @intCast(r);
        last = @intCast(r);
    };
    return .{ first + 11, last + 11 }; // as raster lines
}

fn run(v: *vic.Vic, q: *vic.Queue, out: *vic.Out, frames: usize) void {
    for (0..frames) |_| v.frame(q, mem, out);
}

test "a sprite at Y 100 shows its 21 rows on lines 101..121, at column X + 16" {
    var v = setup();
    var out = vic.Out{ .pix = &pix };
    var q = vic.Queue{};
    q.w(0, 10, 0, 100); // X 100
    q.w(0, 12, 1, 100); // Y 100
    q.w(0, 14, vic.PTR0, 1);
    run(&v, &q, &out, 1);
    try std.testing.expectEqual([2]i32{ 101, 121 }, rowsLit(&out, 116));
}

test "Y-expanded, every row shows on two lines: 42 lines" {
    var v = setup();
    var out = vic.Out{ .pix = &pix };
    var q = vic.Queue{};
    for ([_][3]u8{ .{ 0, 100, 0 }, .{ 1, 100, 0 }, .{ 0x17, 1, 0 } }) |r| q.w(0, 10, r[0], r[1]);
    q.w(0, 14, vic.PTR0, 1);
    run(&v, &q, &out, 1);
    try std.testing.expectEqual([2]i32{ 101, 142 }, rowsLit(&out, 116));
}

test "the $D017 0-then-1 trick on every line holds the row: 100 lines of row 0, then Y-expanded" {
    var v = setup();
    var out = vic.Out{ .pix = &pix };
    var q = vic.Queue{};
    q.w(0, 10, 0, 100);
    q.w(0, 12, 1, 100);
    q.w(0, 14, vic.PTR0, 1);
    for (100..200) |l| {
        q.w(@intCast(l), 31, 0x17, 0);
        q.w(@intCast(l), 39, 0x17, 1);
    }
    run(&v, &q, &out, 1);
    // row 0 held on lines 101..200; $D017 stays 1 after, so rows 1..20 take 2 lines each
    try std.testing.expectEqual([2]i32{ 101, 241 }, rowsLit(&out, 116));
}

test "screen off (DEN 0) keeps the vertical border shut: no sprite pixel" {
    var v = setup();
    v.reg[0x11] = 0x08;
    var out = vic.Out{ .pix = &pix };
    var q = vic.Queue{};
    q.w(0, 10, 0, 100);
    q.w(0, 12, 1, 100);
    q.w(0, 14, vic.PTR0, 1);
    run(&v, &q, &out, 2);
    try std.testing.expectEqual([2]i32{ 10, 10 }, rowsLit(&out, 116)); // none (-1 + 11)
}

test "the right border opens only for a $D016 DEC at cycles 55..56" {
    for ([_]u8{ 54, 55, 56, 57 }) |cyc| {
        var v = setup();
        var out = vic.Out{ .pix = &pix };
        var q = vic.Queue{};
        q.w(0, 10, 0, 0x60); // X 352: physical 368, in the right border
        q.w(0, 11, 0x10, 1);
        q.w(0, 12, 1, 100);
        q.w(0, 14, vic.PTR0, 1);
        q.w(110, cyc, 0x16, 0);
        run(&v, &q, &out, 1);
        const lit = out.pix[(110 - 11) * 400 + 368] != 0;
        try std.testing.expectEqual(cyc == 55 or cyc == 56, lit);
    }
}
