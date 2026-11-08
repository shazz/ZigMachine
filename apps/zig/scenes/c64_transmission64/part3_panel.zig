// --------------------------------------------------------------------------
// Part 3's info panel (VIC bank 3: screen $CC00, charset $D000): rolled in row by row
// ($3E52: each row written 5 times, its codes + 4, +3 .. +0, codes 0 left alone: the charset
// holds each glyph's squashed versions after it), held, rolled out ($3F3D: + 1 .. + 4, then
// the row cleared), with the border flashes around it ($3DC1 in, $4016 out: $3E43's colours).
// $3A05 runs beside them: the globe, 11 frames of 16+16 bytes from $DE00 into chars $72 and $77
// ($D390/$D3B8).
// The ADCs keep their carry along a row (one CLC per row), as the 6510 did.
// --------------------------------------------------------------------------
pub const FLASH = [15]u8{ 0x00, 0x0B, 0x06, 0x04, 0x0E, 0x03, 0x07, 0x01, 0x07, 0x03, 0x0E, 0x04, 0x06, 0x0B, 0x00 }; // $3E43
const CODES = 0xD600;
const SCREEN = 0xCC00;
const COLOURS = 0xFB00;

pub const Panel = struct {
    flash_x: u8 = 0, // $3DE9
    in_done: bool = false, // $3E70
    in_k: u8 = 4, // $3E87
    in_row: u8 = 0, // $3EA3
    holding: bool = false, // $3EF9
    hold: u8 = 0xFA, // $3F00: 250 frames held
    out_k: u8 = 1, // $3F65
    out_row: u8 = 0, // $3F90
    out_done: bool = false, // $3FE1
    back_x: u8 = 4, // $403E
    back_state: u8 = 1, // $405B
    anim_tick: u8 = 10, // $3A1D
    anim_left: u8 = 11, // $3A45
    anim_off: u16 = 0, // $3A0A/$3A10: from $DE00 and $DEB0

    /// $3E52's copy: row `in_row` with the current offset. Returns true when the hold ends.
    pub fn rollIn(self: *Panel, ram: *[65536]u8, col: *[1024]u8) bool {
        if (!self.in_done) {
            const o = @as(usize, self.in_row) * 40;
            for (0..40) |x| col[o + x] = ram[COLOURS + o + x] & 15;
            rowCodes(ram, o, self.in_k);
            self.in_k -%= 1;
            if (self.in_k == 0xFF) {
                self.in_k = 4;
                self.in_row += 1;
                if (self.in_row == 25) {
                    self.in_row = 0;
                    self.in_done = true;
                    self.holding = true;
                }
            }
        }
        if (self.holding) {
            self.hold -= 1;
            if (self.hold == 0) {
                self.hold = 0xFA;
                self.in_done = false;
                self.holding = false;
                return true;
            }
        }
        self.anim(ram);
        return false;
    }

    /// $3F3D: the row with + 1 .. + 4, then cleared (screen 0, colour purple). True when done.
    pub fn rollOut(self: *Panel, ram: *[65536]u8, col: *[1024]u8) bool {
        const o = @as(usize, self.out_row) * 40;
        rowCodes(ram, o, self.out_k);
        self.out_k += 1;
        if (self.out_k == 5) {
            @memset(ram[SCREEN + o ..][0..40], 0);
            @memset(col[o..][0..40], 4);
            self.out_k = 1;
            self.out_row += 1;
            if (self.out_row == 25) {
                self.out_row = 0;
                self.out_done = true;
            }
        }
        if (self.out_done) {
            self.out_done = false;
            return true;
        }
        self.anim(ram);
        return false;
    }

    /// $3DC1, the flash before the panel (colour RAM purple): true on its 12th frame.
    pub fn flash(self: *Panel, ram: *[65536]u8, col: *[1024]u8) bool {
        self.flash_x += 1;
        if (self.flash_x == 12) {
            self.flash_x = 0;
            return true;
        }
        @memset(col, 4);
        self.anim(ram);
        return false;
    }

    /// $4016, the flash after it: the dots' colours put back, half a screen a frame. True
    /// when the dots take over again.
    pub fn back(self: *Panel, ram: *[65536]u8, col: *[1024]u8) bool {
        self.back_x += 1;
        if (self.back_x == 0x0F) {
            self.back_state += 1;
            self.back_x = 4;
        }
        self.anim(ram);
        switch (self.back_state) {
            1 => {
                dotColours(ram, col, 0);
                self.back_state = 2;
            },
            2 => {
                dotColours(ram, col, 1);
                self.back_state = 3;
            },
            4 => {
                self.back_state = 1;
                return true;
            },
            else => {},
        }
        return false;
    }

    /// $3A05.
    pub fn anim(self: *Panel, ram: *[65536]u8) void {
        for (0..16) |x| {
            ram[0xD390 + x] = ram[0xDE00 + self.anim_off + x];
            ram[0xD3B8 + x] = ram[0xDEB0 + self.anim_off + x];
        }
        self.anim_tick -= 1;
        if (self.anim_tick != 0) return;
        self.anim_tick = 10;
        self.anim_off += 0x10;
        self.anim_left -= 1;
        if (self.anim_left != 0) return;
        self.anim_left = 11;
        self.anim_off = 0;
    }
};

/// The panel row at screen offset `o`, each non-zero code + `k`, right to left: the ADC's
/// carry runs on into the next cell (one CLC a row).
fn rowCodes(ram: *[65536]u8, o: usize, k: u8) void {
    var c: u16 = 0;
    var x: usize = 40;
    while (x > 0) {
        x -= 1;
        const code = ram[CODES + o + x];
        if (code == 0) continue;
        const s = @as(u16, code) + k + c;
        ram[SCREEN + o + x] = @truncate(s);
        c = s >> 8;
    }
}

/// Half `h` (0, 1) of the colour RAM from the dots' colours ($DA00 / $DC00, 512 each).
pub fn dotColours(ram: *const [65536]u8, col: *[1024]u8, h: usize) void {
    for (0..512) |i| col[512 * h + i] = ram[0xDA00 + 0x200 * h + i] & 15;
}
