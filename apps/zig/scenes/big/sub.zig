// The B.I.G. Demo's SUB-SCREENS and the plane they take turns owning.
//
// The main picture advertises "Hit 1...3 for Psych-O-Screens" and "Hit B for
// the B.I.G.-Scroller", and the demo's list has a Digital Department row. Five
// screens behind the jukebox, of which the CODEF remake implements none — its
// KeyCheck() (screen.js:33) binds neither key and has no Digital row at all.
//
// They do not share the jukebox's look, so each one owns the PLANE while it is
// up: its own palette, its own contents, its own idea of where the screen is
// inside the 400x280 buffer. Coming back means putting the menu's palette and
// side borders back, which is `restore` below.
//
// The transition is applied in DRAW, not in the key handler, because the cart
// ABI hands key() a codepoint and nothing else (apps/zig/demo_main.zig:253) —
// there is no framebuffer to switch at the moment the key arrives. So key()
// sets `mode` and the next frame notices. One place owns the plane, and it is
// the one that can see it.
const zg = @import("zigos");
const LogicalFB = zg.LogicalFB;
const A = @import("assets.zig");
const border = @import("border.zig");
const digital = @import("digital.zig");
const key1 = @import("key1.zig");
const keyb = @import("keyb.zig");
const key2 = @import("key2.zig");
const key3 = @import("key3.zig");
const Screen = @import("screen.zig").Screen;

pub const K_SPACE: u32 = 32;
const K_B: u32 = 'B';
const K_b: u32 = 'b';
const K_1: u32 = '1';
const K_2: u32 = '2';
const K_3: u32 = '3';

/// Which screen owns the frame.
pub const Mode = enum { jukebox, digital, key1, key2, key3, keyb };

pub const Sub = struct {
    mode: Mode,
    /// What is actually on the plane. Differs from `mode` for exactly one
    /// frame, between the key arriving and the next draw.
    shown: Mode,
    /// What the jukebox was playing when the Digital Department was opened.
    /// Its screen takes the sound chip over, so coming back has to hand it
    /// back rather than leave the list highlighting a tune nobody is playing.
    resume_to: usize,
    k1: key1.Key1,
    kb: keyb.KeyB,
    k2: key2.Key2,
    k3: key3.Key3,

    pub fn init(self: *Sub) void {
        self.mode = .jukebox;
        self.shown = .jukebox;
        self.resume_to = 0;
    }

    pub fn up(self: *const Sub) bool {
        return self.mode != .jukebox;
    }

    /// Paint the frame if a sub-screen owns it. True when it did, so the
    /// jukebox knows to stay out of the way.
    pub fn draw(self: *Sub, screen: *Screen, zigos: *zg.ZigOS) bool {
        const fb: *LogicalFB = &zigos.lfbs[0];
        if (self.shown != self.mode) {
            switch (self.mode) {
                .key1 => self.k1.enter(fb),
                .keyb => self.kb.enter(zigos, fb),
                .key2 => self.k2.enter(zigos, fb),
                .key3 => self.k3.enter(fb),
                .jukebox => restore(zigos, fb),
                .digital => {}, // draws over the jukebox's own palette
            }
            self.shown = self.mode;
        }
        switch (self.mode) {
            .jukebox => return false,
            .digital => digital.draw(screen, fb),
            .key1 => self.k1.draw(fb),
            .keyb => self.kb.draw(fb),
            .key2 => self.k2.draw(fb),
            .key3 => self.k3.draw(fb),
        }
        return true;
    }

    /// True when the key was the sub-screens' to handle. `running` gates the
    /// Psych-O-Screen keys to the jukebox proper: during wait() the picture
    /// that advertises them is not even on screen.
    pub fn key(self: *Sub, cp: u32, screen: *Screen, running: bool) bool {
        switch (self.mode) {
            .digital => {
                // Its 1-6 play the digi versions; Space comes back, and the
                // jukebox's own tune comes back with it.
                if (digital.key(cp)) {
                    self.mode = .jukebox;
                    screen.play(self.resume_to);
                }
                return true;
            },
            .key1, .key2, .key3, .keyb => {
                if (cp == K_SPACE) self.mode = .jukebox;
                return true;
            },
            .jukebox => {},
        }
        if (running) switch (cp) {
            K_1 => {
                self.mode = .key1;
                return true;
            },
            K_B, K_b => {
                self.mode = .keyb;
                return true;
            },
            K_2 => {
                self.mode = .key2;
                return true;
            },
            K_3 => {
                self.mode = .key3;
                return true;
            },
            else => {},
        };
        return false;
    }

    /// The Digital Department row opens its screen instead of playing. `playing`
    /// is the entry the jukebox had going, which Space puts back.
    pub fn enterDigital(self: *Sub, playing: usize) void {
        self.mode = .digital;
        self.resume_to = playing;
        digital.enter(); // the screen opens WITH its own music
    }
};

/// The jukebox's plane, rebuilt: palette, transparent pen, panel-grey ground
/// and the side borders. The next go() repaints the content over it.
fn restore(zigos: *zg.ZigOS, fb: *LogicalFB) void {
    // Key 2 replaces the plane's HBL with its own per-line palette handler, so
    // the flicker that holds the jukebox's borders open has to be put back.
    fb.openBorders(.all);
    zigos.setBackgroundColor(A.palette[A.PANEL]);
    fb.setPalette(A.palette);
    fb.setPaletteEntry(A.TRANSPARENT, zg.Color{ .r = 0, .g = 0, .b = 0, .a = 0 });
    fb.clearFrameBuffer(A.PANEL);
    border.paint(fb);
    border.paintRules(fb, A.PULSE);
}
