// --------------------------------------------------------------------------
// The intro (part 8, loaded once before the menu): a Spectrum 512 picture --
// the "SWEDISH NEW YEAR DEMO 89-90" title -- and Mad Max's tune (subtune 4 of
// the menu's module). The disk holds it in the SPU layout: the 32000-byte
// screen at $5724, then 199 palettes of 48 words at $D424. The original shows
// it with a cycle-counted loop ($10B8) that, from display line 1 on, writes
// colours 1..15, then 0..15, then 0..15 a line while the beam runs, so each
// register holds three colours across the line. Which one a pixel of colour c
// at x gets is the standard Spectrum 512 boundary (spuSlot).
//
// The loop never writes colour 0 of the first set (it starts at $FF8242): at
// x = 0 colour 0 still holds the previous line's third set. On this picture
// that is always black, but it is what the original does, and it is checked
// pixel for pixel against a Hatari capture (prototypes/snyd90_re/spu.py).
//
// Here each line's 48 registers become 48 palette entries of that line, the
// pixels index them, and the plane's HBL loads them before the line: the same
// per-line register writes, lossless. Space leaves for the menu ($109C).
// --------------------------------------------------------------------------
const st = @import("../swedish_newyear/st.zig");
const shifter = @import("shifter.zig");

pub const SCREEN_LEN = 32000;
pub const LINES = 199; // palettes: display lines 1..199
pub const LEN = SCREEN_LEN + LINES * 96;

/// The register (0..47: set*16 + colour) live when the beam paints pixel `x`
/// with colour `c`.
pub fn spuSlot(x: usize, c: u8) u8 {
    const ci: i32 = c;
    const x1: i32 = 10 * ci + (if (c & 1 != 0) @as(i32, -5) else 1);
    const xi: i32 = @intCast(x);
    if (xi >= x1 and xi < x1 + 160) return c + 16;
    return if (xi >= x1 + 160) c + 32 else c;
}

/// Show the picture: `spu` is the screen and its 199 line palettes.
pub fn show(spu: *const [LEN]u8) void {
    const black = st.color(0);
    shifter.blank(black);
    var carry: u16 = 0; // colour 0 of set 0: the previous line's last colour 0
    for (0..200) |y| {
        var line: [320]u8 = undefined;
        st.lineToChunky(spu[y * st.LINE ..][0..st.LINE], &line);
        const out = shifter.row(y);
        if (y == 0) { // no palette: the registers are all black
            @memset(out, 0);
            continue;
        }
        const pal = spu[SCREEN_LEN + (y - 1) * 96 ..][0..96];
        var regs: [48]u32 = undefined;
        for (&regs, 0..) |*c, i| c.* = st.color(word(pal, i));
        regs[0] = st.color(carry);
        carry = word(pal, 32);
        for (out, line, 0..) |*o, c, x| o.* = spuSlot(x, c);
        shifter.setLine(y, &regs);
    }
}

fn word(pal: *const [96]u8, i: usize) u16 {
    return @as(u16, pal[2 * i]) << 8 | pal[2 * i + 1];
}
