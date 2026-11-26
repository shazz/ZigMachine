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
pub const CHUNK = 2048; // spans a half: 48 KB

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

    pub fn flush(_: *CpuSink) void {}
};

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
    synced: bool = false, // no op fired since the last sync: a car's next shadow spans need none

    pub fn begin(self: *AffineSink, fb: *zg.LogicalFB) void {
        self.fb = fb;
        self.ops = 0;
        self.spans = 0;
        self.pixels = 0;
        self.synced = false;
        self.cur = self.buf[self.half * CHUNK ..].ptr;
        self.end = self.cur + CHUNK;
    }

    pub inline fn span(self: *AffineSink, y: i32, x0: i32, x1: i32, c: u8) void {
        if (self.cur == self.end) self.flush();
        const s: *[6]u32 = @ptrCast(&self.cur[0]);
        self.cur += 1;
        self.pixels +%= @intCast(x1 - x0);
        s.* = .{ @as(u32, @bitCast(x0)) | @as(u32, @bitCast(x1)) << 16, @bitCast(y), @as(u32, c) << 16, 0, 0, 0 };
        self.synced = false;
    }

    /// A shadow span reads the plane: fire what is queued, wait for CHISEL (once per run of shadow spans), then the CPU
    /// darkens it in place like the CPU path. ~800 cycles of op + the stall a car on the board (docs M5.md step 3).
    pub fn shade(self: *AffineSink, y: i32, x0: i32, x1: i32) void {
        if (!self.synced) {
            self.flush();
            if (self.os) |os| os.blitSync();
            self.synced = true;
        }
        shadow.span(@intFromPtr(self.fb.fb) + @as(usize, @intCast(y)) * self.fb.stride, y, x0, x1);
    }

    /// Fire what this half holds as one op and go on in the other half.
    pub noinline fn flush(self: *AffineSink) void {
        const start = self.buf[self.half * CHUNK ..].ptr;
        const n = (@intFromPtr(self.cur) - @intFromPtr(start)) / @sizeOf(Span);
        if (n != 0) {
            zg.chisel_v2.affine(self.fb, TEX, start[0..n], .{});
            self.ops += 1;
            self.spans += @intCast(n);
        }
        self.half ^= 1;
        self.cur = self.buf[self.half * CHUNK ..].ptr;
        self.end = self.cur + CHUNK;
    }
};
