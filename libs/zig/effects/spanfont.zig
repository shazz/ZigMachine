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

    fn u16At(_: *const SpanFont, bytes: []const u8, i: usize) usize {
        return std.mem.readInt(u16, bytes[2 * i ..][0..2], .little);
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

/// The half-resolution columns [x0, x1) whose canvas column 2x falls in the run
/// [pos + a, pos + b): empty when x1 <= x0.
pub fn halfColumns(pos: i32, run: Run) [2]i32 {
    return .{ @divFloor(pos + run.x0 + 1, 2), @divFloor(pos + run.x1 + 1, 2) };
}
