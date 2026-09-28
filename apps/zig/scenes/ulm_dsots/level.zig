// --------------------------------------------------------------------------
// The map's collision layer as TiledLayer.getTile reads it: a pixel is
// truncated (~~) and looked up in per-pixel column/row tables that only exist
// inside the map, so anything outside (above, below, or in the empty rows the
// data file leaves out) is no tile at all.
//
// No ZigOS import: tests natively.
// --------------------------------------------------------------------------
const map = @import("../../assets/screens/ulm_dsots/map.zig");

pub const TILE: f64 = map.TILE;
pub const WIDTH: f64 = @as(f64, map.COLS) * TILE; // realwidth, 22400
pub const HEIGHT: f64 = @as(f64, map.ROWS) * TILE; // realheight, 1280

pub const Level = struct {
    cells: []const u8, // map.COLS x map.DATA_ROWS kinds (griffin.SOLID / PLATFORM)

    pub fn cellAt(self: *const Level, px: f64, py: f64) u8 {
        const x = @trunc(px);
        const y = @trunc(py);
        if (!(x >= 0 and x < WIDTH and y >= 0 and y < HEIGHT)) return 0;
        const col: usize = @intFromFloat(x / TILE);
        const row: usize = @intFromFloat(y / TILE);
        if (row >= map.DATA_ROWS) return 0;
        return self.cells[row * map.COLS + col];
    }

    pub fn width(_: *const Level) f64 {
        return WIDTH;
    }

    pub fn tile(_: *const Level) f64 {
        return TILE;
    }
};

test "cellAt truncates like ~~ and knows nothing outside the map" {
    const std = @import("std");
    var cells = [_]u8{0} ** (map.COLS * map.DATA_ROWS);
    cells[0] = 1;
    cells[map.COLS + 1] = 2;
    const l = Level{ .cells = &cells };
    try std.testing.expectEqual(@as(u8, 1), l.cellAt(0.5, 31.9));
    try std.testing.expectEqual(@as(u8, 1), l.cellAt(-0.5, 0)); // ~~-0.5 is 0
    try std.testing.expectEqual(@as(u8, 0), l.cellAt(0, -1)); // ~~-1 has no row
    try std.testing.expectEqual(@as(u8, 2), l.cellAt(32, 32));
    try std.testing.expectEqual(@as(u8, 0), l.cellAt(0, HEIGHT - 1));
    try std.testing.expectEqual(@as(u8, 0), l.cellAt(WIDTH, 0));
}
