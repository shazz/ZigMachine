// --------------------------------------------------------------------------
// The RG ship (8xx 20; Falcon main $6B58): SH3's rendered 320x200 true-colour picture (DATA
// $F3950: a 6-byte header, then big-endian RGB565, the blue radial background baked in),
// copied to the screen every frame, with a vertical bounce from the VBL (the BOUNCE table on
// VDB/VDE, screen.zig). Here the picture goes into both buffers once and the bounce moves the
// line list. The white-yellow "light beam" before it is not this part: it is 822 pushing the
// gold blobs (80F) to the top of their LUT, then 823's white.
//
// With the local rip it is the original picture; otherwise a stand-in: the blue radial
// gradient and a plain lettered plaque where the ship would be.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const art = @import("art.zig");
const tc = zg.tc;

const W = 320;
const H = 200;

pub fn paint(fb: tc.Fb, font: []const u8) void {
    if (art.ship.len == W * H * 2) {
        for (0..H) |y| for (0..W) |x| {
            fb.pixels[y * fb.stride + x] = art.be16(art.ship, (y * W + x) * 2);
        };
        return;
    }
    // Stand-in: concentric rings of blue around the centre (the original's background).
    for (0..H) |y| for (0..W) |x| {
        const dx: u32 = @intCast(@abs(@as(i32, @intCast(x)) - 160));
        const dy: u32 = @intCast(@abs(@as(i32, @intCast(y)) - 100));
        const r = (dx * dx + dy * dy) >> 7; // 0..~280
        const band: u32 = (r / 24) & 1; // the faint rings
        const b: u32 = 220 -| r / 3 -| band * 6;
        const g: u32 = 90 -| r / 6;
        fb.pixels[y * fb.stride + x] = tc.rgb565(40, @intCast(g), @intCast(b));
    };
    plaque(fb, font, "RESERVOIR GODS", 104, 92);
}

// The stand-in's label: the 8x8 system font at 2x, pink on green, as the ship's colours.
fn plaque(fb: tc.Fb, font: []const u8, s: []const u8, x0: usize, y0: usize) void {
    const pink = tc.rgb565(232, 160, 192);
    const green = tc.rgb565(60, 170, 90);
    for (y0 - 4..y0 + 20) |y| for (x0 - 6..x0 + s.len * 8 + 6) |x| {
        fb.pixels[y * fb.stride + x] = green;
    };
    for (s, 0..) |ch, k| for (0..16) |y| for (0..8) |x| {
        if (font.len < (@as(usize, ch) + 1) * 64) continue;
        if (font[@as(usize, ch) * 64 + (y / 2) * 8 + x] != 0) fb.pixels[(y0 + y) * fb.stride + x0 + k * 8 + x] = pink;
    };
}
