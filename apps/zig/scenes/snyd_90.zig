// --------------------------------------------------------------------------
// SWEDISH NEW YEAR DEMO 89-90 -- OMEGA, SYNC and THE CAREBEARS (Atari ST,
// released 01-01-1990; Demozoo 71913). Graphics, texts and music belong to
// their authors: the menu by TFE of OMEGA, graphics by Red of OMEGA, music by
// Mad Max. Not the 1989 demo (cart 76), though the same crews made both.
//
// Ported from the DISK (SNYD_90.MSA; prototypes/snyd90_re/NOTES.md). The boot
// sector decrypts a loader into $600 (a chained EOR keyed by the SR it reads);
// the loader's own FDC driver reads each part by sector from a table at $CA8
// and depacks it (ByteKiller, then a word-run pass). It runs the intro once,
// then loops: the menu, then the part its F-key picked, then the menu again,
// read from the disk afresh (so it starts over).
//
// Ported: the intro (a Spectrum 512 picture, intro.zig) and the menu
// (menu.zig, byte for byte against Hatari's RAM). The six parts behind F1..F6
// are not ported yet: their keys are ignored. The loader's "PLEASE WAIT,
// LOADING..." panel between parts is not shown (this machine depacks at once).
//
// Keys: intro Space -> menu (as $109C); Escape leaves (not in the original).
// Music: docs/music/snyd90.sndh, the menu's own COSO replay and module ($79C4,
// $4554 bytes) wrapped as an SNDH -- subtune 4 in the intro, 1 in the menu,
// as the two parts init it. No SNDH in the archive holds this module (best
// match: Mad Max's Stormlord, 155 of 352 module windows: shared instruments,
// a different song table and size).
// --------------------------------------------------------------------------
const zg = @import("zigos");
const st = @import("swedish_newyear/st.zig");
const shifter = @import("snyd_90/shifter.zig");
const assets = @import("snyd_90/assets.zig");
const intro = @import("snyd_90/intro.zig");
const menu = @import("snyd_90/menu.zig");

const ZigOS = zg.ZigOS;

pub const Part = enum(u8) { intro, menu };

const MUSIC = "snyd90.sndh";
const TUNE_INTRO = 4;
const TUNE_MENU = 1;
const K_SPACE: u32 = 32;
const K_ESC: u32 = 0xE012;

pub const Demo = struct {
    part: Part,
    r: st.Ram, // the menu's memory, $1000..$80000
    acc: f32, // host ms not yet run as 50 Hz VBLs
    wants_quit: bool,

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        assets.init();
        shifter.init(zigos);
        self.wants_quit = false;
        self.r = .{ .base = menu.BASE, .m = &.{} };
        self.toIntro();
    }

    pub fn update(_: *Demo, _: *ZigOS, _: f32) void {}

    pub fn render(self: *Demo, zigos: *ZigOS, dt: f32) void {
        shifter.present(&zigos.lfbs[0]);
        if (self.part != .menu or self.r.m.len == 0) return;
        self.acc += dt;
        var shown: ?u32 = null;
        while (self.acc >= st.VBL_MS) : (self.acc -= st.VBL_MS) shown = menu.iteration(&self.r);
        if (shown) |screen| shifter.captureScreen(&self.r, screen, menu.PALETTE);
    }

    pub fn key(self: *Demo, cp: u32) void {
        if (cp == K_ESC) {
            self.wants_quit = true;
            return;
        }
        if (self.part == .intro and cp == K_SPACE) self.toMenu();
    }

    fn toIntro(self: *Demo) void {
        self.part = .intro;
        zg.requestSongTune(MUSIC, TUNE_INTRO);
        const mem = assets.load(.intro) orelse return fault(.intro);
        intro.show(mem[0..intro.LEN]);
    }

    /// The loader reads the menu from the disk again: a fresh start.
    fn toMenu(self: *Demo) void {
        self.part = .menu;
        self.acc = 0;
        self.r.m = &.{};
        zg.requestSongTune(MUSIC, TUNE_MENU);
        const mem = assets.load(.menu) orelse return fault(.menu);
        self.r = .{ .base = menu.BASE, .m = mem[0 .. menu.TOP - menu.BASE] };
        menu.init(&self.r);
        shifter.captureScreen(&self.r, menu.iteration(&self.r), menu.PALETTE);
    }
};

/// A blob that does not depack is a build fault: say so, show black.
fn fault(set: assets.Set) void {
    zg.Console.log("snyd_90: the {s} part does not depack", .{@tagName(set)});
    shifter.blank(st.color(0));
}
