// --------------------------------------------------------------------------
// The original's data, ripped from COMFORT_unpacked.PRG by tools/falcon_ays_art.py into
// apps/zig/assets/screens/falcon_ays/ (published with the port, Matt 3 Nov 2026). Every slice is
// the exact size its part expects, except credit_4: the MUSIC name picture's Pack-Ice stream does
// not depack (ANALYSIS.md), so that slice is empty and the part draws its generated stand-in.
// Big-endian words stay big-endian (the Falcon's): parts read be16.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const ays_art = @import("ays_art");

/// The rip's fingerprint (the md5 of the program it came from).
pub const marker: []const u8 = ays_art.marker;
pub const present = marker.len > 0;

pub const blob_field: []const u8 = ays_art.blob_field; // DATA $38F2C, 320x200 bytes 0..127
pub const blob_tear: []const u8 = ays_art.blob_tear; // DATA $5AAAC: 1024 BE u16, the tear band's row x 320
pub const blob_luts: []const u8 = ays_art.blob_luts; // DATA $4992C..$4AF2C: six BE 565 LUTs, $400 apart
pub const text_font: []const u8 = ays_art.text_font; // DATA $EC1EC: 59 glyphs ' '..'Z', 16x32 bytes 0..$72
pub const text_pal: []const u8 = ays_art.text_pal; // DATA $F37EC: 128 BE 565 words, black -> red -> white
pub const ship: []const u8 = ays_art.ship; // DATA $F3956: 320x200 BE 565 (after a 6-byte header)
pub const flame_tex_a: []const u8 = ays_art.flame_tex_a; // DATA $A9C6C: 256x256 BE 565 fireball (texA)
pub const flame_tex_b: []const u8 = ays_art.flame_tex_b; // DATA $C9C6C: 256x256 BE 565 halftone (texB)
pub const flame_map_a: []const u8 = ays_art.flame_map_a; // DATA $6B46C: 320x150 BE u16 v<<8|u, smooth warp
pub const flame_map_b: []const u8 = ays_art.flame_map_b; // DATA $8A86C: 320x150 BE u16, warp + turbulence
pub const flame_path: []const u8 = ays_art.flame_path; // DATA $E9C6C: 1024 BE u16 v<<8|u offsets
pub const flame_caption: []const u8 = ays_art.flame_caption; // DATA $EA46C: 320x22 bytes, non-zero = ink
pub const chos_flares: []const u8 = ays_art.chos_flares; // DATA $DB24: 12 flare frames, 320x43 bytes 0..63
pub const chos_logo: []const u8 = ays_art.chos_logo; // DATA $36024: 160x44 bytes, 0/127
pub const chos_offsets: []const u8 = ays_art.chos_offsets; // DATA $37BA4: 1024 BE u16 flare x offsets
pub const chos_lut: []const u8 = ays_art.chos_lut; // DATA $383B0: 256 BE 565 words
pub const plaque_code: []const u8 = ays_art.plaque_code; // DATA $13A606: 'G4', w, h, then BE 565
pub const plaque_graphics: []const u8 = ays_art.plaque_graphics; // DATA $13C95C
pub const plaque_music: []const u8 = ays_art.plaque_music; // DATA $137D10
// The five name pictures, depacked (Pack-Ice in DATA), first 200 rows, BE 565; credit 4 empty.
pub const credit_1: []const u8 = ays_art.credit_1;
pub const credit_2: []const u8 = ays_art.credit_2;
pub const credit_3: []const u8 = ays_art.credit_3;
pub const credit_4: []const u8 = ays_art.credit_4;
pub const credit_5: []const u8 = ays_art.credit_5;
pub const env_grey: []const u8 = ays_art.env_grey; // DATA $11A3BE: 64x64 BE 565 (after a 16-byte WordPerPixel header)
pub const env_orange: []const u8 = ays_art.env_orange; // DATA $11C3D2: 64x64 BE 565
pub const thanks: []const u8 = ays_art.thanks; // DATA $1173D6: two 320x8 byte strips, 0..127
pub const thanks_ramp: []const u8 = ays_art.thanks_ramp; // DATA $1187D6: 256 BE 565
pub const greets: []const u8 = ays_art.greets; // DATA $112D56: 1000x8 BE 565
pub const greets_path: []const u8 = ays_art.greets_path; // DATA $116BD6: 1024 BE u16 byte offsets
pub const rg_letters: []const u8 = ays_art.rg_letters; // DATA $5B2AC: 320x65 bytes 0..127, halftone 'reservoirgods'
pub const rg_field: []const u8 = ays_art.rg_field; // DATA $603EC: radial halftone field, 640 wide
pub const rg_sway: []const u8 = ays_art.rg_sway; // DATA $6AC6C: 1024 BE u16 x offsets 1..318
pub const rg_lut: []const u8 = ays_art.rg_lut; // DATA $6A86C: 512 BE 565
pub const flash_ramp: []const u8 = ays_art.flash_ramp; // DATA $EBFEC: 128 BE longs, 565 doubled (81A/81B)

pub fn be16(b: []const u8, off: usize) u16 {
    return @as(u16, b[off]) << 8 | b[off + 1];
}

/// Say which rip the cart carries.
pub fn announce() void {
    if (present) zg.Console.log("falcon_ays: local rip [{s}]", .{marker});
}
