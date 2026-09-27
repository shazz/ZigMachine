// --------------------------------------------------------------------------
// SWEDISH NEW YEAR DEMO -- SYNC, AN COOL, THE CAREBEARS & OMEGA (Atari ST,
// released 01-01-1989). Graphics, texts and music belong to their authors:
// OMEGA (Red) for the graphics, TCB for the code, MAD MAX for the music (and
// David Whittaker's Beyond the Ice Palace on the OMEGA screen).
//
// TWO SOURCES. The menu and OMEGA are still ported from Mellow Man & NewCore's
// CODEF remake (wab.com screen 295, MIT). The SYNC screens are ported from the
// DISK (SNYD_89.MSA; prototypes/snyd_re/NOTES.md): the boot sector decrypts a
// loader into $7000, which reads the menu from tracks 1..11 to $8000 and, on
// F1 / F2 / F3, a part from tracks 45..55 to $20000 / 12..37 to $8000 /
// 38..44 to $8000, jumps in, and reloads the menu when the part returns. The
// FAT on the disk is a decoy. See sync.zig, sync1.zig, sync2.zig.
//
// Keys: menu F1 -> SYNC #1, F2 -> TCB #1, F3 -> OMEGA; SYNC #1 Space -> SYNC #2;
// SYNC #2 Space -> menu (the original resets the ST, which boots back into the
// menu); TCB #1 Space -> TCB #2 (F1..F5: the five Dugger tunes); TCB #2 / OMEGA
// Space -> menu. Escape leaves (not in the original). The remake's screens keep
// their state across visits; a SYNC visit starts fresh, as a disk load does.
//
// MUSIC (each mapped by YM register comparison or from the disk's own replay):
//   SYNC #1  Jinks.sndh #1 (Mad Max). The part's replay (TFMX module at $36DF0)
//            wrapped as an SNDH and logged against Jinks #1 over 3000 frames:
//            99.9% of frames identical in periods and volumes at a 2-frame lag.
//   SYNC #2  Swedish_New_Year_Demo_Sync.sndh (Grazey's rip of this very screen's
//            4-voice sample replay, Timer A at 7680 Hz; FLAG ~ay is Timer A, not
//            STE DMA): 90% of its 32-byte windows are found verbatim in the
//            part's code and samples ($2C3FA..$31C00), the rest relocated code.
//   scout.ym     -> scout.sndh #1 (Mad Max, C64-Conversions/Scout)  hist 0.997, seq 0.94
//   dugger1.ym   -> dugger.sndh #2 (Mad Max, Games/Dugger)          hist 0.992
//   dugger2.ym   -> dugger.sndh #3                                  hist 0.992
//   dugger3.ym   -> dugger.sndh #4                                  hist 0.988
//   dugger5.ym   -> dugger.sndh #1                                  hist 0.996
//   dugger4.ym   -> NO SNDH (a 138-frame jingle, best Archon #1 at 0.17): its own
//                   dump, swedish_newyear_dugger4.ymraw -- the one last-resort dump.
//   icepalace.ym -> beyond_the_ice_palace.sndh #1 (Whittaker)       hist 0.976
//   TCB #1   the remake's intro.ogg and music.ogg, resampled to 12517 Hz .raw.
// All SNDH are FLAG ~y except the Sync one (~ay, Timer A).
// --------------------------------------------------------------------------
const zg = @import("zigos");
const frame = @import("swedish_newyear/frame.zig");
const Menu = @import("swedish_newyear/menu.zig").Menu;
const Sync = @import("swedish_newyear/sync.zig").Sync;
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
    sync: Sync,
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
        if (self.part == .sync1 or self.part == .sync2) return self.renderSync(zigos, dt);
        frame.st_mode = false;
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
            .tcb1 => if (self.tcb1.step()) music.play(.tcb_music),
            .tcb2 => self.tcb2.step(0),
            .omega => self.omega.step(&self.vu, &zigos.ym_regs),
            .sync1, .sync2 => unreachable,
        };
        frame.present(&zigos.lfbs[0]);
        self.colour0();
    }

    fn renderSync(self: *Demo, zigos: *ZigOS, dt: f32) void {
        frame.setBorders(.closed);
        const fb = &zigos.lfbs[0];
        if (!self.load()) {
            frame.st_mode = false;
            frame.clear();
            return frame.present(fb);
        }
        frame.st_mode = true;
        self.sync.frame(fb.fb[0 .. frame.PW * frame.PH], dt);
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
        switch (set) {
            .tcb1 => self.tcb1.enter(),
            .sync => {
                self.sync.enter();
                if (self.part == .sync2) self.sync.toSecond(); // Space beat the load
            },
            else => {},
        }
        return true;
    }

    /// The next frame's colour 0 per line (rasters on TCB #2).
    fn colour0(self: *Demo) void {
        switch (self.part) {
            .tcb2 => self.tcb2.colour0(&frame.c0_next),
            .sync1, .sync2 => {}, // the part captures its own (st_show.zig)
            else => @memset(&frame.c0_next, frame.BLACK),
        }
        self.drawn = self.part;
    }

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
            0 => {
                self.loaded = null; // F1 reads the part from the disk again
                self.go(.sync1, .jinx1);
                // Now, not on the next render: its first frame's borders (the
                // global HBL) are painted from what enter() captures.
                _ = self.load();
            },
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
            .sync1 => {
                if (self.loaded == .sync) self.sync.toSecond();
                self.part = .sync2;
                music.play(.sync2);
            },
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
