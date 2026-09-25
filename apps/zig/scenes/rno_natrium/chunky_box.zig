// --------------------------------------------------------------------------
// Parts 2 and 7: the 80x80-cell chunky box. A cell is 2 px wide and 2 lines
// tall, but each call writes ONE field (lines 20 + 2r + p), so the two lines
// of a cell are always one call apart. Only planes 2 and 3 are written: seven
// shades from pens 0/4/8/12 by horizontal dither ($56492's table).
//
//   $DDEC tunnel   (part 2)  skin texture through the 160x100 offset table
//   $D7F6 wobble   (part 2)  face texture, per-column + per-row sine shifts
//   $DB14 rotozoom (part 7)  skin texture, INCLUDING the original's V0 bug
//
// The integer math is the reference model's (re/chunky/ref.py), which matched
// the Hatari snapshots byte for byte; the 68000's movep/C2P arrays are just a
// fast way to write what writeRow() writes.
// --------------------------------------------------------------------------
const A = @import("assets.zig");
const st = @import("st.zig");
const Screen = st.Screen;

pub const CELLS = 80;
pub const TOP = 20; // first box line
pub const GROUP_LEFT = 1; // x = 16 (part 2)
pub const GROUP_RIGHT = 9; // x = 144 (part 7)

inline fn w16(x: i64) u32 {
    return @as(u32, @truncate(@as(u64, @bitCast(x)))) & 0xFFFF;
}
inline fn s16(x: u32) i32 {
    return @as(i16, @bitCast(@as(u16, @truncate(x))));
}

/// $56492 row k, entry c: the plane-2 (high byte) and plane-3 (low byte) bits
/// of cell k of a movep byte.
inline fn lut(k: usize, c: u8) u16 {
    return A.be16(A.chunky_lut, k * 8 + (c & 7));
}

/// One field line of 80 cells into planes 2 and 3 from group `g0`.
pub fn writeRow(s: *Screen, line: usize, g0: usize, cells: *const [CELLS]u8) void {
    const base = line * st.LINE + g0 * 8;
    for (0..10) |g| {
        var hi: u16 = 0;
        var lo: u16 = 0;
        for (0..4) |k| {
            hi |= lut(k, cells[g * 8 + k]);
            lo |= lut(k, cells[g * 8 + 4 + k]);
        }
        const o = base + g * 8;
        s[o + 4] = @truncate(hi >> 8); // movep.w d, 4(a5): plane 2, left byte
        s[o + 6] = @truncate(hi);
        s[o + 5] = @truncate(lo >> 8); // movep.w d, 5(a5): the right byte
        s[o + 7] = @truncate(lo);
    }
}

/// $144C8 after the $C308 conversion: a byte offset v*256 + u*2, 0 = the hole.
inline fn tunnelOffset(i: usize) u32 {
    const o: u32 = (@as(u32, A.tunnel_map[2 * i + 1]) << 8) | A.tunnel_map[2 * i]; // little-endian in TEXT
    return ((o >> 9) << 8) | (o & 0xFE);
}

/// $DDEC: one field of the tunnel for frame f.
pub fn tunnel(s: *Screen, f: u16, p: u1) void {
    const ff: u32 = f;
    const base = ((ff & 0x7F) << 8) | (ff & 0xFE); // v += 1, u += 0.5 per frame
    const d3 = w16(@as(i64, w16(A.sin((ff * 3) & 0x3FF) * 0x28)) + 0x2800);
    const xpan = (d3 >> 7) & 0xFE; // bytes into a 320-byte table row
    const d4 = w16(@as(i64, w16(A.sin((ff * 4) & 0x3FF) * 0x0A)) + 0x0A00);
    const ypan = (d4 >> 8) & 0x1F;
    var cells: [CELLS]u8 = undefined;
    for (0..CELLS) |r| {
        const row = (ypan + r) * 160 + xpan / 2;
        for (&cells, 0..) |*c, col| {
            const off = tunnelOffset(row + col);
            // The hole: the original zeroes the four arrays' word at `base` for
            // the call, so an offset of 0 reads black.
            c.* = if (off == 0) 0 else A.tex_skin[((base + off) >> 1) & 0x3FFF];
        }
        writeRow(s, TOP + 2 * r + p, GROUP_LEFT, &cells);
    }
}

/// $D7F6: the face wobble for frame f. Always draws the front buffer's box.
pub fn wobble(s: *Screen, f: u16, p: u1) void {
    const ff: u32 = f;
    var disp: [CELLS]i32 = undefined;
    var d1 = (ff *% 0x11) & 0x7FE;
    var d2 = (ff *% 0xFFF5) & 0x7FE;
    for (&disp, 0..) |*d, c| {
        const w = w16(@as(i64, s16(w16(A.sin(d1 >> 1) + A.sin(d2 >> 1)))) * 12);
        d.* = s16((w & 0xFF00) | ((0x30 + 2 * @as(u32, @intCast(c))) & 0xFF)); // hi = rows, lo = u byte
        d1 = (d1 + 0x0A) & 0x7FE;
        d2 = (d2 + 0x16) & 0x7FE;
    }
    d1 = (ff *% 0x0D) & 0x7FE;
    d2 = (ff *% 0xFFED) & 0x7FE;
    var cells: [CELLS]u8 = undefined;
    for (0..CELLS) |r| {
        const w = w16(@as(i64, s16(w16(A.sin(d1 >> 1) + A.sin(d2 >> 1)))) * 24);
        const shift: i32 = @intCast((w >> 8) & 0xFFFE); // LOGICAL shift: 0..254
        d1 = (d1 + 0x0E) & 0x7FE;
        d2 = (d2 + 0x12) & 0x7FE;
        const a: i32 = 0x1800 + @as(i32, @intCast(r)) * 0x100 + shift;
        for (&cells, disp) |*c, d| c.* = A.tex_face[(@as(u32, @bitCast(a + d)) >> 1) & 0x3FFF];
        writeRow(s, TOP + 2 * r + p, GROUP_LEFT, &cells);
    }
}

/// $DB14: the rotozoom for frame f, into the right-hand box.
pub fn rotozoom(s: *Screen, f: u16, p: u1) void {
    const ff: u32 = f;
    const d0 = (ff *% 3) & 0x7FE; // angle, byte offset
    const d1 = (ff *% 12) & 0x7FE; // zoom
    const z: i64 = w16(A.sin(d1 >> 1) * 4 + 0x480);
    // muls.w + lsr.l #8, low word kept
    const px: u32 = @truncate(@as(u64, @bitCast(A.sin(d0 >> 1) * z)));
    const py: u32 = @truncate(@as(u64, @bitCast(A.sin((d0 >> 1) + 256) * z)));
    const x: i64 = s16(px >> 8);
    const y: i64 = s16(py >> 8);
    const uu0 = w16(0x4000 - @as(i64, w16(y << 5)));
    // The ORIGINAL BUG, kept: d7.w is set to $4000 - 32X, then bsr $DD84 does
    // move.w #$7FFE,d7 -- so V0 is always $7FFE and only U is centred.
    const vv0: u32 = 0x7FFE;
    var cols: [CELLS]u32 = undefined;
    var u: u32 = 0;
    var v: u32 = 0;
    for (&cols) |*c| {
        c.* = ((v & 0xFF00) | (u >> 8)) & 0x7FFE;
        u = w16(@as(i64, u) + 2 * y);
        v = w16(@as(i64, v) + 2 * x);
    }
    var cells: [CELLS]u8 = undefined;
    for (0..CELLS) |r| {
        const l: i64 = 2 * @as(i64, @intCast(r)) + p;
        u = w16(@as(i64, uu0) - l * x);
        v = w16(@as(i64, vv0) + l * y);
        const rp = ((v & 0xFF00) | (u >> 8)) & 0x7FFE;
        for (&cells, cols) |*c, cd| c.* = A.tex_skin[((rp + cd) >> 1) & 0x3FFF];
        writeRow(s, TOP + 2 * r + p, GROUP_RIGHT, &cells);
    }
}
