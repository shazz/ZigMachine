// --------------------------------------------------------------------------
// Shared credits/label font (efmain.js creditsFonts). A 288x30 sheet of 32x3
// 9x10 glyphs (ASCII 32..127), treated as a 1-bit mask (index 0 = transparent).
// Used by the credits pages and by the door-title labels, each drawing it in
// its own palette-alpha-faded slot. Matches the JS write_text advance: the cell
// is 9px but glyphs step 8px (font.tilew-2 at half scale), overlapping 1px.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const LogicalFB = zg.LogicalFB;

const raw = @embedFile("../../assets/screens/union_main/credits.raw");
const SHEET_W: usize = 288;
pub const GW: i16 = 9; // glyph cell in the sheet
pub const GH: i16 = 10;
pub const CHAR_PITCH: i16 = 8; // on-screen advance per char (glyphs overlap 1px)

pub fn width(line: []const u8) i16 {
    return @as(i16, @intCast(line.len)) * CHAR_PITCH;
}

// Draw one text line at (x0,y0) using palette index `idx` for every glyph pixel.
pub fn drawLine(fb: *LogicalFB, line: []const u8, x0: i16, y0: i16, idx: u8) void {
    const pw: i16 = @intCast(fb.fb_w);
    const ph: i16 = @intCast(fb.fb_h);
    for (line, 0..) |ch, ci| {
        if (ch < 32 or ch > 127) continue;
        const g = ch - 32;
        const scol = @as(usize, g % 32) * @as(usize, @intCast(GW));
        const srow = @as(usize, g / 32) * @as(usize, @intCast(GH));
        const cx = x0 + @as(i16, @intCast(ci)) * CHAR_PITCH;
        var ry: i16 = 0;
        while (ry < GH) : (ry += 1) {
            const py = y0 + ry;
            if (py < 0 or py >= ph) continue;
            const srowoff = (srow + @as(usize, @intCast(ry))) * SHEET_W + scol;
            var rx: i16 = 0;
            while (rx < GW) : (rx += 1) {
                const px = cx + rx;
                if (px < 0 or px >= pw) continue;
                if (raw[srowoff + @as(usize, @intCast(rx))] == 0) continue;
                fb.fb[@as(usize, @intCast(py)) * fb.stride + @as(usize, @intCast(px))] = idx;
            }
        }
    }
}
