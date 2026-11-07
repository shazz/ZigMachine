// --------------------------------------------------------------------------
// Part 3's seven bands of 35 lines ($4400, $4662): the whole effect is one loop per line,
//   STY $D017 (0) / LDA $6C,X / STA $D017 / ... / DEC $D016 / NOP NOP / INC $D016
// The $D017 pair makes every sprite whose bit is set in mask[i] repeat its row on that line
// (vic.zig: the Y-expansion flip-flop), so a column's cube sits as low in its 37-line band
// as it was held above it: the bounce. The DEC/INC pair, at the right cycle, keeps the side
// borders open on that line (all 384+ pixels hold sprites).
//
// The cycles are the 6510's, as VICE traces them. After each band's Y rewrite the loop
// starts early and catches up 2 cycles a line (the sprite DMA syncs it): until it does,
// the DEC lands before the X=335 compare and that line's right border closes. The bottom
// band's 4th line depends on the IRQ's jitter (2 frames in 3 closed, chaotic): the port
// keeps the majority, closed.
// --------------------------------------------------------------------------
const vic = @import("vic.zig");

pub const ROWS = 35;
pub const Y_TOP = [7]u8{ 0x18, 0x3D, 0x62, 0x87, 0xAC, 0xD1, 0xF9 }; // each band's sprite Y

// (STY, STA, DEC) cycles of a band's first lines; later lines run at (31, 39, 56).
const FIRST_BAND = [_][3]u8{ .{ 28, 36, 53 }, .{ 30, 38, 55 } };
const MID_BAND = [_][3]u8{ .{ 23, 31, 48 }, .{ 25, 33, 50 }, .{ 27, 35, 52 }, .{ 29, 37, 54 } };
const LAST_BAND = [_][3]u8{ .{ 24, 32, 49 }, .{ 26, 34, 51 }, .{ 28, 36, 53 }, .{ 30, 38, 54 } };
const STEADY = [3]u8{ 31, 39, 56 };

fn cycles(b: usize, i: usize) [3]u8 {
    const first: []const [3]u8 = switch (b) {
        0 => &FIRST_BAND,
        6 => &LAST_BAND,
        else => &MID_BAND,
    };
    return if (i < first.len) first[i] else STEADY;
}

/// Band b's 35 lines from `line`, then (bands 0..5) the next band's Y.
pub fn band(q: *vic.Queue, b: usize, line: u16, masks: *const [ROWS]u8) void {
    for (0..ROWS) |i| {
        const l = line + @as(u16, @intCast(i));
        const c = cycles(b, i);
        q.w(l, c[0], 0x17, 0);
        q.w(l, c[1], 0x17, masks[i]);
        q.w(l, c[2], 0x16, 0); // DEC $D016
        q.w(l + 1, 20, 0x16, 0); // INC $D016
    }
    if (b == 6) return;
    const yl = line + ROWS;
    for (0..8) |s| q.at(yl, if (s < 6) 32 + 4 * @as(u16, @intCast(s)) else 63 + 12 + 4 * (@as(u16, @intCast(s)) - 6), 1 + 2 * @as(u8, @intCast(s)), Y_TOP[b + 1]);
}

/// The top six bands of a frame: sprites on at line 23, bands at lines 24 + 37b.
pub fn top(q: *vic.Queue, masks: *const [ROWS]u8) void {
    q.w(23, 17, 0x15, 0xFF);
    for (0..6) |b| band(q, b, 24 + 37 * @as(u16, @intCast(b)), masks);
    q.w(245, 50, 0x11, 0x0B);
}

/// The bottom band (its own IRQ at 247): RSEL off on line 248 keeps the border open.
pub fn bottom(q: *vic.Queue, masks: *const [ROWS]u8) void {
    q.w(248, 18, 0x11, 0x00);
    band(q, 6, 249, masks);
}
