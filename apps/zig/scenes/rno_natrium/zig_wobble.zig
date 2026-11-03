// --------------------------------------------------------------------------
// NATRIUM ZIG mode, part 2: the $D7F6 face wobble over the whole overscan
// window, drawn by ZIGGY itself: a texel a 3x3-pixel cell, every cell every
// frame (the original: 2x2 cells, 80x80 of them, one field a call).
//
// The original's two displacements, continued past its box:
//   per column c  rows(c)  = (SIN[17f/2 + 5c] + SIN[-11f/2 + 11c]) * 12 >> 8
//   per row r     shift(r) = (SIN[13f/2 + 7r] + SIN[-19f/2 + 9r]) * 24 >> 9, mod 128
// and cell (c, r) reads the face at U = 24 + c + shift(r), V = 24 + r + rows(c).
// That is not affine (V depends on the column, U on the row), so it is a CPU
// job, and the job ZM-X's tex2d is for: one instruction turns the Q16 (U, V)
// into the 128x128 texel index, from a face (16 KB) that stays in ZIGGY's D$.
// A band of 3 lines is built once as 100 words (4 cells = 3 words) and stored
// to its 3 lines; then the girl panel goes back on with one blit.
// f is the part's VBL count with the frame's fraction (Q10, zig_mode.zig).
// --------------------------------------------------------------------------
const zg = @import("zigos");
const trig = zg.fixtrig;
const zmx = @import("rom_sdk").zmx;
const R = @import("zig_res.zig");

pub const CELL: usize = 3;
const COLS: usize = 136; // cells across 408 px: 34 groups of 4
const BANDS: usize = (R.H + CELL - 1) / CELL; // 94
/// The original's 80x80 cells sit at cells (27..106, 7..86) of the window.
const C0: i32 = -27;
const R0: i32 = -7;
const DIMS: u32 = (7 - 3) | (7 - 3) << 3; // tex2d funct7: 128 x 128 (libs/zig/zmx.zig texDims)

const Q: u32 = 1 << 16;
const IDX: u32 = 1 << 22; // a SIN index (1024 a turn) as a fixtrig angle

/// The displacement sum at angles a1, a2, Q16 (two SINs of 65536).
inline fn sum(a1: u32, a2: u32) i32 {
    return trig.sin(a1) + trig.sin(a2);
}

/// rows(c) for every column at time t, as Q16 V offsets (24 + rows).
fn columns(t: u32, vq: *[COLS]u32) void {
    var a1: u32 = t *% (17 << 11) +% @as(u32, @bitCast(C0 * 5)) *% IDX;
    var a2: u32 = t *% @as(u32, @bitCast(@as(i32, -11) << 11)) +% @as(u32, @bitCast(C0 * 11)) *% IDX;
    for (vq) |*v| {
        const rows: i32 = (sum(a1, a2) * 12) >> 16;
        v.* = @as(u32, @bitCast(24 + rows)) << 16;
        a1 +%= 5 * IDX;
        a2 +%= 11 * IDX;
    }
}

/// shift(r) at time t for row r (cells), texels 0..127.
pub fn shiftAt(t: u32, r: i32) u32 {
    const a1 = t *% (13 << 11) +% @as(u32, @bitCast(r * 7)) *% IDX;
    const a2 = t *% @as(u32, @bitCast(@as(i32, -19) << 11)) +% @as(u32, @bitCast(r * 9)) *% IDX;
    return @as(u32, @bitCast((sum(a1, a2) * 24) >> 17)) & 127;
}

/// Groups (12 px) wholly under the girl panel (x 247..344), skipped on the bands
/// wholly under it (lines 42..239): the panel's blit covers them anyway.
const PANEL_G0 = 21;
const PANEL_G1 = 28;
const PANEL_J0 = 14;
const PANEL_J1 = 80;

/// One band: the cells of row r, each word stored straight to the band's lines
/// (4 cells = 3 words; the last group's first word ends the 100).
fn band(face: []const u8, vq: *const [COLS]u32, r: i32, shift: u32, rows: [CELL][*]u32, panel: bool) void {
    const rq: u32 = @as(u32, @bitCast(r)) << 16;
    var u: u32 = (@as(u32, @bitCast(24 + C0)) +% shift) << 16;
    var w: usize = 0;
    for (0..COLS / 4) |g| {
        if (panel and g >= PANEL_G0 and g < PANEL_G1) {
            u +%= 4 * Q;
            w += 3;
            continue;
        }
        var t: [4]u32 = undefined;
        inline for (0..4) |k| {
            t[k] = face[zmx.zmTex2d(u, vq[4 * g + k] +% rq, DIMS)];
            u +%= Q;
        }
        const words = [3]u32{ t[0] * 0x010101 | t[1] << 24, t[1] * 0x0101 | t[2] * 0x01010000, t[2] | t[3] * 0x01010100 };
        inline for (0..3) |k| {
            if (k == 0 or w + k < R.W / 4) {
                inline for (rows) |row| row[w + k] = words[k];
            }
        }
        w += 3;
    }
}

pub fn draw(fb: *zg.LogicalFB, t: u32) void {
    var vq: [COLS]u32 = undefined;
    columns(t, &vq);
    const px: [*]u32 = @ptrCast(@alignCast(fb.fb));
    const stride = fb.stride / 4;
    for (0..BANDS) |j| {
        const r: i32 = @as(i32, @intCast(j)) + R0;
        var rows: [CELL][*]u32 = undefined;
        // the last band has one line: its other two stores land on that line again
        for (&rows, 0..) |*row, k| row.* = px + @min(j * CELL + k, R.H - 1) * stride;
        band(R.face, &vq, r, shiftAt(t, r), rows, j >= PANEL_J0 and j < PANEL_J1);
    }
    R.panel(fb, R.PANEL_P2);
}
