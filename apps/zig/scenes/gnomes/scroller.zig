// --------------------------------------------------------------------------
// The big scroller ($13AFE): the 2885-character French text in the 32x25
// four-plane font, on ST lines 251..275. Each glyph is four 8-px columns
// (movep.l records of 25 rows); the loop appends one column a frame and the
// two screen buffers each shift by 16 px every other frame, so the text moves
// 8 px a frame and a new character starts every 4 frames. In frame n the 40
// visible 8-px columns are stream columns n-39 .. n, where column k is column
// k % 4 of the glyph of text[k / 4 - 1] (k < 4: the space glyph, the column
// $19E48 starts on; k < 0: the cleared screen).
//
// Here the strip is drawn whole every frame: the 10 or 11 glyphs it shows,
// each one 32x25 CHISEL copy from the font in cart RAM, clipped to the screen.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const blit = zg.blit;
const A = @import("assets.zig");
const text = @import("text.zig");

pub const Y = 251; // ST line ($9CE0 / 160)
const H = 25;
const GW = 32;

const font = blit.Image.init(&A.font32, GW);

/// The glyph of text character `k` (-1: the space the stream starts on).
fn glyphOf(k: i32) usize {
    if (k < 0) return 0;
    const ch = text.BIG_TEXT[@as(usize, @intCast(k)) % text.BIG_TEXT.len];
    return A.FONT32_MAP[ch - 0x20];
}

/// The leftmost stream column on screen in frame n.
pub fn firstColumn(n: u32) i32 {
    return @as(i32, @intCast(n)) - 39;
}

pub fn draw(d: blit.Dst, n: u32) void {
    const strip = d.window(A.X0, A.Y0 + Y, 320, H);
    const k0 = firstColumn(n);
    var g: i32 = @divFloor(k0, 4); // the glyph slot holding column k0
    while (g * 4 <= @as(i32, @intCast(n))) : (g += 1) {
        const x = (g * 4 - k0) * 8;
        const glyph: usize = if (g <= 0) 0 else glyphOf(g - 1);
        blit.blit(strip, font, .{ .x = 0, .y = glyph * H, .w = GW, .h = H }, x, 0, null, .copy);
    }
}
