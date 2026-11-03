// --------------------------------------------------------------------------
// klystron's wavetable sample packing (pack.c bitunpack): 16 bit planes, each
// all-0, all-1, literal or run-length (Elias gamma), then optionally Gray- and
// delta-decoded. Integer only, run once at load.
// --------------------------------------------------------------------------

const STATIC0 = 0;
const STATIC1 = 1;
const LITERAL = 2;
const RLE = 3;
const OPT_DELTA: u32 = 1;
const OPT_GRAY: u32 = 2;

const Bits = struct {
    buf: []const u8,
    byte: u32 = 0,
    bit: u8 = 0,
    size_byte: u32,
    size_bit: u8,

    /// bit_r: the next bit, or null past the end (upstream's -1).
    fn r(self: *Bits) ?u1 {
        if (self.size_byte <= self.byte and self.size_bit <= self.bit) return null;
        if (self.byte >= self.buf.len) return null;
        const b: u1 = @intCast(self.buf[self.byte] >> @intCast(self.bit) & 1);
        self.bit += 1;
        if (self.bit == 8) {
            self.bit = 0;
            self.byte += 1;
        }
        return b;
    }

    fn rbits(self: *Bits, n: u5) ?u32 {
        var v: u32 = 0;
        for (0..n) |i| v |= @as(u32, self.r() orelse return null) << @intCast(i);
        return v;
    }

    /// bit_rgamma: an Elias gamma value; 0 is a read error.
    fn gamma(self: *Bits) u32 {
        var n: u32 = 0;
        while (true) {
            const b = self.r() orelse return 0;
            if (b == 1) break;
            n += 1;
            if (n > 31) return 0;
        }
        var v: u32 = 0;
        var a: i32 = @as(i32, @intCast(n)) - 1;
        while (a >= 0) : (a -= 1) {
            const b = self.r() orelse return 0;
            if (b == 1) v |= @as(u32, 1) << @intCast(a);
        }
        return v | @as(u32, 1) << @intCast(n);
    }
};

/// Unpack `size_bits` bits of `src` into `out` (zeroed first); false on a
/// stream that runs out or does not decode, as bitunpack's NULL.
pub fn unpack(src: []const u8, size_bits: u32, out: []i16, flags: u32) bool {
    var bp = Bits{ .buf = src, .size_byte = size_bits / 8, .size_bit = @intCast(size_bits & 7) };
    @memset(out, 0);
    for (0..16) |plane| {
        const mask: u16 = @as(u16, 1) << @intCast(plane);
        const kind = bp.rbits(2) orelse return false;
        switch (kind) {
            LITERAL => for (out) |*v| {
                if ((bp.r() orelse return false) == 1) v.* = @bitCast(@as(u16, @bitCast(v.*)) | mask);
            },
            STATIC1 => for (out) |*v| {
                v.* = @bitCast(@as(u16, @bitCast(v.*)) | mask);
            },
            RLE => if (!runs(&bp, out, mask)) return false,
            else => {}, // STATIC0: the plane stays clear
        }
    }
    if (flags & OPT_GRAY != 0) for (out) |*v| {
        var g: u16 = @bitCast(v.*);
        g ^= g >> 8;
        g ^= g >> 4;
        g ^= g >> 2;
        g ^= g >> 1;
        v.* = @truncate(@as(i32, g) - 32768);
    };
    if (flags & OPT_DELTA != 0) {
        var d: i32 = 0;
        for (out) |*v| {
            v.* = @truncate(@as(i32, v.*) + d);
            d = v.*;
        }
    }
    return true;
}

fn runs(bp: *Bits, out: []i16, mask: u16) bool {
    var bit: u16 = if ((bp.r() orelse return false) == 1) mask else 0;
    if (out.len == 0) return true;
    var i: usize = 0;
    while (i < out.len) {
        var ctr = bp.gamma();
        if (ctr == 0) return false;
        while (i < out.len and ctr != 0) : ({
            i += 1;
            ctr -= 1;
        }) out[i] = @bitCast(@as(u16, @bitCast(out[i])) | bit);
        if (ctr != 0) return false;
        bit ^= mask;
    }
    return true;
}
