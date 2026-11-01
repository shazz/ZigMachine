// --------------------------------------------------------------------------
// The TOS console as the Empire's cracktro uses it (cracktro.zig): BIOS
// Cconout on the VT52 screen of ST low resolution, drawn straight into the
// plane as the ST screen would hold it (colour 0 paper, colour 15 ink).
//
// Only what the cracktro sends: printable characters in the 8x8 system font,
// CR, LF (scrolling at the bottom line), and ESC E (clear + home), ESC e
// (cursor on), ESC p / ESC q (reverse video), ESC D / ESC C (cursor left /
// right). Wrap is OFF, as TOS boots: a character at column 39 leaves the
// cursor there, so the 41-space bar of the original ends in column 39.
//
// The cursor is TOS's: an inverted cell, hidden around every output and shown
// again after it, with its blink count (V_PERIOD, 30 VBLs, line-A -$18)
// reloaded each time; the VBL toggles it when the count runs out. Measured in
// Hatari (TOS 1.62): V_PERIOD = $1E, and V_CUR_CT counts down a VBL at a time
// from the last character.
//
// Only cells that change are written (a glyph, the cursor's cell, the scroll).
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");

pub const COLS: u8 = 40;
pub const ROWS: u8 = 25;
pub const PAPER: u8 = 0;
pub const INK: u8 = 15;
/// V_PERIOD: the cursor blinks every 30 VBLs.
const PERIOD: u8 = 30;

/// é ($82) in the ST's 8x8 font, cut from the original's screen in Hatari
/// ("poupée", page 2): ZigOS's system font carries ASCII only.
const E_ACUTE = [8]u8{ 0x0C, 0x18, 0x00, 0x3C, 0x7E, 0x60, 0x3C, 0x00 };

pub const Screen = struct {
    fb: *zg.LogicalFB,
    /// ZigOS's 8x8 system font: one byte a pixel, 64 bytes a character.
    font: []const u8,
    cx: u8 = 0,
    cy: u8 = 0,
    reverse: bool = false,
    cursor_on: bool = false,
    /// The cursor's cell is inverted on the screen now.
    shown: bool = false,
    blink: u8 = PERIOD,
    esc: bool = false,
    /// An ESC E since the caller last looked: TOS clears the 32000 bytes in
    /// about a frame, so the program's next Vsync misses the coming VBL
    /// (measured in Hatari: $F7's clear + character + two Vsyncs = 3 VBLs).
    cleared: bool = false,

    /// Cconout: the cursor off, the byte, the cursor back on (blink reloaded).
    pub fn out(self: *Screen, c: u8) void {
        self.hide();
        self.put(c);
        if (self.cursor_on) self.show();
        self.blink = PERIOD;
    }

    pub fn outs(self: *Screen, s: []const u8) void {
        for (s) |c| self.out(c);
    }

    /// The VBL's cursor flash.
    pub fn vbl(self: *Screen) void {
        if (!self.cursor_on) return;
        self.blink -= 1;
        if (self.blink != 0) return;
        self.blink = PERIOD;
        self.invert(self.cx, self.cy);
        self.shown = !self.shown;
    }

    fn put(self: *Screen, c: u8) void {
        if (self.esc) return self.escape(c);
        switch (c) {
            27 => self.esc = true,
            10 => if (self.cy == ROWS - 1) self.scroll() else {
                self.cy += 1;
            },
            13 => self.cx = 0,
            0...9, 11, 12, 14...26, 28...31 => {},
            else => {
                self.glyph(c);
                if (self.cx < COLS - 1) self.cx += 1;
            },
        }
    }

    fn escape(self: *Screen, c: u8) void {
        self.esc = false;
        switch (c) {
            'E' => {
                self.fb.clearFrameBuffer(PAPER);
                self.cleared = true;
                self.cx = 0;
                self.cy = 0;
            },
            'e' => self.cursor_on = true,
            'p' => self.reverse = true,
            'q' => self.reverse = false,
            'D' => self.cx -|= 1,
            'C' => self.cx = @min(self.cx + 1, COLS - 1),
            else => {},
        }
    }

    fn glyph(self: *Screen, c: u8) void {
        const ink: u8 = if (self.reverse) PAPER else INK;
        const paper: u8 = if (self.reverse) INK else PAPER;
        for (0..8) |y| {
            const row = self.cell(self.cx, self.cy, y);
            for (0..8) |x| {
                const on = if (c == 0x82)
                    (E_ACUTE[y] >> @intCast(7 - x)) & 1 != 0
                else
                    self.font[(@as(usize, c) * 8 + y) * 8 + x] != 0;
                row[x] = if (on) ink else paper;
            }
        }
    }

    /// LF on the last line: everything up a text line, a blank line below.
    fn scroll(self: *Screen) void {
        const s: usize = self.fb.stride;
        const px = self.fb.fb[0 .. s * zg.HEIGHT];
        std.mem.copyForwards(u8, px[0 .. s * (zg.HEIGHT - 8)], px[s * 8 ..]);
        @memset(px[s * (zg.HEIGHT - 8) ..], PAPER);
    }

    fn hide(self: *Screen) void {
        if (!self.shown) return;
        self.invert(self.cx, self.cy);
        self.shown = false;
    }

    fn show(self: *Screen) void {
        if (self.shown) return;
        self.invert(self.cx, self.cy);
        self.shown = true;
    }

    fn invert(self: *Screen, cx: u8, cy: u8) void {
        for (0..8) |y| {
            for (self.cell(cx, cy, y)) |*p| p.* ^= INK;
        }
    }

    fn cell(self: *Screen, cx: u8, cy: u8, y: usize) *[8]u8 {
        const at = (@as(usize, cy) * 8 + y) * self.fb.stride + @as(usize, cx) * 8;
        return self.fb.fb[at..][0..8];
    }
};
