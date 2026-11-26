// --------------------------------------------------------------------------
// AURORA BOOT: plane 1's palette per frame. The star ramp (opaque), the falcon's wire and the name (their full
// colour at an alpha that fades them in over the sky, look.zig), and the baked name's 128 coverage
// entries; all through the end fade (TC_FADE's rule on RGB, the alpha kept: a blend of two faded colours is
// the faded blend). An entry is rewritten only when its level or the fade changes (a palette write is ~free).
// --------------------------------------------------------------------------
const zg = @import("zigos");
const look = @import("look.zig");

pub const Colours = struct {
    drawn: [look.WORD + 1]u8 = [_]u8{255} ** (look.WORD + 1), // the last level written per entry
    coef: u8 = 255, // the fade last applied
    word_drawn: u8 = 255, // the name level last written to entries WORD_BASE..255

    /// wire / name: the baked levels 0..15; fade: the TC_FADE coefficient.
    pub fn apply(self: *Colours, fb: *zg.LogicalFB, wire: u32, name: u32, c: u5) void {
        const redo = c != self.coef;
        self.coef = c;
        for (1..look.LEVELS + 1) |lv| self.set(fb, @intCast(lv), .{ .rgb = look.star(@intCast(lv)), .a = 255 }, lv, c, redo);
        self.set(fb, look.LINE, look.wire(wire), wire, c, redo);
        self.set(fb, look.WORD, look.ink(name), name, c, redo);
        self.word(fb, name, c, redo);
    }

    /// The baked name's 128 entries: the ink at alpha coverage x level.
    fn word(self: *Colours, fb: *zg.LogicalFB, level: u32, c: u5, redo: bool) void {
        if (!redo and self.word_drawn == level) return;
        self.word_drawn = @intCast(level);
        const ink = look.ink(look.LEVELS).rgb;
        var e: u32 = look.WORD_BASE;
        while (e < 256) : (e += 1) fb.palette[e] = faded(ink, look.wordAlpha(@intCast(e), level), c);
    }

    fn set(self: *Colours, fb: *zg.LogicalFB, e: u8, col: look.Rgba, level: usize, c: u5, redo: bool) void {
        if (!redo and self.drawn[e] == level) return;
        self.drawn[e] = @intCast(level);
        fb.palette[e] = faded(col.rgb, col.a, c);
    }
};

fn faded(rgb: look.Rgb, a: u8, c: u5) u32 {
    const col = zg.Color{ .r = look.fadeChannel(rgb.r, c), .g = look.fadeChannel(rgb.g, c), .b = look.fadeChannel(rgb.b, c), .a = a };
    return col.toRGBA();
}
