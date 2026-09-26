// --------------------------------------------------------------------------
// The Shifter and the colour registers.
//
// present() turns the ST screen into the plane's palette indices 0..15 and
// latches the 17 palettes and the line each one starts on. The plane's HBL is
// then Timer B: on the first line of a band it writes all 16 colour registers,
// exactly the movem the original's $7C4 does. Nothing is painted as pixels.
//
// Every band sets colour 0 as well, and on an ST colour 0 IS the border, so the
// grey bands and the bar run edge to edge. The plane is 320 wide, so the border
// is the machine background, set per physical line by a global HBL from
// border[]. The host paints the border (hwClear) BEFORE the cart's frame, so
// border[] is built from the state the NEXT frame presents (see stcs_css3.zig).
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const A = @import("assets.zig");
const machine = @import("machine.zig");
const raster = @import("raster.zig");
const Machine = machine.Machine;

const LINES: usize = 200;
const ROWS: usize = zg.PHYSICAL_HEIGHT;
const TOP: usize = zg.VERTICAL_BORDERS_HEIGHT; // physical row of line 0
const PALETTES: usize = raster.NBLOCKS + 1;

/// What the plane's HBL plays back: the latched palettes as RGBA, and the
/// palette each line shows (0 = top, i + 1 = block i).
var shown: [PALETTES][16]u32 = undefined;
var shown_line: [LINES]u8 = undefined;
/// Colour 0 per physical row for the NEXT frame's border.
var border: [ROWS]u32 = undefined;

/// One plane byte -> eight pixels, one byte lane each, MSB = leftmost pixel.
const SPREAD: [256]u64 = blk: {
    @setEvalBranchQuota(4000);
    var t: [256]u64 = undefined;
    for (0..256) |b| {
        var v: u64 = 0;
        for (0..8) |k| v |= @as(u64, (b >> (7 - k)) & 1) << (8 * k);
        t[b] = v;
    }
    break :blk t;
};

/// The screen through the colour registers. `lit` is false before the
/// picture: the program set all 16 registers to 0 and Timer B is not running.
pub fn present(m: *const Machine, lit: bool, fb: *zg.LogicalFB) void {
    latch(m, lit, &shown, &shown_line);
    const pixels = fb.fb[0 .. @as(usize, fb.stride) * LINES];
    for (0..LINES) |y| {
        const src = machine.screen[y * A.LINE ..][0..A.LINE];
        const dst = pixels[y * fb.stride ..][0..zg.WIDTH];
        for (0..A.LINE / 4) |h| {
            const g = (h >> 1) * 8 + (h & 1);
            const v = SPREAD[src[g]] | SPREAD[src[g + 2]] << 1 |
                SPREAD[src[g + 4]] << 2 | SPREAD[src[g + 6]] << 3;
            std.mem.writeInt(u64, dst[h * 8 ..][0..8], v, .little);
        }
    }
}

/// The border rows for the state `m` holds: top border = the top palette's
/// colour 0 (the VBL installs it), bottom border = the last line's.
pub fn buildBorder(m: *const Machine, lit: bool) void {
    var pals: [PALETTES][16]u32 = undefined;
    var line: [LINES]u8 = undefined;
    latch(m, lit, &pals, &line);
    @memset(border[0..TOP], pals[0][0]);
    for (line, 0..) |p, y| border[TOP + y] = pals[p][0];
    @memset(border[TOP + LINES ..], pals[line[LINES - 1]][0]);
}

fn latch(m: *const Machine, lit: bool, pals: *[PALETTES][16]u32, line: *[LINES]u8) void {
    if (!lit) {
        for (pals) |*p| @memset(p, stColor(0));
        @memset(line, 0);
        return;
    }
    for (pals, 0..) |*p, i| {
        for (p, 0..) |*c, r| c.* = stColor(raster.colour(m, i, r));
    }
    raster.lineBlocks(m, line);
}

/// Timer B: the band's 16 registers on its first line (and the top palette on
/// line 0, as the VBL installs it).
pub fn timerB(fb: *zg.LogicalFB, zigos: *zg.ZigOS, hbl_line: u16, col: u16) void {
    _ = zigos;
    _ = col;
    const y: usize = if (fb.hblLinesArePhysical()) @as(usize, hbl_line) -% TOP else hbl_line;
    if (y >= LINES) return;
    if (y != 0 and shown_line[y] == shown_line[y - 1]) return;
    @memcpy(fb.palette[0..16], &shown[shown_line[y]]);
}

/// Global HBL, physical rows 0..279: the border is colour 0.
pub fn borderHbl(zigos: *zg.ZigOS, row: u16) void {
    zigos.setBackgroundColor(zg.Color.fromRGBA(border[@min(row, ROWS - 1)]));
}

/// An ST colour register ($0RGB, three bits a gun, as on an STF) as RGBA.
pub fn stColor(word: u16) u32 {
    const r: u32 = gun(word >> 8);
    const g: u32 = gun(word >> 4);
    const b: u32 = gun(word);
    return (0xFF << 24) | (b << 16) | (g << 8) | r;
}

fn gun(nibble: u16) u32 {
    return @as(u32, nibble & 7) * 255 / 7;
}
