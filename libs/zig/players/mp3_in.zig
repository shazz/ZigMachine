// --------------------------------------------------------------------------
// The MP3 player's input: a byte ring the cart's feeds append to (mp3.zig),
// and the framing that cuts whole Layer III frames out of it for pvmp3.
// Counters are totals (they wrap), so the cart's flow control is plain: it
// knows what it fed, the player publishes what it used (Status 1), and the
// difference is the fill. Pure: tested natively (mp3_in_test.zig).
// --------------------------------------------------------------------------
const frame = @import("mp3_frame.zig");

pub const Ring = struct {
    buf: []u8, // a power of two long: an index is a mask, not a divide (BARD has no divider)
    w: u32 = 0, // bytes written, total
    r: u32 = 0, // bytes used, total
    dropped: u32 = 0, // fed past a full ring (the cart overfed)

    pub fn fill(self: *const Ring) u32 {
        return self.w -% self.r;
    }

    /// Append `src`; what does not fit is dropped and counted.
    pub fn write(self: *Ring, src: []const u8) void {
        const room: u32 = @as(u32, @intCast(self.buf.len)) - self.fill();
        const n: u32 = @min(room, @as(u32, @intCast(src.len)));
        self.dropped +%= @as(u32, @intCast(src.len)) - n;
        for (src[0..n]) |b| {
            self.buf[self.w & (self.buf.len - 1)] = b;
            self.w +%= 1;
        }
    }

    pub fn at(self: *const Ring, k: u32) u8 {
        return self.buf[(self.r +% k) & (self.buf.len - 1)];
    }

    pub fn copyOut(self: *const Ring, dst: []u8) void {
        for (dst, 0..) |*d, k| d.* = self.at(@intCast(k));
    }

    pub fn skip(self: *Ring, n: u32) void {
        self.r +%= @min(n, self.fill());
    }

    fn header(self: *const Ring, k: u32) ?frame.Header {
        if (self.fill() < k + 4) return null;
        return frame.parse(.{ self.at(k), self.at(k + 1), self.at(k + 2), self.at(k + 3) });
    }
};

pub const Cut = union(enum) {
    frame: u32, // a whole frame of this many bytes is at the ring's read side
    wait, // not enough bytes yet
    skipped, // bytes were skipped (an ID3 tag, garbage): look again
};

/// What the ring's read side holds. A first frame (not `synced`) must be confirmed by the header
/// right after it, unless the input has ended (`eof`); an ID3v2 tag is skipped whole (`pending`
/// carries what the ring does not hold yet).
pub fn cut(ring: *Ring, synced: bool, eof: bool, pending: *u32) Cut {
    if (pending.* > 0) {
        const n = @min(pending.*, ring.fill());
        ring.skip(n);
        pending.* -= n;
        return if (n > 0) .skipped else .wait;
    }
    if (ring.fill() < 4) return .wait;
    if (!synced and ring.at(0) == 'I' and ring.at(1) == 'D' and ring.at(2) == '3') {
        if (ring.fill() < 10) return .wait;
        var tag: [10]u8 = undefined;
        ring.copyOut(&tag);
        pending.* = frame.id3Len(&tag);
        return .skipped;
    }
    const h = ring.header(0) orelse {
        ring.skip(1);
        return .skipped;
    };
    if (ring.fill() < h.len) return if (eof) drain(ring) else .wait;
    if (!synced and !eof) {
        if (ring.fill() < h.len + 4) return .wait;
        const next = ring.header(h.len) orelse {
            ring.skip(1);
            return .skipped;
        };
        if (next.rate != h.rate) {
            ring.skip(1);
            return .skipped;
        }
    }
    return .{ .frame = h.len };
}

/// The input has ended inside a frame: drop the tail.
fn drain(ring: *Ring) Cut {
    ring.skip(ring.fill());
    return .wait;
}
