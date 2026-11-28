// --------------------------------------------------------------------------
// RACER: the two fill paths behind poly.Emitter's `span(y, x0, x1, colour)` (the M1 A/B):
//
//   CpuSink     aligned word stores (stniccc/span.zig: head bytes, words, tail), no CHISEL
//   AffineSink  a 24-byte AFFINE record a span (six word stores), flat: the texture is ONE row of
//               the 256 palette indices, u0 = colour << 16, du = dv = 0, NO colour key (index 0
//               is a colour too). A full half of the ring becomes one CHISEL op, the emitter goes
//               on in the other half while it runs (sb_spike/sink.zig's ring); flush() fires the
//               rest. The ops run in order, so sky -> backdrop -> track need only a flush between.
// Both count spans and pixels. The AffineSink is the only one that needs the machine.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const row = @import("../stniccc/span.zig").row;
const shadow = @import("shadow.zig");

pub const Span = zg.chisel_v2.Span;
/// Spans a half (12 KB): CHISEL starts on a half while the CPU fills the other (each hwBlit waits for the previous op), so
/// a shadow's sync waits for at most one half; 2,048 left CHISEL idle until a half filled (board optimisation).
pub const CHUNK = 512;

/// Texel i = i: a span of colour c reads the one texel c of row 0.
pub const palette_row: [256]u8 align(16) = blk: {
    var t: [256]u8 = undefined;
    for (&t, 0..) |*b, i| b.* = i;
    break :blk t;
};

const TEX = zg.chisel_v2.Texture{ .pixels = &palette_row, .stride = 256, .umask = 255, .vmask = 0 };

pub const CpuSink = struct {
    base: usize = 0, // the plane's first pixel
    stride: usize = 0,
    spans: u32 = 0,
    pixels: u32 = 0,

    pub fn begin(self: *CpuSink, fb: *zg.LogicalFB) void {
        self.* = .{ .base = @intFromPtr(fb.fb), .stride = fb.stride };
    }

    pub inline fn span(self: *CpuSink, y: i32, x0: i32, x1: i32, c: u8) void {
        const a = self.base + @as(usize, @intCast(y)) * self.stride;
        row(a + @as(usize, @intCast(x0)), a + @as(usize, @intCast(x1)), c);
        self.spans += 1;
        self.pixels += @intCast(x1 - x0);
    }

    /// A shadow span: the pixels already in the plane darkened in place (shadow.zig).
    pub fn shade(self: *CpuSink, y: i32, x0: i32, x1: i32) void {
        shadow.span(self.base + @as(usize, @intCast(y)) * self.stride, y, x0, x1);
    }

    /// A smoke span: the pixels lightened in place (shadow.lightSpan, R82 bug pass).
    pub fn light(self: *CpuSink, y: i32, x0: i32, x1: i32) void {
        shadow.lightSpan(self.base + @as(usize, @intCast(y)) * self.stride, x0, x1);
    }

    pub fn flush(_: *CpuSink) void {}
};

/// The AffineSink's two halves, zeroed once: AffineSink.span writes only the three words a flat span sets.
pub fn spanBuffer() []Span {
    const b = zg.mem.mustAlloc(Span, 2 * CHUNK);
    @memset(b, @import("std").mem.zeroes(Span));
    return b;
}

pub const AffineSink = struct {
    buf: []Span, // 2 * CHUNK
    fb: *zg.LogicalFB = undefined,
    half: usize = 0,
    cur: [*]Span = undefined,
    end: [*]Span = undefined,
    os: ?*zg.ZigOS = null, // blitSync before a shadow span (the plane must hold every earlier op's pixels)
    ops: u32 = 0,
    spans: u32 = 0,
    pixels: u32 = 0,
    fired: bool = false, // an op fired since the last sync (a span still in the half is seen by cur)

    pub fn begin(self: *AffineSink, fb: *zg.LogicalFB) void {
        self.fb = fb;
        self.ops = 0;
        self.spans = 0;
        self.pixels = 0;
        self.fired = true; // WHY: a fresh begin may follow ops of another frame: the first shadow syncs, as before
        self.cur = self.buf[self.half * CHUNK ..].ptr;
        self.end = self.cur + CHUNK;
    }

    /// Three of the record's six words: v0, du and dv are zero in every flat span, and the buffer was zeroed once at init
    /// (spanBuffer) and is written by nothing else (board optimisation: 15,000 stores a 32X race frame fewer).
    pub inline fn span(self: *AffineSink, y: i32, x0: i32, x1: i32, c: u8) void {
        if (self.cur == self.end) self.flush();
        const s: *[6]u32 = @ptrCast(&self.cur[0]);
        self.cur += 1;
        self.pixels +%= @intCast(x1 - x0);
        s[0] = @as(u32, @bitCast(x0)) | @as(u32, @bitCast(x1)) << 16;
        s[1] = @bitCast(y);
        s[2] = @as(u32, c) << 16;
    }

    /// A shadow span reads the plane: fire what is queued, wait for CHISEL (once per run of shadow spans), then the CPU
    /// darkens it in place like the CPU path. ~800 cycles of op + the stall a car on the board (docs M5.md step 3).
    pub fn shade(self: *AffineSink, y: i32, x0: i32, x1: i32) void {
        self.sync();
        shadow.span(@intFromPtr(self.fb.fb) + @as(usize, @intCast(y)) * self.fb.stride, y, x0, x1);
    }

    /// A smoke span reads the plane too: the same sync, then lightened in place.
    pub fn light(self: *AffineSink, y: i32, x0: i32, x1: i32) void {
        self.sync();
        shadow.lightSpan(@intFromPtr(self.fb.fb) + @as(usize, @intCast(y)) * self.fb.stride, x0, x1);
    }

    /// Wait for CHISEL once per run of shadow / smoke spans: only when a span was queued or an op fired since the last wait.
    fn sync(self: *AffineSink) void {
        if (!self.fired and self.cur == self.buf[self.half * CHUNK ..].ptr) return;
        self.flush();
        if (self.os) |os| os.blitSync();
        self.fired = false;
    }

    /// Fire what this half holds as one op and go on in the other half.
    pub noinline fn flush(self: *AffineSink) void {
        const start = self.buf[self.half * CHUNK ..].ptr;
        const n = (@intFromPtr(self.cur) - @intFromPtr(start)) / @sizeOf(Span);
        if (n != 0) {
            zg.chisel_v2.affine(self.fb, TEX, start[0..n], .{});
            self.ops += 1;
            self.spans += @intCast(n);
            self.fired = true;
        }
        self.half ^= 1;
        self.cur = self.buf[self.half * CHUNK ..].ptr;
        self.end = self.cur + CHUNK;
    }
};
