// --------------------------------------------------------------------------
// SWEDISH NEW YEAR DEMO -- SYNC, AN COOL, THE CAREBEARS & OMEGA (Atari ST,
// released 01-01-1989), from Mellow Man & NewCore's "reworked remake" for CODEF
// (wab.com screen 295, MIT). Graphics, texts and music belong to their authors:
// OMEGA (Red) for the graphics, TCB for the code, MAD MAX for the music (and
// David Whittaker's Beyond the Ice Palace on the OMEGA screen).
//
// The remake is a menu and five screens, switched by keys (screen.js KeyCheck):
//   menu   F1 -> SYNC #1 (Jinks)   F2 -> TCB #1 (intro.ogg, music.ogg)
//          F3 -> OMEGA (Beyond the Ice Palace)
//   SYNC #1  Space -> SYNC #2 (same tune)        SYNC #2  Space -> menu (Scout)
//   TCB #1   Space -> TCB #2 (Dugger)            TCB #2 / OMEGA  Space -> menu
//   TCB #2   F1..F5: the five Dugger tunes.      Escape leaves (not in the remake).
// Its state never resets, so a screen resumes where it was left.
//
// GEOMETRY. The 640x450 work canvas is an ST 320x225 doubled: the picture plus
// the bottom border's first 25 lines, where the menu scroller and TCB #2's
// scroller run (those parts open the bottom border). TCB #1 draws on the whole
// 768x536 frame and opens every border. Everything is sampled at the
// 640-space point (2X, 2Y); art the remake draws at 1 px per 640-space pixel
// shows at half size, as it does there.
//
// MUSIC (every .ym of the remake mapped to an SNDH by YM register comparison:
// note-set histograms over the dump vs 3000 frames of each subtune, and aligned
// register-for-register runs; the one-off comparison scripts were scratch):
//   scout.ym     -> scout.sndh #1 (Mad Max, C64-Conversions/Scout)  hist 0.997, seq 0.94
//   jinx1.ym     -> Jinks.sndh #1 (Mad Max, Games/Jinks)            hist 1.000, seq 1.00
//   dugger1.ym   -> dugger.sndh #2 (Mad Max, Games/Dugger)          hist 0.992
//   dugger2.ym   -> dugger.sndh #3                                  hist 0.992
//   dugger3.ym   -> dugger.sndh #4  (dump frame 0 = subtune 4's frame 42: same periods and volumes for 12 frames)  hist 0.988
//   dugger5.ym   -> dugger.sndh #1                                  hist 0.996
//   dugger4.ym   -> NO SNDH: a 138-frame jingle ("Dugger #4", SainT) found in no
//                   subtune of Dugger.sndh nor any of Mad Max's 357 SNDH files (best:
//                   Archon #1 at 0.17), so it plays its own dump,
//                   swedish_newyear_dugger4.ymraw -- the one last-resort dump.
//   icepalace.ym -> beyond_the_ice_palace.sndh #1 (Whittaker; the dump is a 1 MHz
//                   rip, compared by pitch)                         hist 0.976
//   mute.ym      -> nothing: TCB #1 plays the remake's own intro.ogg and music.ogg,
//                   resampled to 12517 Hz signed .raw.
// All four SNDH are FLAG ~y (YM only).
// --------------------------------------------------------------------------
const zg = @import("zigos");
const frame = @import("swedish_newyear/frame.zig");
const Menu = @import("swedish_newyear/menu.zig").Menu;
const Sync1 = @import("swedish_newyear/sync1.zig").Sync1;
const sync2 = @import("swedish_newyear/sync2.zig");
const Tcb1 = @import("swedish_newyear/tcb1.zig").Tcb1;
const Tcb2 = @import("swedish_newyear/tcb2.zig").Tcb2;
const Omega = @import("swedish_newyear/omega.zig").Omega;
const Vu = @import("swedish_newyear/vu.zig").Vu;
const music = @import("swedish_newyear/music.zig");
const assets = @import("swedish_newyear/assets.zig");

const ZigOS = zg.ZigOS;

pub const Part = enum(u8) { menu, sync1, sync2, tcb1, tcb2, omega };

const K_SPACE: u32 = 32;
const K_ESC: u32 = 0xE012;
const K_F1: u32 = 0xE001;
/// intro.ogg's length: onend sets musicplease = 1 (164516 samples at 12517 Hz).
const INTRO_MS: f32 = 13143;

pub const Demo = struct {
    part: Part,
    drawn: Part, // the part whose colour-0 table c0_next holds
    menu: Menu,
    sync1: Sync1,
    tcb1: Tcb1,
    tcb2: Tcb2,
    omega: Omega,
    vu: Vu,
    intro_on: bool,
    intro_ms: f32,
    wants_quit: bool,
    loaded: ?assets.Set, // the pictures in the part buffer (null: none usable)

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        self.part = .menu;
        self.drawn = .menu;
        self.menu.init();
        self.sync1.init();
        self.tcb1.init();
        self.tcb2.init();
        self.omega.init();
        self.vu.init();
        self.intro_on = false;
        self.intro_ms = 0;
        self.wants_quit = false;
        self.loaded = null;
        frame.init(zigos);
        music.play(.scout);
    }

    pub fn update(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = zigos;
        if (self.part != .tcb1 or !self.intro_on) return;
        self.intro_ms += dt;
        if (self.intro_ms >= INTRO_MS) { // tcbintro's onend
            self.intro_on = false;
            self.tcb1.music_please = 1;
        }
    }

    pub fn render(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = dt;
        if (self.drawn != self.part) self.colour0(); // a key switched parts
        frame.flipColour0();
        frame.setBorders(switch (self.part) {
            .menu, .tcb2 => .bottom,
            .tcb1 => .all,
            else => .closed,
        });
        const ready = self.load();
        if (self.part != .tcb1 or !ready) frame.clear();
        if (ready) switch (self.part) {
            .menu => self.menu.step(),
            .sync1 => self.sync1.step(),
            .sync2 => sync2.step(&self.vu, &zigos.ym_regs),
            .tcb1 => if (self.tcb1.step()) music.play(.tcb_music),
            .tcb2 => self.tcb2.step(self.sync1.scroll.current()),
            .omega => self.omega.step(&self.vu, &zigos.ym_regs),
        };
        frame.present(&zigos.lfbs[0]);
        self.colour0();
    }

    /// The part's pictures, depacked when it is first drawn after a switch (so
    /// two keys between frames depack once). False: nothing to draw with.
    fn load(self: *Demo) bool {
        const set: assets.Set = switch (self.part) {
            .menu => .menu,
            .sync1, .sync2 => .sync,
            .tcb1 => .tcb1,
            .tcb2 => .tcb2,
            .omega => .omega,
        };
        if (self.loaded == set) return true;
        if (!assets.load(set)) {
            self.loaded = null;
            zg.Console.log("swedish_newyear: the {s} pictures do not depack", .{@tagName(set)});
            return false;
        }
        self.loaded = set;
        if (set == .tcb1) self.tcb1.enter();
        return true;
    }

    /// The next frame's colour 0 per line (rasters on SYNC #1 and TCB #2).
    fn colour0(self: *Demo) void {
        switch (self.part) {
            .sync1 => self.sync1.colour0(&frame.c0_next),
            .tcb2 => self.tcb2.colour0(&frame.c0_next),
            else => @memset(&frame.c0_next, frame.BLACK),
        }
        self.drawn = self.part;
    }

    /// screen.js KeyCheck, case by case (its ifs run in order on the updated part).
    pub fn key(self: *Demo, cp: u32) void {
        if (cp == K_ESC) {
            self.wants_quit = true;
            return;
        }
        if (cp == K_SPACE) return self.space();
        if (cp < K_F1 or cp > K_F1 + 4) return;
        const f = cp - K_F1; // 0 = F1
        if (self.part == .tcb2) return music.play(music.dugger_keys[f]);
        if (self.part != .menu) return;
        switch (f) {
            0 => self.go(.sync1, .jinx1),
            1 => {
                self.go(.tcb1, .tcb_intro); // player: mute.ym; tcbintro.play()
                self.intro_on = true;
                self.intro_ms = 0;
            },
            2 => self.go(.omega, .icepalace),
            else => {},
        }
    }

    fn space(self: *Demo) void {
        switch (self.part) {
            .tcb2, .omega, .sync2 => self.go(.menu, .scout),
            .tcb1 => {
                self.intro_on = false; // tcbintro.stop(); tcbmusic.stop()
                self.go(.tcb2, .dugger3);
            },
            .sync1 => self.part = .sync2,
            .menu => {},
        }
        self.colour0();
    }

    fn go(self: *Demo, part: Part, tune: music.Tune) void {
        self.part = part;
        music.play(tune);
        // The key lands between frames and hwClear paints the borders BEFORE the
        // next frame runs: the new part's colour 0 must be in place now.
        self.colour0();
    }
};
