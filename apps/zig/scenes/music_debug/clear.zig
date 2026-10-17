// --------------------------------------------------------------------------
// Clearing only what was drawn, the way an ST screen restores its sprites:
// the four planes are 304 KB a frame to memset, and most of it never holds a
// pixel. Every plane is cleared whole once at init; after that
//   - the starfield erases last frame's 200 star pixels,
//   - the text and logo planes clear only the rows they can reach,
//   - the scope plane is cleared only while a scope is (or just was) drawn.
// The pixels are the same as a full clear, since nothing else writes there.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const LogicalFB = zg.LogicalFB;

// Rows [first, last] of `fb` back to `color`.
pub fn rows(fb: *LogicalFB, first: u16, last: u16, color: u8) void {
    const s: usize = fb.stride;
    @memset(fb.fb[@as(usize, first) * s .. (@as(usize, last) + 1) * s], color);
}

// The star pixels Starfield3D.render() drew (its rule: a star whose previous
// projection was on screen is plotted at its current one, clipped).
pub fn StarEraser(comptime n: usize) type {
    return struct {
        idx: [n]u32 = undefined,
        len: usize = 0,

        pub fn erase(self: *@This(), fb: *LogicalFB) void {
            for (self.idx[0..self.len]) |i| fb.fb[i] = 0;
            self.len = 0;
        }

        pub fn record(self: *@This(), fb: *LogicalFB, stars: anytype, w: f32, h: f32) void {
            for (stars) |*s| {
                if (!(s.prev_proj_x > 0 and s.prev_proj_x < w and s.prev_proj_y > 0 and s.prev_proj_y < h)) continue;
                const x: u16 = @intFromFloat(s.proj_x);
                const y: u16 = @intFromFloat(s.proj_y);
                if (x >= fb.fb_w or y >= fb.fb_h) continue;
                self.idx[self.len] = @as(u32, y) * fb.stride + x;
                self.len += 1;
            }
        }
    };
}
