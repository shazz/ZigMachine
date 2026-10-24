// --------------------------------------------------------------------------
// Span font: a big 1-bit font kept as runs of ink, sampled at half resolution.
//
// A CODEF remake's font is drawn on a canvas twice the ST's size. When it is
// NOT on a 2x grid (the Union Demo TCB2 font's 384x380 tiles are not), halving
// the tiles loses columns; keeping the canvas-unit runs does not. The ST pixel
// x shows canvas column 2x, so a run [a, b) of a letter whose left edge is at
// canvas x `pos` covers the half-resolution columns [ceil((pos+a)/2),
// ceil((pos+b)/2)): exact at either parity of pos, as the canvas scrolls by an
// odd number of pixels.
//
// Layout (little-endian): row ids, glyphs x rows_per_glyph u8 (a row id names a
// unique row); first, (unique + 1) u16, row id k's runs are first[k]..first[k+1];
// spans, u16 (x0, x1) pairs, end-exclusive.
//
// ALIGNMENT (2026-10-24). The tables are byte views of an asset, and nothing makes
// them start on an even address (superscroller.bin's sit at odd offsets). A u16
// read there is a wide load the board's `aligned` build TRAPS on (~210 cycles,
// ~1,500 a frame in the TCB2 superscroller). So SpanFont reads them a byte at a
// time (u16At: volatile, or LLVM merges the two bytes back into one load), and a
// screen that reads runs every frame copies the tables once into aligned ones:
// `aligned(Store(rows, spans), &store, font)` -> Aligned, whose runs() is a slice.
// No ZigOS import: it tests natively (spanfont_test.zig).
// --------------------------------------------------------------------------
const std = @import("std");

pub const Run = struct { x0: u16, x1: u16 };

pub const SpanFont = struct {
    row_ids: []const u8,
    first: []const u8,
    spans: []const u8,
    rows_per_glyph: usize,

    pub fn glyphs(self: *const SpanFont) usize {
        return self.row_ids.len / self.rows_per_glyph;
    }

    /// The runs of glyph `glyph`'s row `row`: an iterator over `Run`s.
    pub fn runs(self: *const SpanFont, glyph: usize, row: usize) Runs {
        if (glyph >= self.glyphs() or row >= self.rows_per_glyph) return .{ .font = self, .at = 0, .end = 0 };
        const id: usize = self.row_ids[glyph * self.rows_per_glyph + row];
        return .{ .font = self, .at = self.u16At(self.first, id), .end = self.u16At(self.first, id + 1) };
    }

    /// Two byte loads, whatever the table's alignment: volatile, so they stay two.
    fn u16At(_: *const SpanFont, bytes: []const u8, i: usize) usize {
        const p: [*]const volatile u8 = @ptrCast(bytes[2 * i ..].ptr);
        return @as(usize, p[0]) | (@as(usize, p[1]) << 8);
    }

    pub const Runs = struct {
        font: *const SpanFont,
        at: usize,
        end: usize,

        pub fn next(self: *Runs) ?Run {
            if (self.at >= self.end) return null;
            defer self.at += 1;
            return .{ .x0 = @intCast(self.font.u16At(self.font.spans, 2 * self.at)), .x1 = @intCast(self.font.u16At(self.font.spans, 2 * self.at + 1)) };
        }
    };
};

/// Aligned copies of a SpanFont's u16 tables: (rows + 1) row starts and `spans` runs.
pub fn Store(comptime rows: usize, comptime spans: usize) type {
    return struct {
        first: [rows + 1]u16,
        spans: [spans]Run,
    };
}

/// A SpanFont on aligned tables (see `aligned`): the same lookup, each row's runs a slice.
pub const Aligned = struct {
    row_ids: []const u8,
    first: []const u16,
    spans: []const Run,
    rows_per_glyph: usize,

    pub const empty: Aligned = .{ .row_ids = &.{}, .first = &.{}, .spans = &.{}, .rows_per_glyph = 1 };

    /// Glyph `glyph`'s row `row`: empty outside the font, as SpanFont.runs.
    pub fn runs(self: *const Aligned, glyph: usize, row: usize) []const Run {
        if (row >= self.rows_per_glyph) return &.{};
        const at = glyph * self.rows_per_glyph + row;
        if (at >= self.row_ids.len) return &.{};
        const id: usize = self.row_ids[at];
        return self.spans[self.first[id]..self.first[id + 1]];
    }
};

/// Copy `font`'s u16 tables into `store` (once, at start) and view them.
pub fn aligned(comptime S: type, store: *S, font: SpanFont) Aligned {
    std.debug.assert(font.first.len == 2 * store.first.len and font.spans.len == 4 * store.spans.len);
    for (&store.first, 0..) |*f, i| f.* = @intCast(font.u16At(font.first, i));
    for (&store.spans, 0..) |*s, i| s.* = .{ .x0 = @intCast(font.u16At(font.spans, 2 * i)), .x1 = @intCast(font.u16At(font.spans, 2 * i + 1)) };
    return .{ .row_ids = font.row_ids, .first = &store.first, .spans = &store.spans, .rows_per_glyph = font.rows_per_glyph };
}

/// The half-resolution columns [x0, x1) whose canvas column 2x falls in the run
/// [pos + a, pos + b): empty when x1 <= x0.
pub fn halfColumns(pos: i32, run: Run) [2]i32 {
    return .{ @divFloor(pos + run.x0 + 1, 2), @divFloor(pos + run.x1 + 1, 2) };
}
