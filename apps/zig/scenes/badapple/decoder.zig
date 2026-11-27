// --------------------------------------------------------------------------
// Bad Apple!! row-transition span-delta decoder ("BASP").
// Pure Zig (no ZigOS dependency) so it can be unit-tested natively.
// --------------------------------------------------------------------------
const container = @import("container.zig");

pub const WIDTH = container.WIDTH;
pub const HEIGHT = container.HEIGHT;
pub const MAX_TRANS: usize = 62;
pub const MAGIC = "BASP";
pub const MAX_PACKED: usize = 48 * 1024; // the real film's largest block is 41 KB
pub const MAX_RAW: usize = 96 * 1024; // ...and 76 KB raw

pub fn parseHeader(data: []const u8) ?container.Header {
    return container.parseHeader(data, MAGIC);
}
pub const parseBlockHeader = container.parseBlockHeader;

pub const State = struct {
    counts: [HEIGHT]u8 = [_]u8{0} ** HEIGHT,
    trans: [HEIGHT][MAX_TRANS]u16 = undefined,

    pub fn reset(self: *State) void {
        @memset(&self.counts, 0);
    }

    /// A block's frames start at its first byte (a spans block has no preamble).
    pub fn beginBlock(self: *State, raw: []const u8) ?usize {
        _ = self;
        _ = raw;
        return 0;
    }

    /// Decode one frame from `frame_bytes` (the raw payload inside a depacked block) and paint the rows it
    /// changes into `fb_bytes`. False on any malformed byte: the caller stops, never shows a half frame.
    pub fn decodeFrame(self: *State, frame_bytes: []const u8, fb_bytes: []u8, stride: u16) bool {
        var p: usize = 0;
        var y: usize = 0;
        while (y < HEIGHT) {
            if (p >= frame_bytes.len) return false;
            const tag = frame_bytes[p];
            p += 1;
            if (tag < 0x80) {
                y += @as(usize, tag) + 1;
                continue;
            }
            const rest = frame_bytes[p..];
            const k: usize = tag & 0x3F;
            const used = (if (tag < 0xC0) self.deltaRow(y, k, rest) else self.fullRow(y, k, rest)) orelse return false;
            p += used;
            paintRow(fb_bytes, stride, y, self.trans[y][0..self.counts[y]]);
            y += 1;
        }
        return y == HEIGHT;
    }

    /// A row with the same k transitions as before: dx -7..+7 each, two a byte (low nibble first). Bytes used.
    fn deltaRow(self: *State, y: usize, k: usize, rest: []const u8) ?usize {
        if (k == 0 or k > MAX_TRANS or self.counts[y] != k) return null;
        const n_bytes = (k + 1) / 2;
        if (n_bytes > rest.len) return null;
        for (0..k) |i| {
            const nib: i32 = (rest[i / 2] >> @as(u3, @intCast(4 * (i & 1)))) & 0x0F;
            const v = @as(i32, self.trans[y][i]) + nib - 8;
            if (v < 0 or v >= WIDTH) return null;
            self.trans[y][i] = @intCast(v);
        }
        return n_bytes;
    }

    /// A full row: k transitions, each a byte (< 128) or lo|0x80 then hi. Bytes used.
    fn fullRow(self: *State, y: usize, k: usize, rest: []const u8) ?usize {
        if (k > MAX_TRANS) return null;
        var p: usize = 0;
        for (0..k) |i| {
            if (p >= rest.len) return null;
            var val: u16 = rest[p] & 0x7F;
            const two = rest[p] & 0x80 != 0;
            p += 1;
            if (two) {
                if (p >= rest.len) return null;
                val |= @as(u16, rest[p]) << 7;
                p += 1;
            }
            if (val >= WIDTH) return null;
            self.trans[y][i] = val;
        }
        self.counts[y] = @intCast(k);
        return p;
    }
};

fn paintRow(fb_bytes: []u8, stride: u16, y: usize, trans: []const u16) void {
    const row = fb_bytes[y * @as(usize, stride) ..][0..WIDTH];
    var x: usize = 0;
    var col: u8 = 0;
    for (trans) |tx| {
        const end = @min(@as(usize, tx), WIDTH);
        if (end > x) {
            @memset(row[x..end], col);
            x = end;
        }
        col ^= 1;
    }
    if (x < WIDTH) {
        @memset(row[x..WIDTH], col);
    }
}
