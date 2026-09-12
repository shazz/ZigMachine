// --------------------------------------------------------------------------
// CharPanel — a grid of character cells that writes and erases itself one cell
// per frame, each glyph zooming in (or out) through a few fixed sizes.
//
// Port of the credit panel in the D-BUG "Prince of Persia" mega intro
// (Shiftcode's Codef remake, wab.com screen 556 — `screen.js: showLetters()` +
// `data.js`). The original panel is 20x12 cells of 32x28 px; a cell is revealed
// per frame in the order given by one of seven hand-authored apparition
// patterns, growing through letterSizes[0..6]; once the whole text stands, it
// holds for 100 frames, then erases itself cell by cell (same machine, run
// backwards, next pattern), and the next text takes its place.
//
// Like scrolltext2.zig this effect knows nothing about LogicalFB/ZigOS: it owns
// the animation state and draws into a caller-supplied byte buffer at an
// arbitrary `stride`, so a scene can point it at a plane or an off-screen page.
//
// The panel is INCREMENTAL: only the handful of cells that are moving are
// touched each frame, and a finished glyph simply stays in the buffer — exactly
// as the original leaves its letters on `lettersCan`. The caller must therefore
// NOT clear the destination between frames.
// --------------------------------------------------------------------------
const std = @import("std");

/// One frame of a cell's zoom. `size` is the glyph's edge in destination
/// pixels (0 == invisible) and `off` its top-left inset inside the cell — the
/// original centres a 32-wide glyph, so off == (32 - size) / 2, and applies
/// that same inset vertically even though its cells are 28 tall (which is why
/// a settled letter sits slightly low; the artefact is part of the look).
pub const Step = struct { size: u8, off: u8 };

pub const Config = struct {
    cols: u16 = 20,
    rows: u16 = 12,
    cell_w: u16,
    cell_h: u16,
    ascii_base: u8 = 32,
    /// Indexed glyph sheet, glyph-major: glyph i starts at i * cell_w * cell_h.
    font: []const u8,
    /// Source index treated as see-through, and the value a cleared cell gets.
    transparent: u8 = 0,
    /// Zoom stages, smallest first. steps[0] must be the invisible one.
    steps: []const Step,
    /// Panel texts, each exactly cols*rows characters.
    texts: []const []const u8,
    /// Apparition orders, concatenated: cols*rows cell indices per pattern.
    /// Indices are u8, so a panel may not exceed 256 cells.
    patterns: []const u8,
    /// Frames the finished panel is held before it starts erasing itself.
    wait_frames: u16 = 100,
};

/// `MAX_LIVE` must be at least `steps.len`: one cell starts per frame and a
/// cell lives for one frame per step, so that many are ever in flight.
pub fn Panel(comptime MAX_LIVE: usize) type {
    return struct {
        const Self = @This();
        const Cell = struct { ch: u8, cell: u16, t: i16 };

        cfg: Config = undefined,
        live: [MAX_LIVE]Cell = undefined,
        live_n: usize = 0,
        /// Cells to paint this frame, snapshotted by update() at the size they
        /// are to be drawn AT — the original draws, then advances.
        draw: [MAX_LIVE]Cell = undefined,
        draw_n: usize = 0,
        order: i32 = 0, // how far into the current apparition pattern we are
        wait: u16 = 0,
        dir: i16 = 1, // +1 writing the panel, -1 erasing it
        text: usize = 0,
        pattern: usize = 0,

        pub fn init(self: *Self, cfg: Config) void {
            std.debug.assert(cfg.steps.len >= 2 and cfg.steps.len <= MAX_LIVE);
            std.debug.assert(cfg.cols * cfg.rows <= 256); // patterns hold u8 indices
            std.debug.assert(cfg.patterns.len % (cfg.cols * cfg.rows) == 0);
            self.* = .{ .cfg = cfg };
        }

        fn cells(self: *const Self) u16 {
            return self.cfg.cols * self.cfg.rows;
        }

        /// Advance one frame. Paints nothing — render() does that.
        pub fn update(self: *Self) void {
            self.draw_n = 0;
            if (self.wait > 0) {
                self.wait -= 1;
                return;
            }
            self.spawn();
            self.age();
        }

        // Start the next cell of the pattern, or — once the last one has
        // finished moving — turn the panel around.
        fn spawn(self: *Self) void {
            if (self.order >= 0 and self.order < self.cells()) {
                self.push(@intCast(self.order));
            } else if (self.live_n == 0) {
                self.turn();
            }
            self.order += 1;
        }

        fn push(self: *Self, order_idx: u16) void {
            if (self.live_n == MAX_LIVE) return; // unreachable while MAX_LIVE >= steps.len
            const n = self.cells();
            const cell = self.cfg.patterns[self.pattern * n + order_idx];
            const last: i16 = @intCast(self.cfg.steps.len - 1);
            self.live[self.live_n] = .{
                .ch = self.cfg.texts[self.text][cell],
                .cell = cell,
                .t = if (self.dir == 1) 0 else last - 1,
            };
            self.live_n += 1;
        }

        // Snapshot every live cell at its current size, then move it one step
        // along; a cell that steps off either end of the zoom is done.
        fn age(self: *Self) void {
            const last: i16 = @intCast(self.cfg.steps.len - 1);
            var kept: usize = 0;
            for (self.live[0..self.live_n]) |cell| {
                self.draw[self.draw_n] = cell;
                self.draw_n += 1;
                var moved = cell;
                moved.t += self.dir;
                if (moved.t >= 0 and moved.t <= last) {
                    self.live[kept] = moved;
                    kept += 1;
                }
            }
            self.live_n = kept;
        }

        // The panel is written; hold it, then erase it. Once erased, the next
        // text takes over. Either way the next pattern is selected, so a text
        // never arrives and leaves the same way.
        fn turn(self: *Self) void {
            if (self.dir == 1) {
                self.wait = self.cfg.wait_frames;
            } else {
                self.text = (self.text + 1) % self.cfg.texts.len;
            }
            self.pattern = (self.pattern + 1) % (self.cfg.patterns.len / self.cells());
            self.order = -1; // spawn() bumps it to 0 on the way out
            self.dir = -self.dir;
        }

        /// Paint this frame's moving cells into `dst` with the panel's top-left
        /// at (x, y). Cells that are not moving are left as they were drawn.
        pub fn render(self: *Self, dst: []u8, stride: u16, x: u16, y: u16) void {
            for (self.draw[0..self.draw_n]) |cell| {
                const cx = x + (cell.cell % self.cfg.cols) * self.cfg.cell_w;
                const cy = y + (cell.cell / self.cfg.cols) * self.cfg.cell_h;
                self.wipe(dst, stride, cx, cy);
                const step = self.cfg.steps[@intCast(cell.t)];
                if (step.size == 0) continue;
                self.blit(dst, stride, cx + step.off, cy + step.off, cell.ch, step.size);
            }
        }

        fn wipe(self: *const Self, dst: []u8, stride: u16, x: u16, y: u16) void {
            var row: u16 = 0;
            while (row < self.cfg.cell_h) : (row += 1) {
                const start = (@as(usize, y + row) * stride) + x;
                const end = start + self.cfg.cell_w;
                if (end > dst.len) return;
                @memset(dst[start..end], self.cfg.transparent);
            }
        }

        // Nearest-neighbour zoom of one glyph into a size x size box. The cell
        // need not be square: the source is sampled over the full cell, so a
        // 16x14 cell at size 14 is squeezed horizontally and 1:1 vertically —
        // which is what the original's 32x28 cell at size 28 does.
        fn blit(self: *const Self, dst: []u8, stride: u16, x: u16, y: u16, ch: u8, size: u8) void {
            const cw = self.cfg.cell_w;
            const chh = self.cfg.cell_h;
            if (ch < self.cfg.ascii_base) return;
            const glyph = @as(usize, ch - self.cfg.ascii_base) * cw * chh;
            if (glyph + @as(usize, cw) * chh > self.cfg.font.len) return;

            var dy: u16 = 0;
            while (dy < size) : (dy += 1) {
                const sy = (@as(u32, dy) * chh) / size;
                const src = glyph + sy * cw;
                const row = @as(usize, y + dy) * stride + x;
                var dx: u16 = 0;
                while (dx < size) : (dx += 1) {
                    const pixel = self.cfg.font[src + (@as(u32, dx) * cw) / size];
                    if (pixel == self.cfg.transparent) continue;
                    if (row + dx < dst.len) dst[row + dx] = pixel;
                }
            }
        }
    };
}
