// The B.I.G. Demo's screen: the instructions page, then the jukebox.
// A straight port of CODEF screen 23's wait() and go() (screen.js:390-492),
// halved to 320x270 and drawn into ONE overscan plane in the original's own
// compositing order — which is what go() does anyway, onto one canvas.
const std = @import("std");
const zg = @import("zigos");
const LogicalFB = zg.LogicalFB;
const A = @import("assets.zig");
const list = @import("list.zig");
const paint = @import("paint.zig");
const row = paint.row;

/// The current cycle tile, already repeated across the screen: a band costs 5
/// row builds and 20 row copies a frame, not a per-pixel fill of 6,400.
var band_rows: [A.CYCLE_H][A.W]u8 = undefined;

/// Repeat cycle tile `t`'s 5 rows across the full width, once for the frame.
fn expandBand(t: usize) void {
    const tile = A.cycle[t * A.CYCLE_H * A.CYCLE_W ..][0 .. A.CYCLE_H * A.CYCLE_W];
    for (&band_rows, 0..) |*dst, y| {
        const line = tile[y * A.CYCLE_W ..][0..A.CYCLE_W];
        var x: usize = 0;
        while (x < A.W) : (x += A.CYCLE_W) @memcpy(dst[x..][0..A.CYCLE_W], line);
    }
}

pub const Screen = struct {
    /// texbg, accumulated as go() does it: `texbg += 0.4` in DOUBLE precision.
    /// An integer floor(0.4n) is NOT the same sequence — 0.4 has no exact binary
    /// form, the sum drifts below each integer, and from frame 50 the original
    /// changes tile one frame later, every fifth frame. The drift is the effect.
    texbg: f64,
    /// go()'s frame count, mod A.FRAME_CYCLE — the port's copy of the real
    /// demo's gradient cursor at $BF18, which advances one word per frame.
    frame: u32,
    /// The Digital Solution's own, slower colour-cycle accumulator — NOT texbg.
    digital_cycle: f64,
    mytempo: u32, // wait()'s 200-frame counter
    bgscrposx: i32, // fontbg's scroll under the transparent scroller
    curent: usize, // the cursor: always the MIDDLE of the five rows
    curentlplay: usize, // the highlighted entry — the one that was selected
    // scrolltext_horizontal, in the original's 2x units so the numbers match
    posx: [A.LETTERS]i32,
    ltr: [A.LETTERS]u8,
    scroffset: usize,
    // main.png's rows that carry transparent holes (the three cycler windows);
    // every other row is a straight memcpy.
    holed: [A.H]bool,

    pub fn init(self: *Screen) void {
        self.frame = 0;
        self.texbg = 0;
        self.digital_cycle = 0;
        self.mytempo = 0;
        self.bgscrposx = 0;
        self.curent = 2;
        self.curentlplay = 2;
        self.scroffset = 0;
        for (&self.posx, &self.ltr, 0..) |*px, *lt, i| {
            px.* = A.RING + @as(i32, @intCast(i)) * A.FONT_W2;
            lt.* = A.scrolltext[self.scroffset];
            self.scroffset += 1;
        }
        for (&self.holed, 0..) |*h, y| {
            h.* = std.mem.indexOfScalar(u8, A.main_img[y * A.W ..][0..A.W], A.TRANSPARENT) != null;
        }
    }

    /// wait(): 200 frames of the instruction screen. True once it is over.
    pub fn waited(self: *Screen) bool {
        const was = self.mytempo; // if((mytempo++)>=200)
        self.mytempo += 1;
        return was >= 200;
    }

    pub fn drawWait(self: *Screen, fb: *LogicalFB) void {
        _ = self;
        for (0..A.H) |y| @memcpy(row(fb, y), A.wait_img[y * A.W ..][0..A.W]);
    }

    /// scrolltext_horizontal.draw() advances the letters BEFORE painting them,
    /// so go()'s very first frame already shows them one step in.
    /// Public because the Digital Solution (big/digital.zig) shows the SAME
    /// scroller and drives it the same way — advance, paint, scrollerTick — off
    /// this one Screen, so the text carries on across the swap.
    pub fn advance(self: *Screen) void {
        for (&self.posx, &self.ltr) |*px, *lt| {
            px.* -= A.SPEED2;
            if (px.* <= -A.FONT_W2) {
                px.* = A.RING + (px.* + A.FONT_W2);
                lt.* = A.scrolltext[self.scroffset];
                self.scroffset += 1;
                if (self.scroffset > A.scrolltext.len - 1) self.scroffset = 0;
            }
        }
    }

    /// The cycle tile showing this frame — go()'s own `Math.floor(texbg)%8`.
    fn tileOf(v: f64) usize {
        return @intFromFloat(@mod(@floor(v), @as(f64, @floatFromInt(A.CYCLE_TILES))));
    }
    pub fn cycleTile(self: *const Screen) usize {
        return tileOf(self.texbg);
    }

    /// texbg += 0.4, exactly go()'s accumulation, drift and all. Public because
    /// the Digital Solution keeps the jukebox's bands running while it is up.
    pub fn texbgTick(self: *Screen) void {
        self.texbg += A.CYCLE_STEP;
    }

    /// The Digital Solution's text cycle. SAME eight colours, SEPARATE and
    /// SLOWER accumulator — it is deliberately not `texbg`, and the two must
    /// not be "simplified" back into one: the jukebox's bands and this screen's
    /// text run at different rates on the real machine (Matt, 2026-09-19).
    /// Advanced only while that screen is up, so it carries on from where it
    /// was across visits, as the scrolltext does. (Whether the real screen
    /// restarts it on entry is not known.)
    pub fn digitalTile(self: *const Screen) usize {
        return tileOf(self.digital_cycle);
    }
    pub fn digitalTick(self: *Screen) void {
        self.digital_cycle += A.DIGITAL_CYCLE_STEP;
    }

    /// The fontbg diagonal's step: the other half of the scroller's state.
    pub fn scrollerTick(self: *Screen) void {
        self.bgscrposx -= 3; // if((bgscrposx-=3)<=-31) bgscrposx=0;
        if (self.bgscrposx <= -31) self.bgscrposx = 0;
    }

    /// go()'s tail (screen.js:488-490), run after the frame is painted.
    fn tick(self: *Screen) void {
        self.scrollerTick();
        self.texbgTick();
        // The rule pulse rides on this: an integer step per frame, kept inside
        // one ramp so the u32 can never wrap out from under it (A.FRAME_CYCLE).
        self.frame = (self.frame + 1) % A.FRAME_CYCLE;
    }

    // ArrowDown: if((curent++)>=mylist.length-3) curent=mylist.length-3;
    pub fn scrollDown(self: *Screen) void {
        const last = list.ENTRIES.len - 3;
        self.curent = if (self.curent >= last) last else self.curent + 1;
    }

    // ArrowUp: if((curent--)<=2) curent=2;
    pub fn scrollUp(self: *Screen) void {
        self.curent = if (self.curent <= 2) 2 else self.curent - 1;
    }

    /// Return: the highlight always moves; a row with no tune plays nothing.
    pub fn select(self: *Screen) void {
        self.play(self.curent);
    }

    /// Put the highlight on `idx` and start its tune. Leaving the Digital
    /// Solution calls this with whatever the jukebox was playing when the
    /// Digital Department row was chosen, so the list picks up where it left
    /// off instead of coming back silent (Matt, 2026-09-20).
    pub fn play(self: *Screen, idx: usize) void {
        self.curentlplay = idx;
        const e = list.ENTRIES[idx];
        if (e.song.len != 0) zg.requestSongTune(e.song, e.tune);
    }

    /// The transparent scroller, wherever it is asked for. Stays a method
    /// because the Digital Solution drives the SAME scroller off this Screen,
    /// 35 rows lower, so the text carries on across the swap.
    pub fn drawScrollerAt(self: *Screen, fb: *LogicalFB, y0: usize) void {
        paint.scroller(fb, y0, self.bgscrposx, &self.posx, &self.ltr);
    }

    /// One whole go(): advance the scroller, paint, then step the counters.
    pub fn go(self: *Screen, fb: *LogicalFB) void {
        self.advance();
        // cycler[Math.floor(texbg)%8].draw(mycanvas,0,498/378/104): each band is
        // cycle.png's tile i, tiled 10 across and 4 down. texbg += 0.4 a frame.
        expandBand(self.cycleTile());
        for (A.BAND_Y) |by| {
            for (0..A.BAND_H) |i| @memcpy(row(fb, by + i), &band_rows[i % A.CYCLE_H]);
        }
        // mymain.draw(mycanvas,0,0): opaque everywhere but the cycler windows.
        for (0..A.H) |y| {
            const src = A.main_img[y * A.W ..][0..A.W];
            const dst = row(fb, y);
            if (!self.holed[y]) {
                @memcpy(dst, src);
            } else {
                for (src, dst) |s, *d| {
                    if (s != A.TRANSPARENT) d.* = s;
                }
            }
        }
        self.drawScrollerAt(fb, A.SCROLL_Y);
        paint.shadows(fb);
        paint.listRows(fb, self.curent, self.curentlplay);
        // The two rules that bracket the cursor row. ONE live colour, stepped
        // one gradient word per frame: the same single palette write the real
        // HBL stage makes at display lines 92 and 100 (= content 107 and 115).
        fb.setPaletteEntry(A.PULSE, A.PULSE_RAMP[@as(usize, self.frame)]);
        for (A.RULE_Y) |ry| @memset(row(fb, ry), A.PULSE);
        self.tick();
    }



};
