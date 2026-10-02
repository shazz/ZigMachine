// --------------------------------------------------------------------------
// F1: MULTISPRITES, by Ric (DEMO_RIC.BIN, loaded at $800). A chain of sprites
// flies one of four figures over a picture, under a one-plane scroller with
// a rainbow and colour bars from Timer B. All of it is interrupt-driven: the
// VBL ($F96) moves everything, drawing into one of four screens; the main
// loop only waits for Space.
//
// The figure is random on the ST ($A3E reads the video counter); here it is
// the menu's VBL count at the key, halved, mod 4 -- the same kind of chance.
// The title picture shows while the set-up runs, as long as it took on the ST
// for that figure (Hatari: from $894 to the main loop).
//
// Ported from the original's code and tables (ric_font.zig, ric_init.zig,
// ric_sprites.zig, ric_scroll.zig = prototypes/naos_nitrowave_re/ric_pre.py,
// ric_init.py, ric_model.py, each = the original to the byte). APPROXIMATED,
// as on the ST these were cycle races: the VBL draws into a screen while the
// shifter may show it (here a screen is shown whole, two VBLs after the one
// that set it -- the lag the captures show), and the colour changes land at
// their nominal lines (ric_show.zig).
// Keys as the original: F1 freezes it (its VBL $EF4 moves nothing), F2 lets
// it go on.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const st = @import("st.zig");
const spr = @import("ric_sprites.zig");
const scroll = @import("ric_scroll.zig");
const init = @import("ric_init.zig");
const font = @import("ric_font.zig");
const show = @import("ric_show.zig");

pub const TUNE = "robocop_tune_2.sndh";
/// VBLs from the title on screen ($894) to the main loop, by figure (Hatari).
const TITLE_VBLS = [4]u16{ 747, 748, 672, 594 };

pub const Ric = struct {
    figure: u2,
    title_left: u16, // VBLs of title still to show; 0 once the part runs
    frozen: bool,
    regs: show.Regs, // the colour registers at the end of the last frame
    shown_regs: show.Regs, // ...and as the last VBL left them
    bases: [3]u32, // the screen base set by the last three VBLs, oldest first

    /// From the file: the title on screen, the fonts built (ric_font.zig).
    pub fn enter(self: *Ric, r: *const st.Ram, figure: u2) void {
        font.run(r);
        self.figure = figure;
        self.title_left = TITLE_VBLS[figure];
        self.frozen = false;
        zg.stopSong(); // the title is silent: the replay starts with the part
    }

    pub fn inTitle(self: *const Ric) bool {
        return self.title_left > 0;
    }

    /// The screen the shifter shows now.
    pub fn displayed(self: *const Ric) u32 {
        return self.bases[0];
    }

    pub fn frame(self: *Ric, r: *const st.Ram) void {
        if (self.title_left > 0) {
            self.title_left -= 1;
            if (self.title_left == 0) self.start(r);
            return;
        }
        self.regs.vbl(r);
        const shown = if (self.frozen) self.bases[2] else vbl(r);
        self.shown_regs = self.regs;
        self.regs.frame(r);
        self.bases = .{ self.bases[1], self.bases[2], shown };
    }

    /// The set-up's end ($D5E..$D94): the replay started, the palette, the VBL.
    fn start(self: *Ric, r: *const st.Ram) void {
        init.run(r, self.figure);
        self.regs = show.Regs.start(r);
        self.shown_regs = self.regs;
        const bg = r.l(spr.BG);
        self.bases = .{ bg, bg, bg };
        zg.requestSongTune(TUNE, 1);
    }

    pub fn present(self: *const Ric, r: *const st.Ram, px: []u8) void {
        if (self.inTitle()) return show.presentTitle(r, px);
        show.present(r, self.displayed(), self.shown_regs, px);
    }
};

/// $F96: the next screen, three sprite lists, the scroller and its colours.
/// Returns the screen base the shifter shows from the next frame.
fn vbl(r: *const st.Ram) u32 {
    const shown = screens(r);
    spr.draw(r, 0x47920, .by_band);
    spr.restore(r);
    spr.third(r);
    scroll.scroller(r);
    scroll.colours(r);
    scroll.bars(r);
    return shown;
}

/// $FD8: the next of the four screens is drawn; the shifter follows it once
/// the countdown at $316A has run out (until then the background shows).
fn screens(r: *const st.Ram) u32 {
    var a0 = r.l(init.SCREEN_PTR);
    if (r.l(a0) == 0xFFFFFFFF) a0 = init.SCREENS;
    const n = r.w(init.COUNTDOWN) -% 1;
    r.sw(init.COUNTDOWN, n);
    var shown = r.l(spr.BG);
    if (n & 0x8000 != 0) {
        r.sw(init.COUNTDOWN, 0);
        shown = r.l(a0) & 0xFFFF00;
    }
    r.sl(spr.WORK, r.l(a0));
    r.sl(init.SCREEN_PTR, a0 + 4);
    return shown;
}
