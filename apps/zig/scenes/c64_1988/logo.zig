// --------------------------------------------------------------------------
// Part 1 ($5300): Elko's skull logo, 8 x 9 multicoloured sprites bobbing on two sines, and a
// proportional scroller of X-expanded hires sprites in the top AND bottom borders (both
// borders open: $D011's RSEL dropped to 24 rows on line 250, before the bottom compare).
//
// One frame of the IRQ chain, as the original runs it (lines/cycles from VICE traces):
//   line 0     the 8 sprites to Y $10: the top scroller (still holding the bottom one's X,
//              pointers and colours from line 250), then the scroller steps (scroll.zig)
//   line 36/37 stable IRQ: hires off, multicolour on, the frame counter, the colours (or the
//              fade, or the end), then the logo's X, MSB, Y and row 0's pointers
//   rows 1..8  one IRQ each, 20 lines apart: Y += 21 and the row's 8 pointers. The row's IRQ
//              lands 2 or 3 lines before its writes depending on its bad-line phase, so a
//              row's pointers often switch while the previous row still shows its last lines:
//              Elko drew the logo for that (logo_rows.zig carries the measured offsets)
//   row 9      pointers 0, Y $0A (line 266), X-expansion on, multicolour off
//   line 250   RSEL off (opens the bottom border), white, the scroller's pointers, X and MSB,
//              the music ($1003)
// --------------------------------------------------------------------------
const vic = @import("vic.zig");
const T = @import("tables.zig");
const Data = @import("data.zig").Data;
const Scroll = @import("scroll.zig").Scroll;
const rows = @import("logo_rows.zig");

const PTR0 = vic.PTR0;
pub const END_COUNT: u16 = 0x640; // 1600 frames, then the fade

pub const Logo = struct {
    text_idx: u8 = 0, // $6000: which text this run scrolls (0, 1, 2, ...)
    scroll: Scroll = .{},
    xi: u8 = 0, // $03: logo X sine index
    yi: u8 = 0, // $04: logo Y sine index
    fade_steps: u8 = 6, // $608D
    fade_wait: u8 = 6, // $608E
    fade_idx: u8 = 0, // $60A1

    /// The init's first frame ($5300 up to its wait for line 256): black, 25 rows.
    pub fn initA(_: *Logo, q: *vic.Queue, line: u16) void {
        q.at(line, 31, 0x21, 0);
        q.at(line, 35, 0x20, 0);
        q.at(line, 41, 0x11, 0x18);
    }

    /// The init's second frame: VIC bank 3, screen $F000 (cleared: the pointers go to 0
    /// while the loop passes $F3F8), sprite set-up, the text copied, IRQ at line 0.
    pub fn initB(self: *Logo, q: *vic.Queue, d: Data) void {
        q.at(0, 14, vic.BANK, 0x60);
        q.at(0, 20, 0x18, 0xC0);
        const clear = [8]u16{ 103 * 63 + 55, 104 * 63 + 59, 105 * 63 + 21, 105 * 63 + 46, 106 * 63 + 8, 106 * 63 + 33, 106 * 63 + 58, 107 * 63 + 20 };
        for (clear, 0..) |t, s| q.at(0, t, PTR0 + @as(u8, @intCast(s)), 0);
        for ([_]u8{ 0x1D, 0x17, 0x1B }, 0..) |r, i| q.at(107, 30 + 4 * @as(u16, @intCast(i)), r, 0);
        q.at(107, 44, 0x1C, 0xFF);
        q.at(107, 50, 0x25, 0x0B);
        q.at(107, 56, 0x26, 0x0F);
        for (0..8) |s| q.at(107, 62 + 4 * @as(u16, @intCast(s)), 0x27 + @as(u8, @intCast(s)), 0x0C);
        for (0..8) |s| q.at(108, 33 + 4 * @as(u16, @intCast(s)), 1 + 2 * @as(u8, @intCast(s)), 0x35);
        q.at(109, 4, 0x15, 0xFF);
        q.at(153, 23, 0x11, 0x18);
        self.xi = 0;
        self.yi = 0;
        self.fade_steps = 6;
        self.fade_wait = 6;
        self.fade_idx = 0;
        self.scroll.start(d.text(self.text_idx), d.textLen(self.text_idx));
    }

    /// One frame of the chain. Returns true on the frame the part ends (after line 38).
    pub fn frame(self: *Logo, q: *vic.Queue, counter: *u16, d: Data) bool {
        for (0..8) |s| q.at(0, 31 + 4 * @as(u16, @intCast(s)), 1 + 2 * @as(u8, @intCast(s)), 0x10);
        self.scroll.step(d.glyphCut());
        q.at(2, 30, 0x11, 0x18);
        q.at(3, 1, 0x11, 0x18);
        q.at(38, 1, 0x1D, 0);
        q.at(38, 7, 0x1C, 0xFF);
        var late: u16 = 0; // the fade routine delays the rest of the handler
        if (counter.* == END_COUNT) {
            if (self.fade_steps == 0) return self.end(q);
            self.fade(q, d.logoFade());
            late = 45;
        } else {
            counter.* += 1;
            colours(q, 38 * 63 + 31, 0x0B, 0x0F, 0x0C);
        }
        const base = self.logoTop(q, late);
        rows.chain(q, base);
        self.bottom(q);
        return false;
    }

    fn end(self: *Logo, q: *vic.Queue) bool {
        q.at(38, 47, vic.BANK, 0x63);
        q.at(38, 53, 0x18, 0x18);
        self.text_idx = if (self.text_idx == 2) 0 else self.text_idx + 1;
        return true;
    }

    // L5E8E: one step of the logo's fade every 7 frames ($608E counts 6..0).
    fn fade(self: *Logo, q: *vic.Queue, f: *const [18]u8) void {
        const y = self.fade_idx;
        colours(q, 38 * 63 + 49, f[y], f[6 + y], f[12 + y]);
        if (self.fade_wait != 0) {
            self.fade_wait -= 1;
        } else {
            self.fade_idx += 1;
            self.fade_steps -= 1;
            self.fade_wait = 6;
        }
    }

    // L5763: the logo's Y (row 0 top) and X for this frame, its MSB, row 0's pointers.
    fn logoTop(self: *Logo, q: *vic.Queue, late: u16) u8 {
        const base = T.logo_y[self.yi];
        self.yi = if (self.yi == 39) 0 else self.yi + 1;
        const x0: u16 = T.logo_x[self.xi];
        self.xi = if (self.xi == 99) 0 else self.xi + 1;
        var msb: u8 = 0;
        for (0..8) |s| {
            const x = x0 + 24 * @as(u16, @intCast(s));
            q.at(42, 9 + late + 20 * @as(u16, @intCast(s)), 2 * @as(u8, @intCast(s)), @truncate(x));
            msb |= @as(u8, @intCast(x >> 8)) << @intCast(s);
        }
        q.at(45, 17 + late, 0x10, msb);
        for (0..8) |s| q.at(45, 24 + late + 4 * @as(u16, @intCast(s)), 1 + 2 * @as(u8, @intCast(s)), base);
        rows.pointers(q, 45 * 63 + 60 + late, 0);
        return base;
    }

    // Line 250: the bottom border opens; the scroller's glyphs, X and MSB; the music.
    fn bottom(self: *Logo, q: *vic.Queue) void {
        q.at(250, 32, 0x11, 0x10);
        for (0..8) |s| q.at(250, 38 + 4 * @as(u16, @intCast(s)), 0x27 + @as(u8, @intCast(s)), 1);
        for (0..8) |s| q.at(251, 10 + 7 * @as(u16, @intCast(s)), PTR0 + @as(u8, @intCast(s)), self.scroll.ptr[s]);
        var msb: u8 = 0;
        for (0..8) |s| {
            const t: u16 = @intCast(s);
            const x = T.scroll_x[self.scroll.idx[s]];
            q.at(252, 7 + 11 * t, 2 * @as(u8, @intCast(s)), @truncate(x));
            msb |= @as(u8, @intCast(x >> 8)) << @intCast(s);
        }
        q.at(254, 50, 0x10, msb);
        q.at(259, 35, 0x11, 0x10);
    }
};

// $D025, $D026 and $D027-$D02E from cycle `t` of the frame (4 cycles a store).
fn colours(q: *vic.Queue, t: u16, mc1: u8, mc2: u8, spr: u8) void {
    q.at(0, t, 0x25, mc1);
    q.at(0, t + 6, 0x26, mc2);
    for (0..8) |s| q.at(0, t + 12 + 4 * @as(u16, @intCast(s)), 0x27 + @as(u8, @intCast(s)), spr);
}
