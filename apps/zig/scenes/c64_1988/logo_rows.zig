// --------------------------------------------------------------------------
// The logo's rows 1..8 and its closing handler: the multiplexer proper.
//
// Row k's IRQ is at line base + 17 + 20(k-1); its writes land some lines later, as many as
// the handler's stable-raster preamble takes, which depends on where the bad lines fall
// (lines with (line & 7) == 0 steal 40 cycles; the screen is on in part 1). Measured over
// two loops of VICE traces (prototypes/1988_re/ANALYSIS.md), by the IRQ line's phase:
//   Y writes        +3 +2 +2 +2 +2 +2 +3 +3   (phase 0..7)
//   pointer writes  +4 +3 +3 +3 +3 +4 +4 +4
// The pointers land before the previous row's last fetch, so its last lines already show
// the next row's blocks: the C64 shows that, so the port does.
// --------------------------------------------------------------------------
const vic = @import("vic.zig");

const Y_LATE = [8]u16{ 3, 2, 2, 2, 2, 2, 3, 3 };
const PTR_LATE = [8]u16{ 4, 3, 3, 3, 3, 4, 4, 4 };
// The pointer stores in their order (SAX $F3F8 / STX $F3FC / INX ...) and their cycles.
const PTR_ORDER = [8]u8{ 0, 4, 1, 5, 2, 6, 3, 7 };
const PTR_CYC = [8]u16{ 0, 4, 10, 14, 20, 24, 30, 34 };

/// Row k's pointers 8k..8k+7, the stores starting at cycle `t` of the frame.
pub fn pointers(q: *vic.Queue, t: u16, k: u8) void {
    for (PTR_ORDER, PTR_CYC) |s, c| q.at(0, t + c, vic.PTR0 + s, 8 * k + s);
}

pub fn chain(q: *vic.Queue, base: u8) void {
    var k: u8 = 1;
    while (k <= 8) : (k += 1) {
        const irq: u16 = @as(u16, base) + 17 + 20 * (@as(u16, k) - 1);
        const y = base +% 21 * k;
        for (0..8) |s| q.at(irq + Y_LATE[irq & 7], 21 + 4 * @as(u16, @intCast(s)), 1 + 2 * @as(u8, @intCast(s)), y);
        pointers(q, (irq + PTR_LATE[irq & 7]) * 63 + 13, k);
    }
    close(q, @as(u16, base) + 17 + 20 * 8);
}

// $5D0C: pointers 0, Y $0A (the bottom scroller, line 266), X-expanded hires sprites.
fn close(q: *vic.Queue, irq: u16) void {
    const l = irq + Y_LATE[irq & 7];
    for (0..8) |s| q.at(l, 20 + 4 * @as(u16, @intCast(s)), vic.PTR0 + @as(u8, @intCast(s)), 0);
    q.at(l, 54, 1, 0x0A);
    for (1..8) |s| q.at(l + 1, 14 + 4 * (@as(u16, @intCast(s)) - 1), 1 + 2 * @as(u8, @intCast(s)), 0x0A);
    q.at(l + 1, 44, 0x1D, 0xFF);
    q.at(l + 1, 50, 0x1C, 0x00);
    q.at(l + 2, 38, 0x11, 0x18);
}
