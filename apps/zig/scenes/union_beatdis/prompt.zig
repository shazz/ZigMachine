// --------------------------------------------------------------------------
// The BEAT DIS loader's question (screens/beatdis/loader.js:17-21, 87-99).
//
// Once its panel has assembled, the loader prints four lines under it in the
// same loader.png font and waits: SPACE ('enter', main.js:391) starts
// BEATDIS1024_SCREEN, RETURN ('start', main.js:392) BEATDIS512_SCREEN.
//
// Placement: loaderfont.print at (328 - 16*len/2, 408 - 16*(4+1) + 16*i) with a
// mid-handled 16x16 font, so a glyph's top-left is 8 px up and left of that.
// Halved: x = 160 - 4*len + 8*k, y = 160 + 8*i (every line has an even length).
// --------------------------------------------------------------------------
const zg = @import("zigos");
const tex_loader = @import("depackers").tex_loader;

pub const LINES = [_][]const u8{
    "ONE MEG AND DOUBLE SIDED DRIVE FOUND",
    "PRESS RETURN FOR THE 1/2 MEG VERSION",
    "ANY OTHER TO GO ON",
    "",
};
const TOP = (408 - 16 * (LINES.len + 1) - 8) / 2;
const CENTRE = (328 - 8) / 2;

comptime {
    for (LINES) |line| {
        if (line.len % 2 != 0) @compileError("an odd-length line would sit half an ST pixel off");
        for (line) |c| if (c < 0x20 or c - 0x20 >= tex_loader.font.len) @compileError("prompt character outside loader.png");
    }
}

/// The assembled panel (every letter landed) and the question under it, in
/// palette entry `ink` on entry `paper`.
pub fn draw(fb: *zg.LogicalFB, panel: []const u8, cols: u8, ink: u8, paper: u8) void {
    tex_loader.draw(fb, panel, cols, tex_loader.timelineEnd(@intCast(panel.len)), ink);
    const dst = zg.blit.Dst.plane(fb);
    for (dst.buf) |*p| {
        if (p.* == 0) p.* = paper;
    }
    for (LINES, 0..) |line, row| {
        const left = CENTRE - 4 * line.len;
        for (line, 0..) |c, k| glyph(dst, c, left + 8 * k, TOP + 8 * row, ink);
    }
}

fn glyph(dst: zg.blit.Dst, c: u8, x: usize, y: usize, ink: u8) void {
    for (tex_loader.font[c - 0x20], 0..) |bits, gy| {
        const line = dst.buf[(y + gy) * dst.stride + x ..][0..tex_loader.GLYPH];
        for (line, 0..) |*p, gx| {
            if (bits >> @intCast(7 - gx) & 1 == 1) p.* = ink;
        }
    }
}
