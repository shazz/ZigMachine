// --------------------------------------------------------------------------
// Character-cell layout for GEM dialogs.
//
// Authentic GEM lays dialog objects out on an 8-pixel character grid (gl_wchar),
// not on hand-tuned pixel offsets. This module is that grid: it turns (col,row)
// cell coordinates into pixels and spreads a row of items with EVEN outer margins
// and gaps — so dialogs read as regular instead of eyeballed. Pure integer maths,
// no ZigOS/wasm imports, so the geometry is covered by native `zig test`.
// --------------------------------------------------------------------------
const std = @import("std");

pub const CELL: i16 = 8; // pixels per character cell (gl_wchar / row pitch)

// A dialog-local coordinate frame: cells measured from the dialog's top-left.
pub const Grid = struct {
    ox: i16 = 0, // dialog origin x (px, top-left of the box)
    oy: i16 = 0, // dialog origin y (px)
    cell: i16 = CELL,

    pub fn x(self: Grid, col: i16) i16 {
        return self.ox + col * self.cell;
    }
    pub fn y(self: Grid, row: i16) i16 {
        return self.oy + row * self.cell;
    }
    pub fn w(self: Grid, cols: i16) i16 {
        return cols * self.cell;
    }
    pub fn h(self: Grid, rows: i16) i16 {
        return rows * self.cell;
    }
};

// Place `count` items of width `item_w` across `width` (starting at x0) so the
// outer margins equal the inner gaps — GEM's centred button row. Returns item
// `i`'s left x. `count` must be >= 1 and the items must fit (item_w*count <= width).
pub fn hspread(x0: i16, width: i16, count: i16, item_w: i16, i: i16) i16 {
    const gap = @divTrunc(width - count * item_w, count + 1);
    return x0 + gap * (i + 1) + item_w * i;
}

// Left x that centres an `inner`-wide thing inside an `outer`-wide area at x0.
pub fn center(x0: i16, outer: i16, inner: i16) i16 {
    return x0 + @divTrunc(outer - inner, 2);
}

// --- native geometry tests (run with `zig test rom/gem/gui/grid.zig`) ---

test "hspread gives equal outer margins and inner gaps" {
    const x0: i16 = 0;
    const width: i16 = 256;
    const iw: i16 = 56;
    const a = hspread(x0, width, 2, iw, 0);
    const b = hspread(x0, width, 2, iw, 1);
    const left = a - x0;
    const gap = b - (a + iw);
    const right = (x0 + width) - (b + iw);
    try std.testing.expectEqual(left, gap);
    try std.testing.expectEqual(gap, right);
}

test "hspread single item is centred" {
    const x = hspread(0, 100, 1, 20, 0);
    try std.testing.expectEqual(@as(i16, 40), x); // (100-20)/2
}

test "grid cell maths" {
    const g = Grid{ .ox = 10, .oy = 20 };
    try std.testing.expectEqual(@as(i16, 34), g.x(3)); // 10 + 3*8
    try std.testing.expectEqual(@as(i16, 36), g.y(2)); // 20 + 2*8
    try std.testing.expectEqual(@as(i16, 32), g.w(4)); // 4*8
    try std.testing.expectEqual(@as(i16, 8), g.h(1));
}

test "center is symmetric" {
    try std.testing.expectEqual(@as(i16, 22), center(0, 100, 56)); // (100-56)/2
    try std.testing.expectEqual(@as(i16, 32), center(10, 100, 56)); // 10 + 22
}
