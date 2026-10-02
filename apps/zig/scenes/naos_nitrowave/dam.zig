// --------------------------------------------------------------------------
// F3: SAPRISTI 3615 GEN 4, by Aragorn (DAMIER3D.BIN, loaded at $400): two
// 3D checkerboards (planes 0/1 drawn once per screen, the squares made by
// colours 0 and 1 swapped per line), a landscape scrolled in planes 0/1 under
// static planes 2/3 (the parallax), a distorted logo and a scroller.
//
// The part memory starts as the part's own set-up leaves it at its main
// loop's first stop ($4AC): its precalculation (the four screens, the band
// routines, the shifted fonts) is a long piece of code, run here by the
// original itself -- Hatari, then checked on Musashi -- and shipped as that
// RAM ($400..$7A000; NOTES.md, "F3"). Everything per frame is ported: the
// VBL program (dam_vbl.zig), the main loop's four phases and its routines
// (here and dam_logo.zig), the colour-register writes (dam_show.zig).
// prototypes/naos_nitrowave_re/dam_model.py + dam_main.py are the same
// model: = the original on Musashi to 20000 frames, = Hatari's 560.
// --------------------------------------------------------------------------
const st = @import("st.zig");
const vbl = @import("dam_vbl.zig");
const logo = @import("dam_logo.zig");

const FREEZE: u32 = 0x36204;
const DRAW: u32 = 0x361F4; // the screen the next VBL draws
const SCROLL_AT: u32 = 0x30C92;
const SCROLL_X: u32 = 0x30C98;

/// One main-loop phase: the screen the next VBL draws, the one shown, a5,
/// and the bottom band's screen line ($3102C).
const Phase = struct { draw: u32, show: u32, a5: u32, bottom: u32 };
const phases = [4]Phase{
    .{ .draw = 0x4DF00, .show = 0x5CA00, .a5 = 0x53DF6, .bottom = 0x56668 },
    .{ .draw = 0x3F400, .show = 0x4DF00, .a5 = 0x452F6, .bottom = 0x47B68 },
    .{ .draw = 0x6B500, .show = 0x3F400, .a5 = 0x713F6, .bottom = 0x73C68 },
    .{ .draw = 0x5CA00, .show = 0x6B500, .a5 = 0x628F6, .bottom = 0x65168 },
};

pub const Dam = struct {
    regs: vbl.Regs,
    phase: u8,
    shown: u32, // the screen the shifter shows from the next VBL
    displayed: u32, // the screen shown while the last VBL ran

    /// The registers at the first stop ($4AC), as Hatari printed them.
    pub fn enter(self: *Dam) void {
        self.regs = .{ .a4 = 0x31038, .a5 = 0x628F6, .a6 = 0x14DBE };
        self.phase = 0;
        self.shown = 0x6B500; // $428
        self.displayed = self.shown;
    }

    pub fn frame(self: *Dam, r: *const st.Ram) void {
        self.displayed = self.shown;
        vbl.run(r, &self.regs);
        const p = phases[self.phase];
        columns(r);
        r.sl(DRAW, p.draw);
        r.sl(SCROLL_AT, p.draw +% r.l(SCROLL_X));
        scrollWave(r);
        self.shown = p.show;
        self.regs.a5 = p.a5;
        self.regs.a6 = bandTop(r);
        r.sl(0x3102C, p.bottom);
        bandBottom(r);
        self.regs.a4 = logo.next(r);
        if (!(self.phase == 0 and frozen(r))) self.phase = (self.phase + 1) % 4; // $542
    }

    pub fn toggleFreeze(_: *Dam, r: *const st.Ram) void {
        r.sw(FREEZE, ~r.w(FREEZE)); // $53C: not.w $36204
    }
};

fn frozen(r: *const st.Ram) bool {
    return r.w(FREEZE) != 0;
}

/// $924: the nine character pointers for the next VBL ($30C6E), one of
/// four preshifted fonts (*$30C6A) indexed by the text (*$35734).
fn columns(r: *const st.Ram) void {
    if (!frozen(r)) {
        const a0 = r.l(0x30C6A) + 4;
        if (a0 == 0x30C6A) stepText(r) else r.sl(0x30C6A, a0);
    }
    const font = r.l(r.l(0x30C6A));
    const text = r.l(0x35734);
    for (0..9) |k| {
        const kk: u32 = @intCast(k);
        r.sl(0x30C6E + 4 * kk, r.l(font + 4 * @as(u32, r.b(text + kk))));
    }
}

/// $970: four shifts done: the place 8 pixels back, every third time the
/// text a character on (it wraps from $361B4 to $3577A).
fn stepText(r: *const st.Ram) void {
    r.sl(0x30C6A, 0x30C5A);
    r.sl(SCROLL_X, r.l(SCROLL_X) -% 8);
    const n = r.w(0x30C96) -% 1;
    r.sw(0x30C96, n);
    if (n != 0) return;
    r.sl(SCROLL_X, r.l(SCROLL_X) +% 0x18);
    r.sw(0x30C96, 3);
    const t = r.l(0x35734) + 1;
    r.sl(0x35734, if (t == 0x361B4) 0x3577A else t);
}

/// $9D8: the scroller's wave (*$30C92 += word) and the clear's place.
fn scrollWave(r: *const st.Ram) void {
    var a0 = r.l(0x30E7C);
    const d0: u32 = r.w(a0);
    const d1: u32 = r.w(a0 + 2);
    if (!frozen(r)) a0 += 4;
    if (a0 == 0x30E7C) a0 = 0x30CA0;
    r.sl(0x30E7C, a0);
    r.sl(SCROLL_AT, r.l(SCROLL_AT) +% d0);
    r.sl(0x30C9C, d1 +% r.l(DRAW) +% 0xA08E);
}

/// $682: the top band's source; each time its list wraps, the next routine pair.
fn bandTop(r: *const st.Ram) u32 {
    return walkBand(r, 0x31010, 0x30FF0, 0x30F68, 0x30E80, 0x30F6C);
}

/// $6E0: the same for the bottom band, into $31028.
fn bandBottom(r: *const st.Ram) void {
    r.sl(0x31028, walkBand(r, 0x31024, 0x31014, 0x30FE4, 0x30F74, 0x30FE8));
}

fn walkBand(r: *const st.Ram, ptr: u32, first: u32, pairs: u32, pairs_first: u32, routines: u32) u32 {
    var a0 = r.l(ptr);
    if (!frozen(r)) {
        a0 += 4;
        if (a0 == ptr) {
            r.sl(ptr, first);
            var q = r.l(pairs);
            r.sl(routines, r.l(q));
            r.sl(routines + 4, r.l(q + 4));
            q += 8;
            r.sl(pairs, if (q == pairs) pairs_first else q);
            return r.l(first);
        }
        r.sl(ptr, a0);
    }
    return r.l(a0);
}
