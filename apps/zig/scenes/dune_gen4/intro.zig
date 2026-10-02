// The intro ($24C + VBL $35E): INTRO.TNY's DUNE logo dropped down the screen
// and bounced, then the main part's set-up with the logo parked at the top.
//
// The VBL copies the picture's first 116 lines to line DROP[i] of the hidden
// screen and swaps; i walks 1..33 and back, one step a VBL, with a turn-round
// VBL at each end that draws nothing but STILL swaps -- so the screen from two
// VBLs back is shown for a frame (the logo flicks back up at the bottom). A
// screen address written in a VBL is latched at the next one: what a frame
// shows is the screen drawn in the VBL before. (Hatari, frame by frame.)
//
// Timeline, measured in Hatari (prototypes/dune_gen4_re/NOTES.md): the bounce
// lasts as long as the main loop's busy wait, 229 VBLs; then the palette goes
// black, both screens are cleared and lines 10..110 of the picture copied to
// lines 0..100 -- the logo at the very top -- which is faded in; the logo then
// waits while ALPHA.DAT loads and its font is pre-shifted, and the main part's
// first VBL comes 182 VBLs after the bounce's last. The disk loads before the
// bounce happen on a black screen and are left out; the intro's own fade-in
// runs on a cleared screen, so it is kept as black.
const zg = @import("zigos");
const st = @import("st.zig");
const tny = @import("tny.zig");
const fade = @import("fade.zig");
const A = @import("assets.zig");

pub const BOUNCE_VBLS: u32 = 229;
const PREP_VBLS: u32 = 4; // clearing both screens, copying the logo twice (Hatari)
const TO_MAIN_VBLS: u32 = 182; // last bounce VBL -> the main part's first
const LOGO_LINES = 116; // $35E copies $73 + 1 lines
pub const PARK_FROM = 10; // $FC: picture line 10 to screen line 0, 101 lines
pub const PARK_LINES = 101;
const LAST_STEP = 0x21;

/// The intro fades INTRO.TNY in on a cleared screen: black, as long as a fade.
const START_BLACK = fade.MAIN.frames();
const BOUNCE_END = START_BLACK + BOUNCE_VBLS;
const FADE_START = BOUNCE_END + PREP_VBLS;

pub const Intro = struct {
    n: u32, // VBLs since the cart started
    step: u8, // $1DBE
    up: bool, // $1DA4 > 0: the step grows, the logo rises
    drawn: [2]?u8, // the line each screen's logo was drawn at
    hidden: u1,

    pub fn init(self: *Intro) void {
        self.n = 0;
        self.step = 0;
        self.up = true;
        self.drawn = .{ null, null };
        self.hidden = 0;
    }

    /// One VBL. True when it is the main part's first instead.
    pub fn vbl(self: *Intro) bool {
        self.n += 1;
        if (self.n > START_BLACK and self.n <= BOUNCE_END) self.bounce();
        return self.n == BOUNCE_END + TO_MAIN_VBLS;
    }

    fn bounce(self: *Intro) void {
        if (self.up) {
            if (self.step == LAST_STEP) self.up = false else self.drawAt(1);
        } else {
            if (self.step == 1) self.up = true else self.drawAt(-1);
        }
        self.hidden ^= 1; // swapped whether drawn or not
    }

    fn drawAt(self: *Intro, d: i8) void {
        self.step = @intCast(@as(i16, self.step) + d);
        self.drawn[self.hidden] = A.T.DROP[self.step];
    }

    pub fn render(self: *const Intro, fb: *zg.LogicalFB, pic: *const tny.Picture) void {
        st.clear(fb);
        if (self.n <= START_BLACK or (self.n > BOUNCE_END and self.n <= FADE_START)) {
            return st.setPalette(&BLACK);
        }
        if (self.n <= BOUNCE_END) {
            st.setPalette(&pic.palette);
            // on show: the screen the VBL before drew (the swap just made
            // the other one hidden again)
            if (self.drawn[self.hidden]) |y| st.copyRows(fb, &pic.px, 0, y, LOGO_LINES);
            return;
        }
        const pal = fade.at(&pic.palette, self.n - FADE_START, fade.MAIN);
        st.setPalette(&pal);
        st.copyRows(fb, &pic.px, PARK_FROM, 0, PARK_LINES);
    }
};

const BLACK = [_]u16{0} ** 16;
