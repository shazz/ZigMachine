// --------------------------------------------------------------------------
// Part 5 ($1200..$17F0): the texture-mapped twister ($E094) and the greetings.
//
// The texture is the 512x64 chrome strip: 64 "angles" of an 8-px slice. Each
// 4-px screen column picks an angle from two sine waves, and the precalc
// ($E6D4) merges pixel PAIRS from two neighbouring angles into two 128 KB
// tables (T1 for pixels 0-1 / 2-3, T2 for 4-5 / 6-7), so a movep.l blit can
// assemble 8 pixels from 4 table longs. The tables are a pure function of the
// strip, so they are evaluated here per long instead of being held in 256 KB.
// Double buffered: draw into $CA5C, show it, swap.
// --------------------------------------------------------------------------
const A = @import("assets.zig");
const st = @import("st.zig");
const Screen = st.Screen;

pub const START: u32 = 0x1200;
pub const END: u32 = 0x17F0;
pub const FADE_OUT: u32 = 0x17D0;

/// $B791A[r][g]: the four plane bytes of 8-pixel group g of strip line r.
inline fn texel(r: usize, g: usize) u32 {
    const line = A.chrome[r * 256 ..];
    return (@as(u32, line[g]) << 24) | (@as(u32, line[64 + g]) << 16) |
        (@as(u32, line[128 + g]) << 8) | line[192 + g];
}

/// T1 / T2 at byte offset e + 4r: pass = e >> 14 picks the neighbour angle.
inline fn table(e: u32, r: usize, comptime own: u32, comptime next: u32) u32 {
    const g: usize = (e >> 8) & 63;
    const g2: usize = (g + (e >> 14) + 61) & 63; // (g + pass - 3) & 63
    return (texel(r, g) & own) | (texel(r, g2) & next);
}

/// y = (SIN[4f] * 55 + $4000) >> 8, a 256-frame bob between lines 9 and 119.
pub fn ypos(f: u16) usize {
    const s: u32 = @as(u16, @bitCast(@as(i16, @intCast(A.sin((@as(usize, f) * 4) & 1023)))));
    return (((s *% 0x37) +% 0x4000) & 0xFFFF) >> 8 & 0x7F;
}

/// The 80 column entries: pass * $4000 + angle * $100.
fn entries(f: u16, e: *[80]u32) void {
    const ff: u32 = f;
    const b1: usize = ((ff *% 7) & 0x7FE) / 2;
    const b2: usize = ((0 -% ff *% 4) & 0x7FE) / 2;
    for (e, 0..) |*out, i| {
        const a = A.sin(b1 + 2 * i);
        const b = A.sin(b1 + 2 * i + 1);
        const c = A.sin(b2 + i);
        const col: u32 = @as(u32, @bitCast(a + c)) & 0x3F;
        const pass: u32 = @as(u32, @bitCast(b - a + 3)) & 7;
        out.* = pass * 0x4000 + col * 0x100;
    }
}

/// $E094's twister for frame f: 4 erase lines above and below, 64 texture rows.
pub fn draw(s: *Screen, f: u16) void {
    const y = ypos(f);
    for ([_]usize{ 0, 1, 2, 3, 68, 69, 70, 71 }) |l| @memset(s[(y + l) * st.LINE ..][0..st.LINE], 0xFF);
    var e: [80]u32 = undefined;
    entries(f, &e);
    for (0..20) |blk| {
        const q = e[blk * 4 ..][0..4];
        for (0..64) |r| {
            const ev = table(q[0], r, 0xC0C0C0C0, 0x30303030) | table(q[1], r, 0x0C0C0C0C, 0x03030303);
            const od = table(q[2], r, 0xC0C0C0C0, 0x30303030) | table(q[3], r, 0x0C0C0C0C, 0x03030303);
            const o = (y + 4 + r) * st.LINE + blk * 8;
            inline for (0..4) |p| { // movep.l: byte p -> plane p
                s[o + 2 * p] = @truncate(ev >> (24 - 8 * p));
                s[o + 2 * p + 1] = @truncate(od >> (24 - 8 * p));
            }
        }
    }
}

/// The greeting for `counter`: slot (counter - $1200) / 96, 8 lines of a
/// 224-px 1-bit bitmap written to all four planes, top on even slots (lines
/// 1..8), bottom on odd ones (191..198). Nothing erases a name but the next.
pub fn greeting(s: *Screen, counter: u32) void {
    const idx: usize = ((counter - START) / 0x60) & 0xFFFF;
    const y = 1 + (idx & 1) * 190;
    for (0..8) |r| {
        for (0..14) |w| {
            const src = idx * 0xE0 + r * 28 + w * 2;
            const o = (y + r) * st.LINE + 0x18 + w * 8;
            for (0..4) |p| {
                s[o + 2 * p] = A.greet[src];
                s[o + 2 * p + 1] = A.greet[src + 1];
            }
        }
    }
}

/// $BB3C / $BB7A: the palette is a 16-word window into the 32 at $14420,
/// colour 0 forced black. Returns the window's first entry, or null to leave
/// the palette alone.
pub fn fadeWindow(f: u16, counter: u32) ?u32 {
    var w: ?u32 = null;
    if (f <= 0x20) w = ((0x20 - @as(u32, f)) & 0x3E) / 2; // in: one step every 2 frames
    if (counter >= FADE_OUT) w = ((counter - FADE_OUT) & 0x1E) / 2; // out
    return w;
}
