// --------------------------------------------------------------------------
// SWEDISH NEW YEAR DEMO -- SYNC, AN COOL, THE CAREBEARS & OMEGA (Atari ST,
// released 01-01-1989). Graphics, texts and music belong to their authors:
// OMEGA (Red) for the graphics, TCB for the code, MAD MAX for the music (and
// David Whittaker's Beyond the Ice Palace on the OMEGA screen).
//
// TWO SOURCES. The menu is still ported from Mellow Man & NewCore's CODEF
// remake (wab.com screen 295, MIT). SYNC, TCB and OMEGA are ported from the
// DISK (SNYD_89.MSA; prototypes/snyd_re/NOTES*.md): the boot
// sector decrypts a loader into $7000, which reads the menu from tracks 1..11
// to $8000 and, on F1 / F2 / F3, a part from tracks 45..55 to $20000 /
// 12..37 to $8000 / 38..44 to $8000, jumps in, and reloads the menu when the
// part returns. The FAT on the disk is a decoy. See sync.zig, tcb.zig, omega.zig.
//
// Keys: menu F1 -> SYNC #1, F2 -> TCB #1, F3 -> OMEGA; SYNC #1 Space -> SYNC #2;
// SYNC #2 Space -> menu (the original resets the ST, which boots back into the
// menu); TCB #1 Space -> TCB #2 (F1/F2 scroller speed, F3/F4/F5 the Dugger
// tune from subtune 2/3/4); TCB #2 / OMEGA Space -> menu. Escape leaves (not
// in the original). A disk part's visit starts fresh, as a disk load does, and
// the menu starts over on every return (the loader reloads it).
//
// MUSIC (each from the disk's own replay, or mapped by YM register comparison):
//   SYNC #1  Jinks.sndh #1 (Mad Max). The part's replay (TFMX module at $36DF0)
//            wrapped as an SNDH and logged against Jinks #1 over 3000 frames:
//            99.9% of frames identical in periods and volumes at a 2-frame lag.
//   SYNC #2  Swedish_New_Year_Demo_Sync.sndh (Grazey's rip of this very screen's
//            4-voice sample replay, Timer A at 7680 Hz; FLAG ~ay is Timer A, not
//            STE DMA): 90% of its 32-byte windows are found verbatim in the
//            part's code and samples ($2C3FA..$31C00), the rest relocated code.
//   TCB #1   swedish_newyear_tcb_digi.sndh, HAND-BUILT from the disk: TCB #1
//            plays no tune but one sample byte a scanline (~15.65 kHz) through
//            a volume table into YM registers 8-10, the "TCB are the best"
//            speech 10 times then a loop of its stream. The SNDH plays the same
//            stream and table on Timer A at 15754 Hz (the nearest MFP rate);
//            1496 of 1500 frames' volumes are the modelled stream's. No SNDH in
//            the archive holds it (best candidates: none by name or composer).
//   TCB #2   dugger.sndh #4 at the start, #2/#3/#4 on F3/F4/F5 (Mad Max). The
//            part's replay (copied to $50600) wrapped as an SNDH: subtunes 1..4
//            identical to dugger.sndh's, 1.000 aligned at lag 0.
//   OMEGA    beyond_the_ice_palace.sndh #1 (David Whittaker). The part's replay
//            ($8BC4..$9C64, init d0 = 0) wrapped as an SNDH and logged against
//            it over 3000 frames: 1.000 of frames identical at lag 0.
//   menu     scout.sndh #1 (Mad Max, C64-Conversions/Scout)     hist 0.997, seq 0.94
//            (from the remake's .ym dump).
// Every SNDH is FLAG ~y except the Sync one and the TCB digi (~ay, Timer A).
// --------------------------------------------------------------------------
const zg = @import("zigos");
const frame = @import("swedish_newyear/frame.zig");
const Menu = @import("swedish_newyear/menu.zig").Menu;
const Sync = @import("swedish_newyear/sync.zig").Sync;
const Tcb = @import("swedish_newyear/tcb.zig").Tcb;
const Omega = @import("swedish_newyear/omega.zig").Omega;
const music = @import("swedish_newyear/music.zig");
const assets = @import("swedish_newyear/assets.zig");

const ZigOS = zg.ZigOS;

pub const Part = enum(u8) { menu, sync1, sync2, tcb1, tcb2, omega };

const K_SPACE: u32 = 32;
const K_ESC: u32 = 0xE012;
const K_F1: u32 = 0xE001;

pub const Demo = struct {
    part: Part,
    menu: Menu,
    sync: Sync,
    tcb: Tcb,
    omega: Omega,
    ym: *const [16]u8, // the YM registers the SNDH leaves: OMEGA's meters read them
    wants_quit: bool,
    loaded: ?assets.Set, // the part in the part buffer (null: none usable)

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        self.part = .menu;
        self.menu.init();
        self.ym = &zigos.ym_regs;
        self.wants_quit = false;
        self.loaded = null;
        frame.init(zigos);
        music.play(.scout);
    }

    pub fn update(_: *Demo, _: *ZigOS, _: f32) void {}

    pub fn render(self: *Demo, zigos: *ZigOS, dt: f32) void {
        const fb = &zigos.lfbs[0];
        switch (self.part) {
            .sync1, .sync2, .tcb1, .tcb2, .omega => return self.renderSt(fb, dt),
            .menu => {},
        }
        frame.st_mode = false;
        frame.flipColour0();
        frame.setBorders(.bottom);
        frame.clear();
        if (self.load()) self.menu.step();
        frame.present(fb);
        @memset(&frame.c0_next, frame.BLACK);
    }

    /// A part from the disk: it presents what it captured last frame, runs
    /// its VBLs and captures the next (st_show.zig).
    fn renderSt(self: *Demo, fb: *zg.LogicalFB, dt: f32) void {
        const px = fb.fb[0 .. frame.PW * frame.PH];
        if (!self.load()) {
            frame.st_mode = false;
            frame.setBorders(.closed);
            frame.clear();
            return frame.present(fb);
        }
        frame.st_mode = true;
        switch (self.part) {
            .sync1, .sync2 => {
                frame.setBorders(.closed);
                self.sync.frame(px, dt);
            },
            .omega => self.omega.frame(px, dt, self.levels()),
            else => if (self.tcb.frame(px, dt)) |n| music.play(.{ .dugger = n }),
        }
    }

    /// The part's data, depacked when it is first shown after a switch (two
    /// keys between frames depack once). A disk part starts over on its load.
    fn load(self: *Demo) bool {
        const set: assets.Set = switch (self.part) {
            .menu => .menu,
            .sync1, .sync2 => .sync,
            .tcb1, .tcb2 => .tcb,
            .omega => .omega,
        };
        if (self.loaded == set) return true;
        if (!assets.load(set)) {
            self.loaded = null;
            zg.Console.log("swedish_newyear: the {s} set does not depack", .{@tagName(set)});
            return false;
        }
        self.loaded = set;
        switch (set) {
            .sync => {
                self.sync.enter();
                if (self.part == .sync2) self.sync.toSecond(); // Space beat the load
            },
            .tcb => {
                self.tcb.enter();
                if (self.part == .tcb2) self.tcb.toSecond();
            },
            .omega => self.omega.enter(self.levels()),
            .menu => {},
        }
        return true;
    }

    pub fn key(self: *Demo, cp: u32) void {
        if (cp == K_ESC) {
            self.wants_quit = true;
            return;
        }
        if (cp == K_SPACE) return self.space();
        if (cp < K_F1 or cp > K_F1 + 4) return;
        const f: u8 = @intCast(cp - K_F1); // 0 = F1
        if (self.part == .tcb2) { // not loaded: self.tcb is a previous visit's
            if (self.loaded != .tcb) return;
            if (self.tcb.key(f)) |n| music.play(.{ .dugger = n });
            return;
        }
        if (self.part != .menu) return;
        switch (f) {
            0 => self.fromDisk(.sync1, .jinx1),
            1 => self.fromDisk(.tcb1, .tcb_digi),
            2 => self.fromDisk(.omega, .icepalace),
            else => {},
        }
    }

    fn space(self: *Demo) void {
        switch (self.part) {
            .tcb2, .omega, .sync2 => self.go(.menu, .scout),
            .tcb1 => {
                if (self.loaded == .tcb) self.tcb.toSecond();
                self.part = .tcb2; // the Dugger tune starts with its first frame
                zg.stopSong(); // TCB #1's exit ($E0C2) stops the sample stream
            },
            .sync1 => {
                if (self.loaded == .sync) self.sync.toSecond();
                self.part = .sync2;
                music.play(.sync2);
            },
            .menu => {},
        }
    }

    /// F1 / F2 / F3: the loader reads the part from the disk again. Loaded now,
    /// not on the next render: the first frame's borders (the global HBL) are
    /// painted from what the part's entry captures.
    fn fromDisk(self: *Demo, part: Part, tune: music.Tune) void {
        self.loaded = null;
        self.go(part, tune);
        _ = self.load();
    }

    /// YM registers 8, 9, 10: the voices' amplitudes.
    fn levels(self: *const Demo) [3]u8 {
        return self.ym[8..11].*;
    }

    fn go(self: *Demo, part: Part, tune: music.Tune) void {
        self.part = part;
        // The loader reads the menu from the disk again after every part, so
        // its scroller starts over (the remake's kept its place).
        if (part == .menu) self.menu.init();
        music.play(tune);
        // The key lands between frames and hwClear paints the borders BEFORE
        // the next frame runs: the menu has a black colour 0.
        if (part == .menu) @memset(&frame.c0_next, frame.BLACK);
    }
};
