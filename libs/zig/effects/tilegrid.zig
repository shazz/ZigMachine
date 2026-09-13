// --------------------------------------------------------------------------
// Tile grid — the pure half of the 2D tile map (zigos library, via tilemap.zig).
//
// tilemap.Layer draws a pre-wrapped horizontal BAND addressed in tiles. A
// platform/street screen needs a real 2D map addressed in PIXELS instead: a
// camera scrolls over it and an entity asks "which tile is at this corner?".
// Those questions live here, with no ZigOS import, so they test natively
// (tilegrid_test.zig); drawing a Grid is tilemap.drawGrid.
//
// Semantics follow melonJS 0.9.8, which the Union Demo menu remake runs on:
// cell lookup truncates like JS `~~(x / tw)`, the camera follow is
// me.Viewport._followH/_followV, and the ratio scroll is me.ImageLayer.update.
// --------------------------------------------------------------------------

/// A Tiled orthogonal layer: `cols` x `rows` cells of one byte each, row-major.
/// `tw`/`th` are the cell size in whatever pixel units the caller works in.
pub const Grid = struct {
    cells: []const u8,
    cols: usize,
    rows: usize,
    tw: u16,
    th: u16,

    /// The cell holding pixel (px, py), or null outside the map. Truncates
    /// toward zero like melonJS's TMXLayer.getTile, so -0.5 is still column 0.
    pub fn cellAt(self: *const Grid, px: f32, py: f32) ?u8 {
        const c = @trunc(px / @as(f32, @floatFromInt(self.tw)));
        const r = @trunc(py / @as(f32, @floatFromInt(self.th)));
        if (c < 0 or r < 0) return null;
        if (c >= @as(f32, @floatFromInt(self.cols)) or r >= @as(f32, @floatFromInt(self.rows))) return null;
        const ci: usize = @intFromFloat(c);
        const ri: usize = @intFromFloat(r);
        return self.cells[ri * self.cols + ci];
    }

    pub fn widthPx(self: *const Grid) usize {
        return self.cols * self.tw;
    }
};

/// One axis of melonJS's viewport follow. The view moves only when `target`
/// leaves the dead zone [lo, hi] measured from the view's leading edge, is kept
/// within [0, limit], and lands on a truncated integer (`~~` in the original).
pub fn followAxis(view: i32, target: f32, lo: i32, hi: i32, limit: i32) i32 {
    const rel = target - @as(f32, @floatFromInt(view));
    if (rel > @as(f32, @floatFromInt(hi))) {
        return @intFromFloat(@trunc(@min(target - @as(f32, @floatFromInt(hi)), @as(f32, @floatFromInt(limit)))));
    }
    if (rel < @as(f32, @floatFromInt(lo))) {
        return @intFromFloat(@trunc(@max(target - @as(f32, @floatFromInt(lo)), 0)));
    }
    return view;
}

/// The dead zone melonJS's setDeadzone(w, h) builds for a view `size` pixels
/// long on one axis: lo = ~~((size - w) / 2), hi = size - lo.
pub fn deadzone(size: i32, w: i32) struct { lo: i32, hi: i32 } {
    const lo = @divTrunc(size - w, 2);
    return .{ .lo = lo, .hi = size - lo };
}

/// A repeating image that scrolls with the camera at `ratio` (me.ImageLayer's
/// parallax). `pos` is the image column at the view's left edge, 0 <= pos < w.
/// JS `%` keeps the dividend's sign, hence @rem.
pub const RatioScroll = struct {
    pos: f32,
    last: f32,
    ratio: f32,
    w: f32,

    pub fn update(self: *RatioScroll, view: f32) void {
        if (view == self.last) return;
        self.pos += @rem((view - self.last) * self.ratio, self.w);
        self.pos = @rem(self.w + self.pos, self.w);
        self.last = view;
    }
};
