// --------------------------------------------------------------------------
// TR, the four text cards ("enjoy the ride", "only raster magic needed",
// "party shout out", "end of part one"). Kernel $21E00: 144 lines, registers
// d0..a4 = the 13-word palette. Line k shows card row k + s, or a blank line:
//   card row  : d0 at rel 332+512k, 52 x 8 px cells from 340, d0 at 756
//   blank line: 59 writes of d0 from 332
// The roll offset s comes from the 50-word table at $69676; the roll-in and
// roll-out counters ($21B6E, $21DFC) are shared by all four cards.
// --------------------------------------------------------------------------
const core = @import("core.zig");
const out = @import("out.zig");
const rip = @import("rip.zig");
const assets = @import("assets.zig");

const ROWS = 144;
const NONE: u8 = 0xFF;

var c21b6e: u32 = 0;
var c21dfc: u32 = 0;
var pal: [13]u16 = undefined;
var idx: u32 = 0;
var card: usize = 0;
var map: [ROWS]u8 = undefined; // card row per line, NONE = blank

pub fn reset() void {
    c21b6e = rip.TR_C21B6E;
    c21dfc = rip.TR_C21DFC;
    @memset(&pal, 0);
    idx = 0;
    card = 0;
    @memset(&map, NONE);
}

/// $21842 / $21866 / $2188A / $218AE: card `k` from black, rolled off.
pub fn init(k: usize) void {
    core.colour = 0;
    @memset(&pal, 0);
    idx = 0;
    card = k;
}

pub fn vbl() void {
    core.colour = 0;
}

fn remap() void {
    const s = rip.TR_OFFS[idx >> 1] >> 2;
    for (&map, 0..) |*m, k| m.* = if (k + s < ROWS) @intCast(k + s) else NONE;
}

/// $218E0: every 3rd call a fade step in, then roll one step on.
pub fn rollIn() void {
    c21b6e -= 1;
    if (c21b6e == 0) {
        c21b6e = 3;
        core.step1(&pal, &rip.TR_TGT_IN);
    }
    remap();
    if (idx < 0x62) idx += 2;
}

/// $21B70: every 4th call a fade step out, then roll one step back.
pub fn rollOut() void {
    c21dfc -= 1;
    if (c21dfc == 0) {
        c21dfc = 4;
        core.step1(&pal, &rip.TR_TGT_OUT);
    }
    remap();
    if (idx > 0) idx -= 2;
}

pub fn kernel(l0: u32) void {
    const d0 = pal[0];
    for (map, 0..) |r, k| {
        const b: u32 = 512 * @as(u32, @intCast(k));
        if (r == NONE) {
            for (0..59) |i| out.emit(l0, 332 + 8 * @as(u32, @intCast(i)) + b, d0);
            continue;
        }
        out.emit(l0, 332 + b, d0);
        const row = assets.tr_cards[(card * ROWS + r) * 52 ..][0..52];
        for (row, 0..) |n, j| out.emit(l0, 340 + 8 * @as(u32, @intCast(j)) + b, pal[n]);
        out.emit(l0, 756 + b, d0);
    }
    out.emit(l0, 74044, 0);
    core.colour = 0;
}
