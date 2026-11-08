// TRI TEST's triangles: a hand list of the edge cases CHISEL's TRIANGLE must get bit-exact
// (machine/blitter_ops.zig crossSpan: x = ax + floor(dx * (y - ay) / dy), half-open rows), and a
// seeded generator for the stress mode. Every triangle stays inside the model's i32 product
// (|dx| * (y - ay) < 2^31): coordinates within +-16000.
pub const Tri = struct {
    v: [6]i16, // x0 y0 x1 y1 x2 y2
    color: u8,
    clip: [4]i16 = DRAW_AREA, // x, y, w, h: never above the label rows
};

pub const LABEL_ROWS = 16;
pub const DRAW_AREA = [4]i16{ 0, LABEL_ROWS, 320, 200 - LABEL_ROWS };

fn t(v: [6]i16, color: u8) Tri {
    return .{ .v = v, .color = color };
}

/// Set A: the shapes the walk could get wrong, each named.
pub const EDGES = [_]Tri{
    t(.{ 10, 20, 60, 30, 30, 80 }, 1), // plain, every slope sign below
    t(.{ 70, 20, 120, 20, 95, 70 }, 2), // flat top
    t(.{ 130, 70, 180, 70, 155, 20 }, 3), // flat bottom
    t(.{ 190, 20, 240, 45, 190, 70 }, 4), // vertical left edge
    t(.{ 300, 20, 250, 45, 300, 70 }, 5), // vertical right edge
    t(.{ 10, 90, 11, 160, 12, 120 }, 6), // sliver: two pixels wide, 70 rows
    t(.{ 20, 90, 300, 91, 160, 92 }, 7), // sliver: three rows, 280 wide (|dx| >> dy)
    t(.{ 20, 100, 20, 100, 20, 100 }, 8), // a point: draws nothing
    t(.{ 30, 100, 60, 130, 90, 160 }, 9), // collinear: draws nothing
    t(.{ 40, 110, 140, 110, 240, 110 }, 10), // zero height: draws nothing
    t(.{ 100, 120, 60, 124, 140, 160 }, 11), // dy = 4, exact quotients
    t(.{ 150, 120, 110, 140, 190, 140 }, 12), // -2 and +2 a row exactly (exact negative division)
    t(.{ 200, 100, 197, 103, 230, 180 }, 13), // -1 a row, exact
    t(.{ 260, 100, 259, 107, 300, 107 }, 14), // -1/7 a row: the floor, not the truncation
    t(.{ 60, -40, 20, 40, 100, 60 }, 15), // top above the clip, exact -1/2 edge: the start divide
    t(.{ 160, -3001, 120, 60, 200, 90 }, 1), // top 3000 rows above: a large start offset
    t(.{ 240, 16, 220, 60, 280, 100 }, 2), // top vertex on the clip's top row
    t(.{ 250, -20, 230, 16, 300, 60 }, 3), // middle vertex on the clip's top row: the switch at the first row
    t(.{ -16000, 170, 16000, 180, 0, 199 }, 4), // huge, x far off both sides
    t(.{ 160, 192, -16000, 15000, 16000, 15000 }, 5), // huge, bottom far below the plane
    t(.{ -50, 185, -10, 199, -30, 210 }, 6), // entirely left of the plane
    t(.{ 330, 185, 400, 190, 350, 199 }, 7), // entirely right of it
    t(.{ 300, 150, 340, 170, 290, 199 }, 8), // cut by the right edge
    t(.{ 5, 170, -20, 180, 25, 199 }, 9), // cut by the left edge
    t(.{ 100, 150, 140, 210, 180, 160 }, 10), // cut by the bottom
    t(.{ 31, 166, 77, 167, 54, 196 }, 11), // dy = 1 top edge
    .{ .v = .{ 90, 30, 200, 60, 120, 120 }, .color = 12, .clip = .{ 110, 40, 50, 40 } }, // a clip rect inside
    .{ .v = .{ 210, 140, 280, 150, 230, 199 }, .color = 13, .clip = .{ 230, 150, 1, 1 } }, // a 1x1 clip
};

pub const SEED_A: u32 = 0x7A1E57;
pub const RANDOM_A = 160; // set A's seeded triangles, after EDGES
pub const STRESS_PER_FRAME = 48;
pub const STRESS_FRAMES = 300;

pub const Rng = struct {
    s: u32,
    pub fn next(self: *Rng) u32 {
        self.s = self.s *% 1664525 +% 1013904223;
        return self.s >> 8;
    }
    fn in(self: *Rng, lo: i32, hi: i32) i16 {
        return @intCast(lo + @as(i32, @intCast(self.next() % @as(u32, @intCast(hi - lo + 1)))));
    }
};

/// One seeded triangle: small, big, sliver, flat, |dx| >> dy, huge, or off the plane.
pub fn random(r: *Rng) Tri {
    const cx = r.in(-20, 340);
    const cy = r.in(0, 220);
    var v: [6]i16 = undefined;
    switch (r.next() % 8) {
        0, 1, 2 => for (0..3) |k| {
            v[2 * k] = cx + r.in(-16, 16);
            v[2 * k + 1] = cy + r.in(-16, 16);
        },
        3 => for (0..3) |k| {
            v[2 * k] = r.in(-100, 420);
            v[2 * k + 1] = r.in(-100, 300);
        },
        4 => v = .{ cx, cy, cx + r.in(-2, 2), cy + r.in(-120, 120), cx + r.in(-30, 30), cy + r.in(-60, 60) },
        5 => v = .{ cx - r.in(0, 90), cy, cx + r.in(0, 90), cy, cx + r.in(-60, 60), cy + r.in(-70, 70) },
        6 => v = .{ cx, cy, cx + r.in(-900, 900), cy + r.in(1, 4), cx + r.in(-3, 3), cy + r.in(-80, 80) },
        else => for (0..3) |k| {
            v[2 * k] = r.in(-16000, 16000);
            v[2 * k + 1] = r.in(-16000, 16000);
        },
    }
    var tri = Tri{ .v = v, .color = @intCast(1 + r.next() % 15) };
    if (r.next() % 4 == 0) tri.clip = .{ r.in(0, 200), r.in(LABEL_ROWS, 120), r.in(1, 200), r.in(1, 100) };
    return tri;
}
