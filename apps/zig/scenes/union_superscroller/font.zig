// --------------------------------------------------------------------------
// TCB2 SUPERSCROLLER font: zg.spanfont's runs, on ALIGNED tables.
//
// In superscroller.bin the font's `first` and `spans` u16 tables start at odd
// offsets (the layer bytes before them are 128,321 long), so spanfont's u16
// reads land on odd addresses: on the board every one traps (~210 cycles), and
// ~1,500 of them a frame cost ~0.33 Mc. At start() they are copied once into
// u16 tables on zg.mem (1 KB), and a glyph row's runs come back as a slice.
// Same layout, same lookup as spanfont.SpanFont.runs: the same runs, in order.
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");

pub const Run = zg.spanfont.Run;

/// The font's bytes as superscroller.bin lays them out (spanfont.zig's layout).
pub const Bytes = struct {
    row_ids: []const u8,
    first: []const u8, // (rows + 1) u16
    spans: []const u8, // spans x (x0, x1) u16
};

pub fn Store(comptime rows: usize, comptime spans: usize) type {
    return struct {
        first: [rows + 1]u16,
        spans: [spans]Run,
    };
}

pub const Font = struct {
    row_ids: []const u8,
    first: []const u16,
    spans: []const Run,
    rows_per_glyph: usize,

    /// Glyph `glyph`'s row `row`: empty outside the font, as SpanFont.runs.
    pub fn runs(self: *const Font, glyph: usize, row: usize) []const Run {
        if (row >= self.rows_per_glyph) return &.{};
        const at = glyph * self.rows_per_glyph + row;
        if (at >= self.row_ids.len) return &.{};
        const id: usize = self.row_ids[at];
        return self.spans[self.first[id]..self.first[id + 1]];
    }
};

/// Copy the u16 tables out of `b` into `store` (once, at start) and view them.
pub fn build(comptime S: type, store: *S, b: Bytes, rows_per_glyph: usize) Font {
    std.debug.assert(b.first.len == 2 * store.first.len and b.spans.len == 4 * store.spans.len);
    for (&store.first, 0..) |*f, i| f.* = le16(b.first, i);
    for (&store.spans, 0..) |*s, i| s.* = .{ .x0 = le16(b.spans, 2 * i), .x1 = le16(b.spans, 2 * i + 1) };
    return .{ .row_ids = b.row_ids, .first = &store.first, .spans = &store.spans, .rows_per_glyph = rows_per_glyph };
}

/// Two byte loads: the source is not aligned.
fn le16(bytes: []const u8, i: usize) u16 {
    return @as(u16, bytes[2 * i]) | (@as(u16, bytes[2 * i + 1]) << 8);
}
