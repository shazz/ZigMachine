// --------------------------------------------------------------------------
// Line palette: up to `n` palette entries PER SCANLINE, handed out while a row
// is drawn and replayed by the plane's HBL before that line is composited.
//
// For a screen whose colours are exact per line but far more than 255 per
// frame: canvas-blended layers (chrome_draw.zig) over rasters. Where `copper`
// drives up to 4 fixed entries from tables, this ALLOCATES: the scene asks
// entry(rgba) for each pixel of the row it is drawing and writes the index it
// gets; the same colour on the same line gets the same entry.
//
// The table lives in the scene (module scope): it is rows x n colours. HBL
// handlers take no user pointer, so install() keeps a pointer to it.
// Generic over the plane type, no ZigOS import: it tests natively
// (linepal_test.zig). Entry 0 is never handed out (it stays transparent).
// --------------------------------------------------------------------------
const std = @import("std");

pub const Geometry = struct { rows: usize, visible_top: usize };

/// A palette colour as the plane stores it (zg.Color.toRGBA), opaque.
pub fn rgb(r: u8, g: u8, b: u8) u32 {
    return 0xFF00_0000 | (@as(u32, b) << 16) | (@as(u32, g) << 8) | r;
}

pub fn LinePalette(comptime FB: type, comptime OS: type, comptime g: Geometry, comptime n: usize) type {
    if (n == 0 or n > 255) @compileError("linepal: 1 to 255 entries a line");
    const HASH_BITS = 10;
    const HASH = 1 << HASH_BITS;
    return struct {
        const Self = @This();
        pub const FIRST: u8 = 1;
        pub const ENTRIES = n;

        colours: [g.rows][n]u32,
        used: [g.rows]u8,
        /// The row being drawn: colour -> entry, valid where stamp == gen.
        keys: [HASH]u32,
        slots: [HASH]u8,
        stamp: [HASH]u16,
        gen: u16,
        line: usize,
        /// Most entries any row has needed since init, and pixels that found none.
        peak: u8,
        overflow: u32,

        var active: ?*const Self = null;

        pub fn init(self: *Self) void {
            @memset(&self.used, 0);
            @memset(&self.stamp, 0);
            self.gen = 0;
            self.line = 0;
            self.peak = 0;
            self.overflow = 0;
        }

        /// Replay this table on `fb` from now on.
        pub fn install(self: *const Self, fb: *FB) void {
            active = self;
            fb.setFrameBufferHBLHandler(0, hbl);
        }

        /// Start handing out entries for visible line `line`.
        pub fn beginRow(self: *Self, line: usize) void {
            self.line = @min(line, g.rows - 1);
            self.used[self.line] = 0;
            self.gen +%= 1;
            if (self.gen == 0) {
                @memset(&self.stamp, 0);
                self.gen = 1;
            }
        }

        /// The entry showing `rgba` on the current row. When the row is full
        /// the colour gets the last entry and `overflow` counts it.
        pub fn entry(self: *Self, rgba: u32) u8 {
            var h: usize = @intCast((rgba *% 0x9E37_79B1) >> (32 - HASH_BITS));
            while (self.stamp[h] == self.gen) : (h = (h + 1) & (HASH - 1)) {
                if (self.keys[h] == rgba) return self.slots[h];
            }
            const u = self.used[self.line];
            if (u == n) {
                self.overflow += 1;
                return FIRST + u - 1;
            }
            self.colours[self.line][u] = rgba;
            self.used[self.line] = u + 1;
            self.peak = @max(self.peak, u + 1);
            self.stamp[h] = self.gen;
            self.keys[h] = rgba;
            self.slots[h] = FIRST + u;
            return FIRST + u;
        }

        pub fn hbl(fb: *FB, _: *OS, line: u16, _: u16) void {
            const self = active orelse return;
            const row: usize = if (fb.hblLinesArePhysical()) @as(usize, line) -% g.visible_top else line;
            if (row >= g.rows) return;
            for (self.colours[row][0..self.used[row]], 0..) |c, i| fb.palette[FIRST + i] = c;
        }
    };
}
