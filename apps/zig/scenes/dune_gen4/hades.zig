// F2 ($59CC, VBL $5A1C): the HADES screen. Stars, the waving HADES logo, five
// skulls on F1's path and a scroller in the lower border, all drawn into the
// hidden screen in ST format (hades/ram.zig says why) and shown the VBL after.
// The palette ($789A) is set at once -- no fade -- and every VBL; Timer B at
// line 198 ($5ABA) zeroes colour 3 and opens the lower border, then from line
// 201 writes colour 1 from RASTER1 (the scroller's gradient) and colour 0 from
// the memory at $797E -- the logo's rotating wobble table, read as colour words:
// the bars that shimmer in the border -- until RASTER1's 0; colour 0 is 0 after.
//
// What the original keeps between visits, this keeps: the logo's place on its
// walk and the wobble's rotation, the skulls' places on the path.
// Timeline (Hatari): the first VBL comes FIRST_VBL VBLs after F2 (16 or 17 run
// to run), the screens cleared and the logo and skulls pre-shifted meanwhile --
// and meanwhile the MENU's VBL is still installed: its scroller goes on rolling
// into plane 3 of the cleared screen on show, under the menu's rasters. That
// screen is the one F2 draws into second, so the rolled-in bits stay in it,
// invisible in colour 8 until a star lands on one (dune_gen4.zig runs the
// menu's VBL; vbl() takes over its band).
const zg = @import("zigos");
const st = @import("st.zig");
const ram = @import("hades/ram.zig");
const Stars = @import("hades/stars.zig").Stars;
const Logo = @import("hades/logo.zig").Logo;
const Skulls = @import("hades/skulls.zig").Skulls;
const Scroll = @import("hades/scroll.zig").Scroll;
const H = @import("assets.zig").HADES;

pub const FIRST_VBL: u32 = 17;
const RASTER_TOP = 201;
const C0_FROM = 0x797E - 0x796C; // where Timer B's colour-0 reads start in WOBBLE

pub const Hades = struct {
    n: u32, // VBLs since F2
    hidden: u1, // the screen the next VBL draws into ($F38)
    stars: Stars,
    logo: Logo,
    skulls: Skulls,
    scroll: Scroll,

    /// The screens and the pre-shifts come from the cart's RAM arena.
    pub fn init(self: *Hades) void {
        ram.screens = &zg.mem.mustAlloc([2]ram.Screen, 1)[0];
        self.logo.init(&zg.mem.mustAlloc(Logo.Shifts, 1)[0]);
        self.skulls.init(&zg.mem.mustAlloc(Skulls.Shifts, 1)[0]);
    }

    pub fn enter(self: *Hades) void {
        self.n = 0;
        self.hidden = 0;
        for (ram.screens) |*s| @memset(s, 0); // $39E
        self.stars.init();
        self.scroll.enter();
    }

    /// Space is read once the VBL runs ($59FA).
    pub fn running(self: *const Hades) bool {
        return self.n >= FIRST_VBL;
    }

    /// `band`: plane 3 of the menu scroller's lines, as its VBL left them.
    pub fn vbl(self: *Hades, band: *const [BAND_LINES][20]u16) void {
        self.n += 1;
        if (!self.running()) return;
        if (self.n == FIRST_VBL) takeBand(&ram.screens[self.hidden ^ 1], band);
        const s = &ram.screens[self.hidden];
        self.stars.clear(s);
        self.skulls.clear(s);
        self.logo.clear(s);
        self.scroll.vbl(s);
        self.stars.draw(s);
        self.logo.draw(s);
        self.skulls.draw(s);
        self.hidden ^= 1;
    }

    pub fn render(self: *const Hades, fb: *zg.LogicalFB) void {
        st.clear(fb);
        // on show: the screen the VBL before drew, hidden again since the swap
        for (0..ram.LINES) |y| ram.pixels(&ram.screens[self.hidden], y, st.row(fb, y));
        st.setPalette(&H.PALETTE);
        st.set(0, 0, 0);
        if (!self.running()) return;
        st.setFrom(RASTER_TOP - 2, 3, 0);
        for (0..H.RASTER1.len + 1) |i| {
            const c1 = if (i < H.RASTER1.len) H.RASTER1[i] else 0;
            const at = C0_FROM + 2 * i;
            const c0 = @as(u16, self.logo.wobble[at]) << 8 | self.logo.wobble[at + 1];
            st.set(RASTER_TOP + i, 1, c1);
            st.set(RASTER_TOP + i, 0, c0);
        }
        st.setFrom(RASTER_TOP + H.RASTER1.len, 1, 0);
        st.setFrom(RASTER_TOP + H.RASTER1.len + 1, 0, 0);
    }
};

const BAND_TOP = @import("menuscroll.zig").TOP;
const BAND_LINES = @import("menuscroll.zig").LINES;

/// The menu scroller's plane 3 into the screen that was on show.
fn takeBand(s: *ram.Screen, band: *const [BAND_LINES][20]u16) void {
    for (band, 0..) |row, l| {
        for (row, 0..) |w, g| ram.w16(s, (BAND_TOP + l) * ram.LINE + g * 8 + 6, w);
    }
}

comptime {
    if (C0_FROM + 2 * (H.RASTER1.len + 1) > H.WOBBLE.len) @compileError("Timer B reads past the WOBBLE copy");
}
