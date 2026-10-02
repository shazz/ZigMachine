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
// Ported: the intro (a Spectrum 512 picture, snyd_90/intro.zig), the menu
// (menu.zig) and F2, OMEGA's distorted logo and wave scroller (f2.zig), each
// checked byte for byte against the original (Hatari RAM, or the original
// code on a Musashi oracle that matches it). F1 and F3..F6 are not ported:
// the menu ignores those keys. The loader's "PLEASE WAIT, LOADING..." panel
// between parts is not shown (this machine depacks at once).
//
// Keys: intro Space -> menu ($109C); menu F2 -> F2; F2 Space -> menu ($6828,
// on the key's release there); Escape leaves (not in the original).
// Music: each part's own replay wrapped as an SNDH (snyd_90/parts.zig).
// --------------------------------------------------------------------------
const zg = @import("zigos");
const st = @import("swedish_newyear/st.zig");
const shifter = @import("snyd_90/shifter.zig");
const assets = @import("snyd_90/assets.zig");
const intro = @import("snyd_90/intro.zig");
const parts = @import("snyd_90/parts.zig");

const ZigOS = zg.ZigOS;

const INTRO_MUSIC = "snyd90.sndh";
const INTRO_TUNE = 4; // the intro inits the menu's module with d0 = 4
const K_SPACE: u32 = 32;
const K_ESC: u32 = 0xE012;
const K_F1: u32 = 0xE001;

pub const Demo = struct {
    running: ?parts.Running, // null: the intro (or a part that did not depack)
    acc: f32, // host ms not yet run as 50 Hz VBLs
    wants_quit: bool,

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        assets.init();
        shifter.init(zigos);
        self.wants_quit = false;
        self.running = null;
        self.acc = 0;
        zg.requestSongTune(INTRO_MUSIC, INTRO_TUNE);
        const mem = assets.load(.intro) orelse return fault(.intro);
        intro.show(mem[0..intro.LEN]);
    }

    pub fn update(_: *Demo, _: *ZigOS, _: f32) void {}

    pub fn render(self: *Demo, zigos: *ZigOS, dt: f32) void {
        shifter.present(&zigos.lfbs[0]);
        const p = &(self.running orelse return);
        self.acc += dt;
        while (self.acc >= st.VBL_MS) {
            self.acc -= st.VBL_MS;
            p.vbl(self.acc < st.VBL_MS);
        }
    }

    pub fn key(self: *Demo, cp: u32) void {
        if (cp == K_ESC) {
            self.wants_quit = true;
            return;
        }
        const id: ?parts.Id = if (self.running) |p| p.id else null;
        if (id == null and cp == K_SPACE) return self.start(.menu); // the intro
        if (id == .menu and cp == K_F1 + 1) return self.start(.f2);
        if (id == .f2 and cp == K_SPACE) return self.start(.menu);
    }

    /// The loader reads a part from the disk and jumps in: a fresh start.
    fn start(self: *Demo, id: parts.Id) void {
        self.running = null;
        self.acc = 0;
        const t = parts.tune(id);
        zg.requestSongTune(t.file, t.n);
        const mem = assets.load(parts.set(id)) orelse return fault(parts.set(id));
        self.running = parts.Running.enter(id, mem);
    }
};

/// A blob that does not depack is a build fault: say so, show black.
fn fault(set: assets.Set) void {
    zg.Console.log("snyd_90: the {s} part does not depack", .{@tagName(set)});
    shifter.blank(st.color(0));
}
