// --------------------------------------------------------------------------
// The parrot photo as an 8-bit texture, shared by ZIGGY's ROTO (the CPU's
// rotozoom) and CHISEL V2's AFFINE rotozoom, Mode 7 floor and MAP tunnel.
// Adrian Pingstone's scarlet macaw, public domain (README.txt beside this file).
// The bytes come from tools/parrot_tex.py (build-time: a 400x400 crop on the head,
// LANCZOS to 64/128/256, ONE 192-colour median-cut palette for the three sizes, no
// dither); this file only embeds them. Indices 56..247: free in both carts (ZIGGY's
// HUD keeps 254/255; CHISEL V2 uses 0..2, 16..31, 40..43, 50).
// --------------------------------------------------------------------------
const zg = @import("zigos");

pub const BASE: u8 = 56; // the first palette index the photo uses
pub const COLOURS: usize = 192;
pub const BYTES: usize = 64 * 64 + 128 * 128 + 256 * 256;

/// 64x64, then 128x128, then 256x256 indices (read-only: the ops only read texels).
pub const all: *const [BYTES]u8 = @embedFile("parrot_tex.bin");
const pal: *const [COLOURS * 3]u8 = @embedFile("parrot_pal.bin");

/// The side-2^log picture (log 6, 7 or 8), `side * side` bytes, row after row.
pub fn texture(log: u4) []const u8 {
    return switch (log) {
        6 => all[0 .. 64 * 64],
        7 => all[64 * 64 .. 64 * 64 + 128 * 128],
        else => all[64 * 64 + 128 * 128 ..],
    };
}

/// Install the photo's colours at BASE..BASE+COLOURS-1 (the rest of the palette untouched).
pub fn install(fb: *zg.LogicalFB) void {
    for (0..COLOURS) |k| {
        fb.setPaletteEntry(@intCast(BASE + k), .{ .r = pal[3 * k], .g = pal[3 * k + 1], .b = pal[3 * k + 2], .a = 255 });
    }
}
