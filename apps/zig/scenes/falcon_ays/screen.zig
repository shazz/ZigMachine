// --------------------------------------------------------------------------
// The Falcon's screen on KESTREL: one RGB565 true-colour plane (HW 1.15.0, 320x200 window),
// double-buffered (the Falcon rotated three), and the original's two screen modes:
//
//   804  320x200 true colour: the plane shows the buffer straight;
//   805  the same 320x200 with every line shown twice (Videl VCO bit 0): the effects draw
//        160x100, each pixel stored twice. Here they draw 160 pixel PAIRS into rows 0..99 and
//        the copper line list points raster line y at row y/2: line doubling costs no store.
//
// The shakes: the Falcon's VBL added a table entry a frame to the Videl's display window
// (HDB/HDE: sideways, VDB/VDE: up and down, in half-lines). Here the same entries move every
// line's LBASE: a shake costs no pixel. A frame: draw into back(), flip(); a frame that draws
// nothing calls commit() so a running shake still moves.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const tc = zg.tc;

pub const W = 320;
pub const H = 200;

pub const Mode = enum { full, doubled };

/// The shake tables (DATA $1D3CD0, $1D3F7E, $1D3FBC; ANALYSIS.md): one entry a 50 Hz VBL, to 0.
pub const BOUNCE = [_]i8{ -16, 16, -16, 16, -15, 15, -15, 15, -14, 14, -14, 14, -13, 13, -13, 13, -12, 12, -12, 12, -11, 11, -11, 11, -10, 10, -10, 10, -9, 9, -9, 9, -8, 8, -8, 8, -7, 7, -7, 7, -6, 6, -5, 5, -5, 5, -4, 4, -4, 4, -3, 3, -3, 3, -2, 2, -2, 2, -1, 1, -1, 1, 0 };
pub const JOLT = [_]i8{ -1, 1, -2, 2, -3, 3, -3, 4, -3, 5, -3, 6, -3, 7, -3, 8, -3, 7, -3, 6, -3, 5, -3, 4, -3, 3, -2, 2, -1, 1, 0 };
pub const QUAKE = [_]i8{ -1, -1, 1, 1, -2, -2, 2, 2, -3, -3, 3, 3, -4, -4, 4, 4, -5, -5, 5, 5, -6, -6, 6, 6, -7, -7, 7, 7, -8, -8, 8, 8, -7, -7, 7, 7, -6, -6, 6, 6, -5, -5, 5, 5, -4, -4, 4, 4, -3, -3, 3, 3, -2, -2, 2, 2, -1, -1, 1, 1, 0 };

pub const Axis = enum { x, y };

pub const Shake = struct {
    table: []const i8 = &.{},
    axis: Axis = .y,
    i: usize = 0,
    looping: bool = false, // 83B's quake runs until 83C stops it

    pub fn tick(self: *Shake) void {
        if (self.i + 1 < self.table.len) self.i += 1 else if (self.looping) self.i = 0;
    }
    pub fn value(self: *const Shake) i32 {
        return if (self.table.len == 0) 0 else self.table[self.i];
    }
    pub fn running(self: *const Shake) bool {
        return self.table.len != 0 and (self.looping or self.i + 1 < self.table.len);
    }
};

var lines: [H]zg.linelist.Line = undefined;

pub const Screen = struct {
    plane: *zg.LogicalFB,
    back_fb: tc.Fb,
    list: ?[]u32 = null,
    mode: Mode = .full,
    shake: Shake = .{},

    /// Plane 0 alone, true colour; with no second buffer it draws in place.
    pub fn init(os: *zg.ZigOS) Screen {
        for (&os.lfbs) |*p| p.is_enabled = false;
        const plane = &os.lfbs[0];
        const front_fb = plane.setTruecolorPlane(.window);
        plane.is_enabled = true;
        const second = zg.truecolorBuffer(.window) orelse front_fb;
        second.fill(0);
        var s = Screen{ .plane = plane, .back_fb = second };
        s.list = zg.linelist.install(plane, H, false);
        s.commit();
        return s;
    }

    /// The buffer to draw the next frame in.
    pub fn back(self: *const Screen) tc.Fb {
        return self.back_fb;
    }

    /// The frame on screen (what the feedback effects read).
    pub fn front(self: *const Screen) tc.Fb {
        return tc.view(self.plane.fb, .window);
    }

    /// Show the drawn frame from the next one; the old front becomes the back.
    pub fn flip(self: *Screen) void {
        if (self.back_fb.pixels != self.front().pixels) self.back_fb = self.plane.showTruecolor(self.back_fb);
        self.commit();
    }

    /// The flames draw through CHISEL, which writes 8-bit pixels: they get plane 1, a plain
    /// 320x200 palette plane, shown INSTEAD of the true-colour plane (one plane enabled at a
    /// time: each enabled plane costs the board ~0.6 Mc).
    pub fn eightBit(self: *Screen, os_planes: []zg.LogicalFB, on: bool) *zg.LogicalFB {
        os_planes[1].is_enabled = on;
        self.plane.is_enabled = !on;
        return &os_planes[1];
    }

    pub fn setMode(self: *Screen, m: Mode) void {
        self.mode = m;
    }

    /// Rebuild the line list: mode, then the shake (only the words that changed are stored).
    pub fn commit(self: *Screen) void {
        const l = self.list orelse return;
        const half: u5 = if (self.mode == .doubled) 1 else 0;
        const v = self.shake.value();
        const dy: i32 = if (self.shake.axis == .y) @divTrunc(v, 2) else 0; // VDB is in half-lines
        const dx: i32 = if (self.shake.axis == .x) v else 0;
        for (&lines, 0..) |*ln, y| {
            const src: i32 = @intCast(y);
            const row: u32 = @intCast(@max(0, @min(H - 1, src - dy)));
            const base: i64 = @as(i64, self.plane.lineAddr(0, row >> half)) - 2 * dx;
            ln.* = .{ .base = @intCast(base) };
        }
        _ = zg.linelist.build(l, &lines, .{ .plane = 0, .stride = 2 * W, .first_row = zg.VERTICAL_BORDERS_HEIGHT, .colour_entry = null }) catch {};
    }
};
