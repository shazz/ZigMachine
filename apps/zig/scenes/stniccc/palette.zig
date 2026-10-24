// --------------------------------------------------------------------------
// The stream's 16 ST colours into the plane's palette entries 0..15, writing
// only the entries whose ST word changed: most frames keep the palette of the
// frame before, and an ST coder never rewrote a register that already held
// the right colour (perf_audit palette_rewrite flagged 16 a frame).
// --------------------------------------------------------------------------
const zg = @import("zigos");

const ST_LEVEL = [8]u8{ 0, 36, 73, 109, 146, 182, 219, 255 }; // ST 3-bit gun -> 8 bit

pub const Palette = struct {
    // What entries 0..15 hold, as ST words. Word 0 is black, which is what the
    // scene's init paints every entry, so reset() matches the plane.
    shown: [16]u16,

    pub fn reset(self: *Palette) void {
        self.shown = [_]u16{0} ** 16;
    }

    pub fn apply(self: *Palette, fb: *zg.LogicalFB, pal: *const [16]u16) void {
        for (pal, 0..) |w, i| {
            if (w == self.shown[i]) continue;
            self.shown[i] = w;
            fb.setPaletteEntry(@intCast(i), zg.Color{
                .r = ST_LEVEL[(w >> 8) & 7],
                .g = ST_LEVEL[(w >> 4) & 7],
                .b = ST_LEVEL[w & 7],
                .a = 255,
            });
        }
    }
};
