// The menu ($1018A, VBL $101E6): MENU.TNY faded in, then every VBL its palette
// ($10486), Timer B from line 10: colour 15 -- the grey "3615" and "GEN4" --
// rewritten every line from 11 to 147 ($10278, the rainbow), zeroed on 148,
// a second palette from line 149 ($10466: colours 8..15 become copies of
// 0..7) and colour 8 rewritten from line 150 for the scroller ($102DC).
// F1, F2 and F3 are read by the main loop ($1E2).
const zg = @import("zigos");
const st = @import("st.zig");
const tny = @import("tny.zig");
const fade = @import("fade.zig");
const A = @import("assets.zig");
const MenuScroll = @import("menuscroll.zig").MenuScroll;

const T = A.T;
const RAIN_TOP = 11; // Timer B at 10, then a line per word
const LOW_TOP = RAIN_TOP + T.MENU_RAIN15.len + 1; // 149
const SCROLL8_TOP = LOW_TOP + 1; // 150

pub const Menu = struct {
    n: u32, // VBLs since the menu was (re)loaded
    scroll: MenuScroll,
    palette: [16]u16, // MENU.TNY's, which the fade ends on

    /// The menu is loaded again after every part ($1DC jsr $1018A).
    pub fn enter(self: *Menu, fb: *zg.LogicalFB, pic: *const tny.Picture) void {
        self.n = 0;
        self.palette = pic.palette;
        st.clear(fb);
        for (0..st.H) |y| @memcpy(st.row(fb, y), pic.px[y * tny.W ..][0..tny.W]);
        self.scroll.init(fb);
    }

    pub fn ready(self: *const Menu) bool {
        return self.n > fade.FRAMES;
    }

    pub fn vbl(self: *Menu) void {
        self.n += 1;
        if (self.ready()) self.scroll.vbl();
    }

    pub fn render(self: *const Menu, fb: *zg.LogicalFB) void {
        if (!self.ready()) {
            const pal = fade.at(&self.palette, self.n);
            return st.setPalette(&pal);
        }
        self.scroll.draw(fb);
        st.setPalette(&T.MENU_PAL_TOP);
        for (T.MENU_RAIN15, 0..) |w, i| st.set(RAIN_TOP + i, 15, w);
        st.setFrom(LOW_TOP - 1, 15, 0);
        st.setPaletteFrom(LOW_TOP, &T.MENU_PAL_LOW);
        for (T.MENU_SCROLL8, 0..) |w, i| st.set(SCROLL8_TOP + i, 8, w);
        st.setFrom(SCROLL8_TOP + T.MENU_SCROLL8.len, 8, 0);
    }
};

comptime {
    if (LOW_TOP != 149) @compileError("the low palette loads on line 149");
}
