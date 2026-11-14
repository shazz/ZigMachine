// --------------------------------------------------------------------------
// SB SPIKE: where the spans go: a ring of two CHUNK-span halves in cart RAM.
//
// When a half is full it becomes one CHISEL AFFINE op over the whole atlas
// (colour key 0) and the emitter goes on in the other half. With the lazy wait
// (zg.blitAsync) the op runs while the CPU sets up the next CHUNK spans; the
// next op's hwBlit waits for it, so a half is never rewritten while CHISEL reads
// it (the list is in cart RAM, not the destination: inside the async contract).
// --------------------------------------------------------------------------
const zg = @import("zigos");
const data = @import("data.zig");

pub const CHUNK = 2048; // 48 KB a half
pub const Span = zg.chisel_v2.Span;

const TEX = zg.chisel_v2.Texture{
    .pixels = data.atlas,
    .stride = data.ATLAS_W,
    .umask = data.ATLAS_W - 1,
    .vmask = 2047, // >= ATLAS_ROWS: v never leaves the atlas (every slot's v is inside it)
};

pub const Sink = struct {
    buf: []Span, // 2 * CHUNK
    fb: *zg.LogicalFB = undefined,
    half: usize = 0,
    // The write cursor and the end of the current half: the emitter keeps them in
    // registers for a triangle and calls swap() when cur reaches end.
    cur: [*]Span = undefined,
    end: [*]Span = undefined,
    ops: u32 = 0,
    spans: u32 = 0,
    pixels: u32 = 0,

    pub fn begin(self: *Sink, fb: *zg.LogicalFB) void {
        self.fb = fb;
        self.ops = 0;
        self.spans = 0;
        self.pixels = 0;
        self.cur = self.buf[self.half * CHUNK ..].ptr;
        self.end = self.cur + CHUNK;
    }

    /// Fire the spans written in this half (cur back from the emitter), go on in the other.
    pub noinline fn swap(self: *Sink) void {
        const start = self.buf[self.half * CHUNK ..].ptr;
        const n = (@intFromPtr(self.cur) - @intFromPtr(start)) / @sizeOf(Span);
        if (n != 0) {
            zg.chisel_v2.affine(self.fb, TEX, start[0..n], .{ .key = 0 });
            self.ops += 1;
            self.spans += @intCast(n);
        }
        self.half ^= 1;
        self.cur = self.buf[self.half * CHUNK ..].ptr;
        self.end = self.cur + CHUNK;
    }
};
