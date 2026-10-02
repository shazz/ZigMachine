// The main part ($4448, VBL $44C4): the DUNE logo parked at the top, the
// bouncing "3615 GEN4" over its grey colour-0 bars, and the scroller in the
// lower border. Every VBL loads INTRO.TNY's palette; then Timer B, started at
// line 100 ($FFFA21 = 100), writes colour 0 and colour 8 on every line from
// the two tables ($455E) until colour 8's ends (line 198), opens the lower
// border at line 199/200 by the 60 Hz switch ($45AA, which also zeroes colour
// 3), and from line 201 writes colour 3 from its own table ($4618).
// The part ends when the scroll text runs out, or on Space ($4490).
const std = @import("std");
const zg = @import("zigos");
const st = @import("st.zig");
const tny = @import("tny.zig");
const intro = @import("intro.zig");
const A = @import("assets.zig");
const L = @import("letters.zig");
const Letters = L.Letters;
const Scroller = @import("scroller.zig").Scroller;

const T = A.T;
const RAINBOW_END = L.TOP + T.RAINBOW8.len; // line 198: colour 8's 0
const BORDER_LINE = RAINBOW_END + 1; // 199: $45AA zeroes colour 3
const SCROLL3_TOP = 201;
/// The letters never rise above BOUNCE's lowest value: the logo's lines above
/// are never touched.
const LETTERS_TOP = L.TOP + std.mem.min(u8, &T.BOUNCE);

pub const MainPart = struct {
    letters: Letters,
    scroller: Scroller,
    c0: [L.C0_LINES]u16,
    palette: [16]u16, // $11EA: INTRO.TNY's

    pub fn enter(self: *MainPart, fb: *zg.LogicalFB, pic: *const tny.Picture) void {
        self.letters.init();
        self.scroller.init();
        @memset(&self.c0, 0);
        self.palette = pic.palette;
        st.clear(fb);
        intro.copyLines(fb, pic, 10, 0, 101);
    }

    pub fn done(self: *const MainPart) bool {
        return self.scroller.done;
    }

    pub fn vbl(self: *MainPart) void {
        self.letters.vbl(&self.c0);
        self.scroller.vbl();
    }

    pub fn render(self: *const MainPart, fb: *zg.LogicalFB) void {
        self.letters.draw(fb, LETTERS_TOP);
        self.scroller.draw(fb);
        self.rasters();
    }

    fn rasters(self: *const MainPart) void {
        st.setPalette(&self.palette);
        for (T.RAINBOW8, 0..) |w, i| st.set(L.TOP + i, 8, w);
        st.setFrom(RAINBOW_END, 8, 0);
        for (self.c0, 0..) |w, i| st.set(L.TOP + i, 0, w);
        st.setFrom(L.TOP + self.c0.len, 0, self.c0[self.c0.len - 1]);
        st.setFrom(BORDER_LINE, 3, 0);
        for (T.SCROLL3, 0..) |w, i| st.set(SCROLL3_TOP + i, 3, w);
        st.setFrom(SCROLL3_TOP + T.SCROLL3.len, 3, 0);
    }
};

comptime {
    if (RAINBOW_END != 198) @compileError("colour 8's table ends on line 198");
}
