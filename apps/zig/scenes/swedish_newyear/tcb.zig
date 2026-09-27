// --------------------------------------------------------------------------
// The TCB load (F2 on the menu): TCB #1, then Space, TCB #2 -- both on the
// part's own memory (st.zig) at the original's 50 Hz, one VBL every 20 ms of
// host time, as sync.zig runs SYNC. Every F2 is a fresh start (a disk load).
//
// Between the two: Space ends TCB #1 and TCB #2's set-up runs, which on the ST
// takes 73 VBLs from the key's release to the first frame (measured in
// Hatari) with a black screen at its end -- here those VBLs are black. (For
// the first few of them the ST still shows TCB #1's last noise with a grey
// colour 0, left by its exit; not reproduced.) The Dugger tune starts with
// the first frame, as the set-up's last step starts it.
// --------------------------------------------------------------------------
const st = @import("st.zig");
const show = @import("st_show.zig");
const fr = @import("frame.zig");
const tcb1 = @import("tcb1.zig");
const tcb1_show = @import("tcb1_show.zig");
const tcb2 = @import("tcb2.zig");
const assets = @import("assets.zig");
const ram = @import("ram.zig");

pub const VBL_MS: f32 = 20;
/// VBLs from Space (released) to TCB #2's first frame.
const SETUP_VBLS = 73;
/// TCB #2's tune at its start: Dugger subtune 4.
pub const FIRST_TUNE: u8 = 4;

pub const Tcb = struct {
    r: st.Ram,
    one: tcb1.Tcb1,
    second: bool, // TCB #2
    setup: u32, // TCB #2's set-up VBLs still to go
    running: bool, // TCB #2's frames have started
    shown: tcb2.Shown,
    overscan: bool, // what was captured: TCB #1's fullscreen plane
    borders: fr.Borders, // ... and the borders it needs
    acc: f32,

    /// The part's tracks are in the part buffer (assets.load(.tcb)).
    pub fn enter(self: *Tcb) void {
        const part = ram.buf.part[0..assets.TCB_RAM];
        @memset(part[assets.TCB_IMAGE..], 0);
        self.r = .{ .base = tcb1.BASE, .m = part };
        self.one.init(&self.r);
        self.second = false;
        self.acc = 0;
        self.one.vbl(&self.r);
        self.capture();
    }

    /// Space in TCB #1.
    pub fn toSecond(self: *Tcb) void {
        tcb2.init(&self.r);
        tcb2.resetKeyboard();
        self.second = true;
        self.setup = SETUP_VBLS;
        self.running = false;
        self.capture();
    }

    /// One host frame. Returns a Dugger subtune to start when TCB #2's first
    /// frame runs.
    pub fn frame(self: *Tcb, fb: []u8, dt: f32) ?u8 {
        fr.setBorders(self.borders);
        if (self.overscan) show.presentOverscan(fb) else show.present(fb);
        var tune: ?u8 = null;
        self.acc += dt;
        while (self.acc >= VBL_MS) : (self.acc -= VBL_MS) {
            if (self.vbl()) tune = FIRST_TUNE;
        }
        self.capture();
        return tune;
    }

    /// F1..F5 (0..4) in TCB #2: a subtune to restart, or null.
    pub fn key(self: *Tcb, f: u8) ?u8 {
        if (!self.second or self.setup != 0) return null;
        return tcb2.key(&self.r, f);
    }

    /// One VBL; true on TCB #2's first frame.
    fn vbl(self: *Tcb) bool {
        if (!self.second) {
            self.one.vbl(&self.r);
            return false;
        }
        if (self.setup > 0) {
            self.setup -= 1;
            return false;
        }
        const first = !self.running;
        self.shown = tcb2.frame(&self.r);
        self.running = true;
        return first;
    }

    fn capture(self: *Tcb) void {
        if (!self.second) {
            tcb1_show.capture(&self.one, &self.r);
            self.overscan = true;
            self.borders = self.one.borders();
            return;
        }
        self.overscan = false;
        self.borders = .closed;
        var pal: show.Palettes = undefined;
        var top: u16 = 0;
        var bottom: u16 = 0;
        if (!self.running) { // the set-up: black
            for (&pal) |*line| @memset(line, 0);
            return show.capture(&self.r, self.r.l(tcb2.DRAWN), &pal, 0, 0);
        }
        tcb2.palettes(&self.r, self.shown, &pal, &top, &bottom);
        show.capture(&self.r, self.shown.screen, &pal, top, bottom);
    }
};
