// --------------------------------------------------------------------------
// The plane's colours: the C64's 16 (colodore, VICE's colodore.vpl) at palette indices 1..16,
// index 0 the line's border colour (a raster), and the colour groups' entries the sprites draw
// with (groups.zig), set from the colours of the frame they drew.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const groups = @import("groups.zig");
const cache = @import("vic_cache.zig");

pub const PALETTE = [16]u32{
    0x000000, 0xFFFFFF, 0x96282E, 0x5BD6CE, 0x9F2DAD, 0x41B936, 0x2724C4, 0xEFF347,
    0x9F4815, 0x5E3500, 0xDA5F66, 0x474747, 0x787878, 0x91FF84, 0x6864FF, 0xAEAEAE,
};

/// C64 colour `c` as the machine's palette word (0xRRGGBB -> A,B,G,R).
pub fn rgba(c: u8) u32 {
    const v = PALETTE[c & 15];
    return 0xFF00_0000 | ((v & 0xFF) << 16) | (v & 0xFF00) | (v >> 16);
}

/// The plane's fixed entries: 0 black until the first raster, 1..16 the C64's colours.
pub fn install(fb: *zg.LogicalFB) void {
    fb.setPaletteEntry(0, zg.Color.fromRGBA(rgba(0)));
    for (0..16) |c| fb.setPaletteEntry(@intCast(c + 1), zg.Color.fromRGBA(rgba(@intCast(c))));
}

/// The groups' entries for the frame `g` drew (only the entries that change are written).
pub fn setGroups(fb: *zg.LogicalFB, g: *const groups.Groups) void {
    for (0..groups.GROUPS) |i| {
        if (g.used & (@as(u16, 1) << @intCast(i)) == 0) continue;
        for (0..3) |code| {
            const e = cache.FIRST + 4 * i + 1 + code;
            const v = rgba(g.colours[i][code]);
            if (fb.palette[e] != v) fb.palette[e] = v;
        }
    }
}
