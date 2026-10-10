// The progressive-refinement order. Level 0 traces every 8th pixel on an 8-px
// grid and paints each result as an 8x8 block; level 1 traces the pixels of
// the 4-px grid that level 0 did not, painting 4x4 blocks over the coarse ones;
// then 2 and 1. Every pixel is traced exactly once, for its own coordinates, so
// the finished picture does not depend on the order; the screen simply fills in
// from a blocky preview, 8x8 -> 1x1, instead of top to bottom.
const trace = @import("trace.zig");

pub const LEVELS = 4;
const STEP0: u32 = 8;

pub const Cell = struct { x: u32, y: u32, size: u32 };

pub const Progress = struct {
    level: u32,
    gx: u32,
    gy: u32,

    pub fn start(self: *Progress) void {
        self.level = 0;
        self.gx = 0;
        self.gy = 0;
    }

    /// The next pixel to trace, or null when the picture is complete.
    pub fn next(self: *Progress) ?Cell {
        while (self.level < LEVELS) {
            const s: u32 = STEP0 >> @as(u5, @intCast(self.level));
            const nx = trace.IMG_W / s;
            const ny = trace.IMG_H / s;
            while (self.gy < ny) : (self.gy += 1) {
                while (self.gx < nx) {
                    const gx = self.gx;
                    self.gx += 1;
                    const covered = self.level > 0 and gx & 1 == 0 and self.gy & 1 == 0;
                    if (!covered) return .{ .x = gx * s, .y = self.gy * s, .size = s };
                }
                self.gx = 0;
            }
            self.level += 1;
            self.gy = 0;
        }
        return null;
    }
};
