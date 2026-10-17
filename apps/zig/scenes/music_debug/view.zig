// --------------------------------------------------------------------------
// The 320x200 screen inside the one 400x280 overscan plane the music screen
// draws on. The starfield, the scope and the logo were planes of their own,
// clipped to that window; drawn through a View they clip exactly as before.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const LogicalFB = zg.LogicalFB;

pub const W: i32 = zg.WIDTH;
pub const H: i32 = zg.HEIGHT;
pub const X0: u16 = zg.HORIZONTAL_BORDERS_WIDTH; // 40
pub const Y0: u16 = zg.VERTICAL_BORDERS_HEIGHT; // 40

pub const View = struct {
    px: [*]u8, // the window's (0, 0)
    stride: i32,

    pub fn of(fb: *LogicalFB) View {
        return .{ .px = fb.fb + @as(usize, Y0) * fb.stride + X0, .stride = fb.stride };
    }

    pub fn put(self: View, x: i32, y: i32, c: u8) void {
        if (x < 0 or x >= W or y < 0 or y >= H) return;
        self.px[@intCast(y * self.stride + x)] = c;
    }
};

// Starfield3D.render() (not line mode), drawn into the window: a star whose previous
// projection was on screen is plotted at its current one, in its depth's grey.
pub fn drawStars(v: View, sf: anytype) void {
    const steps: f32 = 29; // the library's GRADIENT_STEPS - 1
    for (&sf.starfield_table) |*s| {
        if (!(s.prev_proj_x > 0 and s.prev_proj_x < sf.width and s.prev_proj_y > 0 and s.prev_proj_y < sf.height)) continue;
        const pal_index = 1 + sf.color_ratio * s.z * 1.2 * steps;
        const x: u16 = @intFromFloat(s.proj_x);
        const y: u16 = @intFromFloat(s.proj_y);
        v.put(x, y, @intFromFloat(pal_index));
    }
}
