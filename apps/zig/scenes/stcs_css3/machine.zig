// --------------------------------------------------------------------------
// The intro's machine state: the ST screen, the raster tables, the stars and
// every state word, set exactly as the program leaves them at the start of the
// star release ($1F2). The per-frame routines live in raster.zig, scroller.zig
// and columns.zig and work on this, byte for byte, as the 68000 did.
// --------------------------------------------------------------------------
const std = @import("std");
const A = @import("assets.zig");

/// $F8000, the screen: module scope, it is the cart's and not the Demo's.
pub var screen: [A.SCREEN_BYTES]u8 = undefined;
/// The four scroll buffers ($1B452, $1DE52, $20852, $23252), 19 lines each.
pub var bufs: [4][A.BUF_BYTES]u8 = undefined;

pub const STARS: usize = 100;
/// The raster region is kept as bytes at its own addresses ($D3FE..$D668):
/// the up rotation writes one word just past P15 ($D61E), as the original does.
pub const RASTER_BASE: u16 = 0xD3FE;

/// XBIOS Random (TOS 1.x): s = s * 3141592621 + 1, r = (s >> 8) & $FFFFFF.
/// The seed is TOS's own boot state; $EF7 is the one low-16-bit state that
/// reproduces the Hatari run's 100 speeds and 50 untouched x words (the
/// program reads only r & $FF, which the low 16 bits alone decide).
pub const TOS_RANDOM_SEED: u32 = 0x0000_0EF7;

pub const Machine = struct {
    raster: [A.raster.len]u8,
    bar_up: bool, // $E71C
    warp: u16, // $E71E, added to every star's speed
    star_x: [STARS]u16, // $E556 + 2*d6: star d6 is on line 159 - d6
    star_speed: [STARS]u16, // $E48A + 2*d6: live, 0 until released
    star_release: [STARS]u16, // $E3C2 + 2*d6: the speeds the release copies in
    released: usize,
    stars_on: bool, // $828's first opcode: nop = on, rts = off
    columns_on: bool, // $930
    scroller_on: bool, // $CAE
    columns_calls: u16, // $E718
    letter: u16, // $E712, the letter drawn next
    path: u16, // $E714
    backward: bool, // $E71A
    letter_x: [4]u8, // $D3EA
    letter_y: [4]u8, // $D3EE
    text_at: u16, // $E7AC
    phase: u16, // $E7AE
    half: u16, // $E7B0: 0 or 8, which 16 px of the glyph the columns come from
    glyph_cur: u32, // $E7B2, as an offset into the font
    glyph_next: u32, // $E7B6
    cols: [8][A.SCROLL_LINES]u32, // $E7BE + $108*n: planes 0+1, one long a line

    pub fn init(self: *Machine) void {
        @memcpy(&screen, A.screen);
        for (&bufs, 0..) |*b, i| @memcpy(b, A.scrollbuf[i * A.BUF_BYTES ..][0..A.BUF_BYTES]);
        @memcpy(&self.raster, A.raster);
        self.bar_up = false;
        self.warp = 0;
        self.seedStars();
        @memset(&self.star_speed, 0);
        self.released = 0;
        self.stars_on = true;
        self.columns_on = true;
        self.scroller_on = false;
        self.columns_calls = 0;
        self.letter = 0;
        self.path = 0;
        self.backward = false;
        self.letter_x = .{ 144, 144, 144, 144 }; // where $A7C lifted them from
        self.letter_y = .{ 50, 67, 84, 101 };
        self.text_at = 0;
        self.phase = 0;
        self.half = 0;
        self.glyph_cur = 0;
        self.glyph_next = 0;
        for (&self.cols) |*c| @memset(c, 0);
    }

    /// $1A2: 100 Random values written downwards from $E6E6 as word pairs
    /// (lower (r&$FF)+(r&$7F), upper r&$FF), and the speeds (r&3)+1 below
    /// $E48A. The live x table is the first 100 of the 200 words, so star d6
    /// takes random 99 - d6/2: the lower word when d6 is even, else the upper.
    fn seedStars(self: *Machine) void {
        var s: u32 = TOS_RANDOM_SEED;
        for (0..STARS) |i| {
            s = s *% 3141592621 +% 1;
            const r: u16 = @truncate(s >> 8);
            const b = r & 0xFF;
            self.star_release[STARS - 1 - i] = (b & 3) + 1;
            if (i >= STARS / 2) {
                const d6 = 2 * (STARS - 1 - i);
                self.star_x[d6] = b + (r & 0x7F);
                self.star_x[d6 + 1] = b;
            }
        }
    }

    /// One $1F2 iteration: the next speed goes live, star 99 (line 60) first.
    pub fn releaseStar(self: *Machine) void {
        const d6 = STARS - 1 - self.released;
        self.star_speed[d6] = self.star_release[d6];
        self.released += 1;
    }

    /// $82A (vbl slot 0, plane 3): one star a line from 60 to 159. The wrap
    /// subtracts 319, not 320.
    pub fn stars(self: *Machine) void {
        if (!self.stars_on) return;
        var line: usize = 0x1F46 + 0x640;
        var d6: usize = STARS;
        while (d6 > 0) {
            d6 -= 1;
            var x = self.star_x[d6];
            plot(line, x, false);
            x +%= self.star_speed[d6] +% self.warp;
            if (@as(i16, @bitCast(x)) > 0x13F) x -%= 0x13F;
            plot(line, x, true);
            self.star_x[d6] = x;
            line += A.LINE;
        }
    }

    pub fn rasterWord(self: *const Machine, addr: u16) u16 {
        return A.be16(&self.raster, addr - RASTER_BASE);
    }
    pub fn setRasterWord(self: *Machine, addr: u16, v: u16) void {
        A.put16(&self.raster, addr - RASTER_BASE, v);
    }
    pub fn rasterByte(self: *const Machine, addr: u16) u8 {
        return self.raster[addr - RASTER_BASE];
    }
};

/// bclr/bset on the word at line + ((x>>1) & $F8), bit 15 - (x & 15). x may
/// start past 319 (up to 382), which lands in the next line's first groups.
fn plot(line: usize, x: u16, set: bool) void {
    const a = line + ((x >> 1) & 0xF8);
    const bit: u16 = @as(u16, 1) << @intCast(15 - (x & 15));
    const w = A.be16(&screen, a);
    A.put16(&screen, a, if (set) w | bit else w & ~bit);
}
