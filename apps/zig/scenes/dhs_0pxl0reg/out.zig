// --------------------------------------------------------------------------
// The frame's colour-0 writes, and the global HBL that hands them to the BEAM.
//
// A kernel emits every move.w to $FF8240 as (L0, rel, value): rel is cycles
// after its lsr.l sync, L0 the ST line the sync completes on. The measured
// mapping (SCHEDULE.md) places it:
//     k = rel + 177;  ST line = L0 + k / 512;  capture x = k mod 512
//     physical line = ST line - 23;  physical x = capture x - 9
// A write at physical x < 0 lands in the line's left edge, and one at x >= 400
// in the right border or the horizontal blank (capture 409..511): on an ST both
// only decide the colour the NEXT visible pixels start with. They become that
// line's starting colour, loaded into BACKGROUND by the HBL before its list,
// and are never queued as beam writes (the machine would drop them).
// --------------------------------------------------------------------------
const zg = @import("zigos");

pub const LINES = zg.PHYSICAL_HEIGHT; // 280
const W = zg.PHYSICAL_WIDTH; // 400
const SLOTS = zg.beam.MAX; // more than that on a line is counted, not stored

var count: [LINES]u8 = undefined;
var list: [LINES][SLOTS]u32 = undefined; // x << 16 | ST colour word
var start_set: [LINES]bool = undefined;
var start_col: [LINES]u16 = undefined;
var top: u16 = 0; // colour 0 at the top of the frame (model `bg`)

/// A new frame: nothing written yet, colour 0 is `bg` from the top.
pub fn begin(bg: u16) void {
    @memset(&count, 0);
    @memset(&start_set, false);
    top = bg;
}

/// One move.w to colour 0, at cycle `rel` after a kernel's sync.
pub fn emit(l0: u32, rel: u32, v: u16) void {
    const k = rel + 177;
    const st = l0 + (k >> 9);
    const cx: i32 = @intCast(k & 511);
    if (st < 23) return;
    const y = st - 23;
    const px = cx - 9;
    if (px < 0) return startColour(y, v);
    if (px >= W) return startColour(y + 1, v);
    if (y >= LINES) return;
    const n = count[y];
    if (n < SLOTS) list[y][n] = (@as(u32, @intCast(px)) << 16) | v;
    count[y] = n +| 1;
}

fn startColour(y: u32, v: u16) void {
    if (y >= LINES) return;
    start_set[y] = true;
    start_col[y] = v;
}

/// The global HBL for physical line `line`: the line's starting colour, then its
/// writes. A line with neither keeps colour 0 as the last one left it.
pub fn hbl(zigos: *zg.ZigOS, line: u16) void {
    if (line >= LINES) return;
    if (start_set[line]) {
        zigos.setBackgroundColor(stColor(start_col[line]));
    } else if (line == 0) {
        zigos.setBackgroundColor(stColor(top));
    }
    const n = count[line];
    if (n == 0) return;
    zg.beam.begin();
    for (list[line][0..@min(n, SLOTS)]) |e| zg.beam.write(@intCast(e >> 16), @truncate(e));
    // Past 64 a write has no slot; the beam still counts it, as a drop.
    if (n > SLOTS) for (SLOTS..n) |_| zg.beam.write(0, 0);
}

/// An ST/STE colour word as the machine converts it (machine/beam.zig
/// stToRgba): each nibble is 3 bits plus the STE LSB in bit 3, level x 16.
pub fn stColor(w: u16) zg.Color {
    return .{ .r = gun(w >> 8), .g = gun(w >> 4), .b = gun(w), .a = 255 };
}

fn gun(n: u16) u8 {
    return @intCast((((n & 7) << 1) | ((n >> 3) & 1)) * 16);
}

pub fn reset() void {
    begin(0);
}
