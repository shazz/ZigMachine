// --------------------------------------------------------------------------
// The sprite unit's output: one sprite row per line, into a 400x280 overscan plane.
//
// Geometry (measured on VICE captures, prototypes/1988_re/ANALYSIS.md): ZigMachine's
// physical row r is raster line r + 11 and column c is sprite X c - 16 (PAL wraps X at
// $1F8), so the C64's 320x200 window (lines 51..250, X 24..343) IS the machine's visible
// 320x200 window and the C64 borders are the machine's borders. A pixel the C64's border
// covers is not drawn, so the plane holds exactly what the C64 shows; the machine's own
// borders are opened (flicker rows) only where the C64 opened its own.
//
// Pixels are palette indices 1 + C64 colour; 0 is no sprite, where the cart's per-line
// colour 0 (the border colour, a real raster: c64_1988.zig) shows. Each sprite row is
// a keyed CPU blit of 24 (48 X-expanded) pixels (vic_pixels.zig): at ~800 cycles fixed
// cost a CHISEL blit per row would cost more than the row itself. Only what moved is
// touched: each row remembers the columns it drew, and the next frame erases those alone.
// --------------------------------------------------------------------------
const px = @import("vic_pixels.zig");
pub const COLS = px.COLS;
pub const ROWS = 280;
pub const FIRST_LINE = 11; // raster line of physical row 0
const NREG = 0x2F;
const PAL_X = 504; // PAL: X runs 0..$1F7, then wraps

/// What the VIC sees as sprite memory: VIC bank 3 ($C000-$FFFF) in part 1, bank 0 in part 3,
/// where only $2000-$27FF (blocks $80-$9F) holds sprites. The rest of bank 0 (zero page, the
/// char ROM at $1000...) is only fetched under a closed border in this intro, so it reads as
/// 0 here; a fetch of it with the border open is counted in `foreign` (a test pins it at 0).
pub const Mem = struct {
    bank3: *const [16384]u8,
    bank0_2000: *const [2048]u8,
    foreign: *u32,

    pub fn byte(self: Mem, bank3: bool, addr: u16, border_open: bool) u8 {
        if (bank3) return self.bank3[addr & 0x3FFF];
        if (addr >= 0x2000 and addr < 0x2800) return self.bank0_2000[addr - 0x2000];
        if (border_open) self.foreign.* += 1;
        return 0;
    }
};

pub const LineInfo = struct {
    reg: *const [NREG]u8, // registers as they were when the row was fetched (c58)
    shown: u8,
    data: *const [8][3]u8,
    vb: bool,
    left_open: bool,
    right_open: bool,
    border: u8, // colour at the line's start
    border_end: u8,
    split_cyc: u8, // cycle of the change, 0 = none
};

/// Where a border colour written at `cyc` first shows: the beam is 8 pixels a cycle and the
/// first new pixel is VICE column 8 * cyc - 103 (measured on the wipe's top lines), so
/// physical column 8 * cyc - 95. VICE's 8565 also paints the pixel before it light grey (the
/// "grey dot"); that pixel shows the new colour here.
pub fn splitColumn(cyc: u8) i32 {
    return 8 * @as(i32, cyc) - 95;
}

pub const Out = struct {
    pub const ROWS_COLS = ROWS * COLS;
    pix: *[ROWS * COLS]u8,
    border: [ROWS]u8 = .{0} ** ROWS, // C64 border colour at the start of each row
    split_x: [ROWS]u16 = .{0} ** ROWS, // a mid-row change to split_c from this column (0 = none)
    split_c: [ROWS]u8 = .{0} ** ROWS,
    sides: [ROWS]bool = .{false} ** ROWS, // a side border open on the row (the machine must flicker)
    vopen: [ROWS]bool = .{false} ** ROWS, // the vertical border open on the row
    // Columns [lo, hi) of each row hold sprite pixels (to erase next frame); lo >= hi: none.
    lo: [ROWS]u16 = .{COLS} ** ROWS,
    hi: [ROWS]u16 = .{0} ** ROWS,

    /// Erase what the last frame drew: only the columns that hold pixels are touched.
    pub fn begin(self: *Out) void {
        for (0..ROWS) |r| {
            if (self.lo[r] >= self.hi[r]) continue;
            @memset(self.pix[r * COLS ..][self.lo[r]..self.hi[r]], 0);
            self.lo[r] = COLS;
            self.hi[r] = 0;
        }
    }

    /// The line's border colour (and its mid-line split) and border state, at its end.
    pub fn edges(self: *Out, raster: u16, li: *const LineInfo) void {
        if (raster < FIRST_LINE or raster >= FIRST_LINE + ROWS) return;
        const r = raster - FIRST_LINE;
        self.borderRow(r, li);
        self.vopen[r] = !li.vb;
        self.sides[r] = li.left_open or li.right_open;
    }

    /// The line's sprite rows, drawn at c58 (registers and border state as they are then).
    pub fn sprites(self: *Out, raster: u16, li: *const LineInfo) void {
        if (raster < FIRST_LINE or raster >= FIRST_LINE + ROWS) return;
        const r = raster - FIRST_LINE;
        if (li.vb) return;
        var m = li.shown;
        while (m != 0) { // highest number first: sprite 0 is drawn last, in front
            const s: usize = 7 - @clz(m);
            m &= ~(@as(u8, 1) << @intCast(s));
            self.sprite(r, s, li);
        }
    }

    fn borderRow(self: *Out, r: usize, li: *const LineInfo) void {
        self.border[r] = li.border & 15;
        self.split_x[r] = 0;
        if (li.split_cyc == 0) return;
        const x = splitColumn(li.split_cyc);
        if (x <= 0) {
            self.border[r] = li.border_end & 15; // before the line's first pixel
        } else if (x < COLS) {
            self.split_x[r] = @intCast(x);
            self.split_c[r] = li.border_end & 15;
        }
    }

    fn sprite(self: *Out, r: usize, s: usize, li: *const LineInfo) void {
        const data = &li.data[s];
        if (data[0] | data[1] | data[2] == 0) return;
        const reg = li.reg;
        const b = @as(u8, 1) << @intCast(s);
        const x0: u32 = reg[2 * s] | (@as(u32, (reg[0x10] >> @intCast(s)) & 1) << 8);
        const xe2 = reg[0x1D] & b != 0;
        const xe: u32 = if (xe2) 2 else 1;
        const colours = [4]u8{ 0, (reg[0x25] & 15) + 1, (reg[0x27 + s] & 15) + 1, (reg[0x26] & 15) + 1 };
        const mcol = reg[0x1C] & b != 0;
        const row = self.pix[r * COLS ..][0..COLS];
        var c: u32 = (x0 + 16) % PAL_X; // one division a row; then the beam steps and wraps
        const w = 8 * xe; // columns a data byte covers
        var lo: u32 = self.lo[r];
        var hi: u32 = self.hi[r];
        for (data) |byte| {
            if (byte != 0) {
                if (c >= 40 and c + w <= 360) { // wholly inside the window: no clipping
                    px.inner(row[c..].ptr, byte, xe2, mcol, &colours);
                    lo = @min(lo, c);
                    hi = @max(hi, c + w);
                } else { // crosses a border or the PAL wrap: the whole row, to be safe
                    px.edge(row, c, byte, xe, mcol, &colours, li.left_open, li.right_open);
                    lo = 0;
                    hi = COLS;
                }
            }
            c += w;
            if (c >= PAL_X) c -= PAL_X;
        }
        self.lo[r] = @intCast(lo);
        self.hi[r] = @intCast(hi);
    }
};
