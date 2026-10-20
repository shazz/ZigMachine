// --------------------------------------------------------------------------
// STNICCC fills on the CHISEL blitter. The CPU filler spent a byte store per
// pixel (@memset, ~3 cycles each) on a 400x280 plane, which is what dropped
// the fullscreen act to ~10 fps; a FILL is one setup and then ~1 clock a pixel.
// Pixel-identical to the memset: both write the same [x, x+w) of the same row.
//
// The spans go through the blitter's QUEUE (zg.blit_queue, HW 1.8.0): a frame
// is ~1000 small fills, and a hwBlit() each cost the board ~900 cycles while a
// queued fill is a few ring stores; CHISEL draws one list while the edge walk
// builds the next. The destination is set in the list (begin()), never in the
// block, so a list never draws with a later begin()'s plane. flush() before the
// CPU touches the plane (keyframes, the message's text) and at the frame's end.
// --------------------------------------------------------------------------
const hw = @import("hardware");
const polyfill = @import("polyfill.zig");
const Queue = @import("zigos").blit_queue.Queue;

var q: Queue = .{};

/// Point the blitter at `t`'s window and return the target with fills routed to it.
pub fn begin(t: polyfill.Target) polyfill.Target {
    const base: usize = @intCast(hw.hwVideoBase());
    if (q.base != base) q.init(base);
    q.set(&.{ // MINTERM and CON 0; the fills clear CON2 (no SRC_ABS, FILL_MT or halftone)
        .{ .k = 0, .v = 0 },
        .{ .k = 8, .v = @intCast(@intFromPtr(t.px.ptr) - base) },
        .{ .k = 9, .v = @intCast(t.stride) },
    });
    var out = t;
    out.rect = fillRect;
    out.sync = flush;
    return out;
}

/// Every fill queued so far has drawn: the CPU may touch the plane.
pub fn flush() void {
    q.flush();
}

fn fillRect(x: usize, y: usize, w: usize, h: usize, color: u8) void {
    q.fill(@intCast(x), @intCast(y), @intCast(w), @intCast(h), color);
}

/// Clear a whole plane (stride x rows, as LogicalFB.clearFrameBuffer does, but not a byte loop).
pub fn clearPlane(px: []u8, stride: usize, rows: usize, color: u8) void {
    const t = begin(.{ .px = px, .stride = stride, .w = stride, .h = rows, .ox = 0 });
    t.rect.?(0, 0, stride, rows, color);
    flush();
}
