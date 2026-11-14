// The order the samples are taken in, the same for the three modes.
//
// Pass 0 is the first picture: progress.zig's coarse-to-fine cells (8x8 blocks
// first, each pixel traced once), sample 0 each. Passes 1..N-1 refine: they sweep
// the image row by row, each pixel taking sample samples.pick(pass, its Bayer rank),
// so every pixel ends with the same N samples whatever the order.
//
// take() never crosses a pass: the chunk that holds a pass's last sample ends it
// (and the frame with it, app.zig), as the first picture always did.
const trace = @import("trace.zig");
const samples = @import("samples.zig");
const colour = @import("colour.zig");
const Progress = @import("progress.zig").Progress;

pub const PASSES: u32 = samples.N;
pub const TOTAL: u32 = trace.IMG_W * trace.IMG_H;

/// One sample to take: the cell it paints in pass 0 (size x size from (x, y)), sample j.
pub const Item = struct { x: u16, y: u16, size: u8, j: u8 };

pub const Work = struct {
    progress: Progress,
    pass: u32, // passes complete; PASSES = converged
    first: u32, // pass 0's samples so far
    x: u32, // a refinement pass's cursor
    y: u32,

    pub fn start(self: *Work) void {
        self.progress.start();
        self.pass = 0;
        self.first = 0;
        self.x = 0;
        self.y = 0;
    }

    pub fn converged(self: *const Work) bool {
        return self.pass >= PASSES;
    }

    /// Samples taken over all passes, for the progress bar.
    pub fn taken(self: *const Work) u32 {
        if (self.pass == 0) return self.first;
        if (self.converged()) return PASSES * TOTAL;
        return self.pass * TOTAL + self.y * trace.IMG_W + self.x;
    }

    /// Fills `out` with the running pass's next samples; fewer when the pass ends,
    /// and then `pass` has moved on.
    pub fn take(self: *Work, out: []Item) u32 {
        if (self.converged()) return 0;
        return if (self.pass == 0) self.takeFirst(out) else self.takeRefine(out);
    }

    fn takeFirst(self: *Work, out: []Item) u32 {
        var n: u32 = 0;
        while (n < out.len) : (n += 1) {
            const c = self.progress.next() orelse break;
            out[n] = .{ .x = @intCast(c.x), .y = @intCast(c.y), .size = @intCast(c.size), .j = 0 };
        }
        self.first += n;
        if (self.first == TOTAL) self.pass = 1;
        return n;
    }

    fn takeRefine(self: *Work, out: []Item) u32 {
        var n: u32 = 0;
        while (n < out.len) : (n += 1) {
            const j = samples.pick(self.pass, colour.rank(self.x, self.y));
            out[n] = .{ .x = @intCast(self.x), .y = @intCast(self.y), .size = 1, .j = @intCast(j) };
            self.x += 1;
            if (self.x < trace.IMG_W) continue;
            self.x = 0;
            self.y += 1;
            if (self.y < trace.IMG_H) continue;
            self.y = 0;
            self.pass += 1;
            return n + 1;
        }
        return n;
    }
};
