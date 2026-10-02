// The intro ($24C + VBL $35E): INTRO.TNY's DUNE logo dropped down the screen
// and bounced, then the main part's set-up with the logo parked at the top.
//
// The VBL copies the picture's first 116 lines to line DROP[i] of the hidden
// screen and swaps; i walks 1..33 and back, one step a VBL, with a turn-round
// VBL at each end that draws nothing but STILL swaps -- so the screen from two
// VBLs back is shown for a frame (a flick back up at the bottom of the drop).
// A screen address written in a VBL is latched at the next one, so what is
// shown in a frame is the screen drawn in the VBL before.
//
// The bounce lasts as long as the main loop's busy wait (19 x 65536 dbra, with
// the VBL eating its share): 228 VBLs, measured in Hatari. Then the palette
// goes black, both screens are cleared and lines 10..110 of the picture are
// copied to lines 0..100 -- the logo at the very top -- and faded in; the logo
// then waits while ALPHA.DAT loads and its font is pre-shifted (165 VBLs in
// Hatari, floppy timing on) before the main part starts. The disk loads before
// the bounce happen on a black screen and are not kept.
const zg = @import("zigos");
const st = @import("st.zig");
const tny = @import("tny.zig");
const fade = @import("fade.zig");
const A = @import("assets.zig");

pub const BOUNCE_VBLS: u32 = 228;
pub const HOLD_VBLS: u32 = 165;
const LOGO_LINES = 116; // $35E copies $73 + 1 lines
const PARK_FROM = 10; // $FC: picture line 10 to screen line 0, 101 lines
const PARK_LINES = 101;
const LAST_STEP = 0x21;

pub const Intro = struct {
    n: u32, // VBLs since the cart started
    step: u8, // $1DBE
    down: bool, // $1DA4 > 0
    drawn: [2]?u8, // the line each screen's logo was drawn at
    hidden: u1,

    pub fn init(self: *Intro) void {
        self.n = 0;
        self.step = 0;
        self.down = true;
        self.drawn = .{ null, null };
        self.hidden = 0;
    }

    /// One VBL. True once the main part should start.
    pub fn vbl(self: *Intro) bool {
        self.n += 1;
        if (self.n <= fade.FRAMES) return false; // fading in on a cleared screen
        if (self.n <= fade.FRAMES + BOUNCE_VBLS) self.bounce();
        return self.n >= fade.FRAMES + BOUNCE_VBLS + fade.FRAMES + HOLD_VBLS;
    }

    fn bounce(self: *Intro) void {
        if (self.down) {
            if (self.step == LAST_STEP) self.down = false else self.drawAt(1);
        } else {
            if (self.step == 1) self.down = true else self.drawAt(-1);
        }
        self.hidden ^= 1; // swapped whether drawn or not
    }

    fn drawAt(self: *Intro, d: i8) void {
        self.step = @intCast(@as(i16, self.step) + d);
        self.drawn[self.hidden] = A.T.DROP[self.step];
    }

    pub fn render(self: *const Intro, fb: *zg.LogicalFB, pic: *const tny.Picture) void {
        st.clear(fb);
        const bounce_end = fade.FRAMES + BOUNCE_VBLS;
        if (self.n <= bounce_end) {
            st.setPalette(&pic.palette);
            // the screen drawn in the previous VBL is the one on show
            if (self.n > fade.FRAMES) if (self.drawn[self.hidden ^ 1]) |y| copyLines(fb, pic, 0, y, LOGO_LINES);
            if (self.n <= fade.FRAMES) st.setPalette(&BLACK);
            return;
        }
        const pal = fade.at(&pic.palette, self.n - bounce_end - 1);
        st.setPalette(&pal);
        copyLines(fb, pic, PARK_FROM, 0, PARK_LINES);
    }
};

const BLACK = [_]u16{0} ** 16;

/// Picture lines from..from+n to screen lines to.., as the movem copies do.
pub fn copyLines(fb: *zg.LogicalFB, pic: *const tny.Picture, from: usize, to: usize, n: usize) void {
    for (0..n) |i| {
        if (from + i >= tny.H or to + i >= st.H) break;
        @memcpy(st.row(fb, to + i), pic.px[(from + i) * tny.W ..][0..tny.W]);
    }
}
