// --------------------------------------------------------------------------
// F2's precalculation ($800..$D20 of B_SPRITE.BIN, loaded at $800), as the
// 68000 does it, into the same addresses: the tiled background on both screens
// and the picture the erase copies from, the sprite's fifteen preshifts and
// its sixteen masks. prototypes/naos_nitrowave_re/bspr_model.py is the same,
// and equals Hatari's RAM.
// --------------------------------------------------------------------------
const st = @import("st.zig");

pub const LINE: u32 = 230;
const TILE: u32 = 0x107B6; // 32 x 64 pixels, 32 bytes a row
const BUILT: u32 = 0x6AE86; // screen B's line 1 (+160 +230)
const BLOCK: u32 = 0x3980; // 64 lines
const COPY: usize = 2 * 0x7300; // 256 lines
pub const GFX0: u32 = 0x10FB6; // the sprite, 144 x 80, 72 bytes a line
const SHIFT0: u32 = 0x17BA2; // preshifts 1..15, each the last moved right a pixel
pub const MASK0: u32 = 0x2CD22; // 16 masks, 36 bytes a line
pub const SPRITE_BYTES: u32 = 0x1680;
const MASK_BYTES: u32 = 0xB40;
pub const LINES = 80;
pub const GROUPS = 9;

/// $86C..$8E2: the tile seven times a line ($6AE86 is screen B's line 1),
/// that 64-line block four times down; then copied to screen A ($5C386) and
/// the picture ($4D886).
pub fn background(r: *const st.Ram) void {
    for (0..64) |row| {
        const rr: u32 = @intCast(row);
        for (0..7) |k| r.cp(BUILT + LINE * rr + 32 * @as(u32, @intCast(k)), TILE + 32 * rr, 32);
    }
    for (1..4) |k| r.cp(BUILT + BLOCK * @as(u32, @intCast(k)), BUILT, BLOCK);
    r.cp(0x5C386, BUILT, COPY);
    r.cp(0x4D886, BUILT, COPY);
}

/// $8E6..$D20: preshift k is k pixels right of the sprite; mask k is, per
/// 16-pixel group, NOT(plane0 | plane1 | plane2 | plane3), written twice.
pub fn sprites(r: *const st.Ram) void {
    var prev = GFX0;
    for (0..15) |k| {
        const dst = SHIFT0 + SPRITE_BYTES * @as(u32, @intCast(k));
        r.cp(dst, prev, SPRITE_BYTES);
        shiftRight(r, dst);
        prev = dst;
    }
    for (0..16) |k| mask(r, preshift(@intCast(k)), MASK0 + MASK_BYTES * @as(u32, @intCast(k)));
}

/// The address of preshift k (0 = the sprite as the file holds it).
pub fn preshift(k: u32) u32 {
    return if (k == 0) GFX0 else SHIFT0 + SPRITE_BYTES * (k - 1);
}

fn mask(r: *const st.Ram, src: u32, dst: u32) void {
    for (0..LINES * GROUPS) |g| {
        const gg: u32 = @intCast(g);
        var v: u16 = 0;
        for (0..4) |p| v |= r.w(src + 8 * gg + 2 * @as(u32, @intCast(p)));
        r.sw(dst + 4 * gg, ~v);
        r.sw(dst + 4 * gg + 2, ~v);
    }
}

/// $1E36: lsr.w the first word of each plane of each line, roxr.w the other
/// eight: one pixel right, the carry crossing from group to group.
fn shiftRight(r: *const st.Ram, a0: u32) void {
    for (0..LINES) |line| {
        for (0..4) |p| {
            var carry: u16 = 0;
            for (0..GROUPS) |g| {
                const a = a0 + 72 * @as(u32, @intCast(line)) + 2 * @as(u32, @intCast(p)) + 8 * @as(u32, @intCast(g));
                const v = r.w(a);
                r.sw(a, (v >> 1) | (carry << 15));
                carry = v & 1;
            }
        }
    }
}
