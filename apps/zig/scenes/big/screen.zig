// The B.I.G. Demo's screen: the instructions page, then the jukebox.
// A straight port of CODEF screen 23's wait() and go() (screen.js:390-492),
// halved to 320x270 and drawn into ONE overscan plane in the original's own
// compositing order — which is what go() does anyway, onto one canvas.
const std = @import("std");
const zg = @import("zigos");
const LogicalFB = zg.LogicalFB;
const A = @import("assets.zig");
const list = @import("list.zig");

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

/// The 320-byte slice of the plane that holds content row `y`.
inline fn row(fb: *LogicalFB, y: usize) []u8 {
    return fb.fb[(A.TOP + y) * A.STRIDE + A.LEFT ..][0..A.W];
}

pub const Screen = struct {
    /// texbg, accumulated as go() does it: `texbg += 0.4` in DOUBLE precision.
    /// An integer floor(0.4n) is NOT the same sequence — 0.4 has no exact binary
    /// form, the sum drifts below each integer, and from frame 50 the original
    /// changes tile one frame later, every fifth frame. The drift is the effect.
    texbg: f64,
    /// go()'s frame count, mod A.FRAME_CYCLE: fadecpt (+0.5)
    /// are read off it as integers, so neither drifts the way a float would.
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
        // fadecpt += 0.5 rides on this; 0.5 IS exact in binary, so the integer
        // count is the same sequence forever, and it is kept inside one cycle
        // so the u32 can never wrap out from under it (see A.FRAME_CYCLE).
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
        self.curentlplay = self.curent;
        const e = list.ENTRIES[self.curentlplay];
        if (e.song.len != 0) zg.requestSongTune(e.song, e.tune);
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
        self.drawShadows(fb);
        self.drawList(fb);
        // The two rules that bracket the cursor row, pulsing on fade[] at +0.5.
        const f = A.FADE[@divFloor(self.frame, 2) % 30];
        for (A.RULE_Y) |ry| @memset(row(fb, ry), f);
        self.tick();
    }

    /// The transparent scroller: the IN font is a MASK filled with the scrolling
    /// fontbg diagonal (canvas 'source-in'), the OUT font's outline over it.
    /// `y0` is the band's top row in content coordinates: A.SCROLL_Y for the
    /// jukebox, 35 lower for the Digital Solution. The fontbg diagonal is
    /// anchored to the GLYPH's row (what the jukebox's 0-px replay confirms)
    /// and repeats every 8 px, so drawing a band at another y is only a phase
    /// shift of it.
    pub fn drawScrollerAt(self: *Screen, fb: *LogicalFB, y0: usize) void {
        const phase = @divFloor(-self.bgscrposx, 2); // fontbg's offset, halved
        for (self.posx, self.ltr) |px, lt| {
            // -ME-'s text is not pure uppercase: it carries 2 TABs and 38
            // lowercase 'r's, which land on tile -23 and tile 82 of a 70-tile
            // font. drawTile feeds both to drawPart, which clips the source
            // rectangle to nothing outside the font image and paints NOTHING —
            // so skipping them is the original's behaviour, not a shortcut.
            if (lt < A.FIRST_CHAR) continue;
            const g: usize = lt - A.FIRST_CHAR;
            if (g >= A.GLYPHS) continue;
            var sx: usize = 0;
            var x = @divFloor(px, 2);
            var n: usize = A.GW;
            if (x < 0) {
                sx = @intCast(-x);
                if (sx >= A.GW) continue;
                n -= sx;
                x = 0;
            }
            const dx: usize = @intCast(x);
            if (dx >= A.W) continue;
            if (n > A.W - dx) n = A.W - dx;
            for (0..A.GH) |y| {
                const off = (g * A.GH + y) * A.GW + sx;
                const mask = A.fontin[off..][0..n];
                const line = A.fontout[off..][0..n];
                const dst = row(fb, y0 + y)[dx..][0..n];
                for (mask, line, dst, 0..) |m, o, *d, k| {
                    if (m != 0) {
                        const t = @as(i32, @intCast(dx + k)) + phase - @as(i32, @intCast(y));
                        d.* = A.FONTBG[@intCast(@mod(t, 8))];
                    }
                    if (o != A.TRANSPARENT) d.* = o;
                }
            }
        }
    }

    /// shadow.draw(mycanvas,0,447,0.5) / (...,500,0.5): an opaque grey at half
    /// alpha is exactly a palette lookup once the palette is fixed.
    fn drawShadows(self: *Screen, fb: *LogicalFB) void {
        _ = self;
        for (A.SHADOW_Y) |sy| {
            for (A.SHADOW_TONE, 0..) |tone, r| {
                const lut = A.shadow_lut[@as(usize, tone) * 256 ..][0..256];
                for (row(fb, sy + r)) |*d| d.* = lut[d.*];
            }
        }
    }

    /// Five entries around the cursor. The selected one is a filled bar with the
    /// font's own ink ('source-over'); the others are the bar colour showing
    /// through the glyphs only ('destination-in'). go() brackets these five
    /// draws with globalCompositeOperation='darker', which no longer exists in
    /// Canvas2D — an unknown op is ignored, so the rows land plain source-over.
    fn drawList(self: *Screen, fb: *LogicalFB) void {
        for (A.LIST_INK, 0..) |ink, k| {
            const idx = self.curent - 2 + k;
            const playing = idx == self.curentlplay;
            const y0 = A.LIST_Y + k * A.LIST_STEP;
            if (playing) {
                for (0..A.PH) |y| @memset(row(fb, y0 + y)[A.LIST_X..][0 .. A.LIST_COLS * A.PW], ink);
            }
            const glyph = if (playing) A.FONTP_INK else ink;
            for (list.ENTRIES[idx].label, 0..) |ch, i| {
                if (i >= A.LIST_COLS or ch < 32) continue;
                const g: usize = ch - 32;
                if (g >= A.P_GLYPHS) continue;
                const x0 = A.LIST_X + i * A.PW;
                for (0..A.PH) |y| {
                    const mask = A.fontp[(g * A.PH + y) * A.PW ..][0..A.PW];
                    const dst = row(fb, y0 + y)[x0..][0..A.PW];
                    for (mask, dst) |m, *d| {
                        if (m != 0) d.* = glyph;
                    }
                }
            }
        }
    }
};
