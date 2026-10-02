// --------------------------------------------------------------------------
// F1's sprites (DEMO_RIC.BIN): a sprite is 48x30, three 16-pixel groups of
// planes 1..3 (plane 0 is the scroller's), masked in. Its place comes from a
// path of 6-byte entries (screen offset, gfx offset, mask offset), ended by
// $FFFF; every path variable starts over at the figure's path (*$782D2).
// Offsets below $2580 lie in the scroller's band, where only planes 1..3 are
// masked. prototypes/naos_nitrowave_re/ric_model.py is the same, = the
// original on Musashi over 5000 VBLs.
// --------------------------------------------------------------------------
const st = @import("st.zig");

pub const GFX: u32 = 0x47914; // the sprite sheet's base
pub const MASK: u32 = 0x47918; // the mask sheet's base
pub const WORK: u32 = 0x47936; // the screen being drawn
pub const BG: u32 = 0x4791C; // the clean background
pub const PATH: u32 = 0x782D2; // the figure's path
pub const STREAM: u32 = 0x782DA; // the precalculated planes of the third list
pub const STREAM_FIRST: u32 = 0xCBD4;
pub const STREAM_END: u32 = 0xBC614E;
const LIMIT: i32 = 0x2580;
const END: u16 = 0xFFFF;
const LINES = 30;

pub inline fn ws(r: *const st.Ram, a: u32) i32 {
    return @as(i16, @bitCast(r.w(a)));
}

pub inline fn add(base: u32, off: i32) u32 {
    return base +% @as(u32, @bitCast(off));
}

/// The entry a path variable points at, or the path's start at its end.
pub fn entry(r: *const st.Ram, path_var: u32) u32 {
    const a0 = r.l(path_var);
    return if (r.w(a0) == END) r.l(PATH) else a0;
}

/// Which planes a sprite's mask clears.
pub const Masked = enum { all, by_band };

/// $107C (and $152C for the set-up, which masks all four planes): the sprite
/// at *path_var, which moves on an entry.
pub fn draw(r: *const st.Ram, path_var: u32, masked: Masked) void {
    const a0 = entry(r, path_var);
    const at = ws(r, a0);
    r.sl(path_var, a0 + 6);
    const dst = add(r.l(WORK), at);
    const mask = add(r.l(MASK), ws(r, a0 + 4));
    if (masked == .all or at >= LIMIT) maskAll(r, dst, mask) else maskUpper(r, dst, mask);
    orGfx(r, dst, add(r.l(GFX), ws(r, a0 + 2)));
}

fn maskAll(r: *const st.Ram, dst: u32, mask: u32) void {
    for (0..LINES) |y| {
        const d = dst + 160 * @as(u32, @intCast(y));
        const k = mask + 160 * @as(u32, @intCast(y));
        var j: u32 = 0;
        while (j < 24) : (j += 4) r.sl(d + j, r.l(d + j) & r.l(k + j));
    }
}

fn maskUpper(r: *const st.Ram, dst: u32, mask: u32) void {
    for (0..LINES) |y| {
        const d = dst + 160 * @as(u32, @intCast(y));
        const k = mask + 160 * @as(u32, @intCast(y));
        var g: u32 = 0;
        while (g < 24) : (g += 8) {
            r.sl(d + g + 2, r.l(d + g + 2) & r.l(k + g + 2));
            r.sw(d + g + 6, r.w(d + g + 6) & r.w(k + g + 6));
        }
    }
}

/// Planes 1..3 of three groups OR the sheet's 6 bytes a group (120 a line).
fn orGfx(r: *const st.Ram, dst: u32, gfx: u32) void {
    for (0..LINES) |y| {
        const d = dst + 160 * @as(u32, @intCast(y));
        const s = gfx + 0x78 * @as(u32, @intCast(y));
        for (0..3) |gi| {
            const g: u32 = @intCast(gi);
            r.sl(d + 8 * g + 2, r.l(d + 8 * g + 2) | r.l(s + 6 * g));
            r.sw(d + 8 * g + 6, r.w(d + 8 * g + 6) | r.w(s + 6 * g + 4));
        }
    }
}

/// $116E: the background back under an old sprite (*$47928).
pub fn restore(r: *const st.Ram) void {
    const a0 = entry(r, 0x47928);
    const at = ws(r, a0);
    const scr = add(r.l(WORK), at);
    const bg = add(r.l(BG), at);
    for (0..LINES) |y| {
        const o = 160 * @as(u32, @intCast(y));
        if (at >= LIMIT) {
            r.cp(scr + o, bg + o, 24);
        } else for (0..3) |gi| {
            const g: u32 = 8 * @as(u32, @intCast(gi));
            r.cp(scr + o + g + 2, bg + o + g + 2, 6);
        }
    }
    r.sl(0x47928, a0 + 6);
}

/// $11F6: the third list (*$47924): a mask in the lower band only, then the
/// planes 1..3 the set-up kept for it, 18 bytes a line from *$782DA.
pub fn third(r: *const st.Ram) void {
    var a0 = r.l(STREAM);
    var a1 = r.l(0x47924);
    const at = ws(r, a1);
    const dst = add(r.l(WORK), at);
    if (at >= LIMIT) maskAll(r, dst, add(r.l(MASK), ws(r, a1 + 4)));
    a1 += 6;
    for (0..LINES) |y| {
        const d = dst + 160 * @as(u32, @intCast(y));
        for (0..3) |gi| {
            r.cp(d + 8 * @as(u32, @intCast(gi)) + 2, a0, 6);
            a0 += 6;
        }
    }
    r.sl(STREAM, if (r.l(a0) == STREAM_END) STREAM_FIRST else a0);
    r.sl(0x47924, if (r.w(a1) == END) r.l(PATH) else a1);
}
