// --------------------------------------------------------------------------
// Bad Apple!! row-transition span-delta decoder ("BASP").
// Pure Zig (no ZigOS dependency) so it can be unit-tested natively.
// --------------------------------------------------------------------------
const std = @import("std");

pub const WIDTH: u16 = 320;
pub const HEIGHT: u16 = 200;
pub const MAX_TRANS: usize = 62;
pub const HEADER_SIZE: usize = 16;
pub const BLOCK_HDR_SIZE: usize = 10;

pub const Header = struct {
    width: u16,
    height: u16,
    fps: u16,
    total_frames: u16,
    block_count: u16,
    gop_frames: u16,
};

pub const BlockHeader = struct {
    packed_len: u32,
    raw_len: u32,
    frame_count: u16,
};

fn readU16Le(b: *const [2]u8) u16 {
    return @as(u16, b[0]) | (@as(u16, b[1]) << 8);
}

fn readU32Le(b: *const [4]u8) u32 {
    return @as(u32, b[0]) | (@as(u32, b[1]) << 8) | (@as(u32, b[2]) << 16) | (@as(u32, b[3]) << 24);
}

pub fn parseHeader(data: []const u8) ?Header {
    if (data.len < HEADER_SIZE) return null;
    if (!std.mem.eql(u8, data[0..4], "BASP")) return null;
    const h: Header = .{
        .width = readU16Le(data[4..6]),
        .height = readU16Le(data[6..8]),
        .fps = readU16Le(data[8..10]),
        .total_frames = readU16Le(data[10..12]),
        .block_count = readU16Le(data[12..14]),
        .gop_frames = readU16Le(data[14..16]),
    };
    // The decoder is 320x200 only; a stream that says otherwise is refused, never painted skewed.
    if (h.width != WIDTH or h.height != HEIGHT or h.fps == 0 or h.gop_frames == 0) return null;
    return h;
}

pub fn parseBlockHeader(data: []const u8) ?BlockHeader {
    if (data.len < BLOCK_HDR_SIZE) return null;
    const b: BlockHeader = .{
        .packed_len = readU32Le(data[0..4]),
        .raw_len = readU32Le(data[4..8]),
        .frame_count = readU16Le(data[8..10]),
    };
    if (b.frame_count == 0) return null;
    return b;
}

pub const State = struct {
    counts: [HEIGHT]u8 = [_]u8{0} ** HEIGHT,
    trans: [HEIGHT][MAX_TRANS]u16 = undefined,

    pub fn reset(self: *State) void {
        @memset(&self.counts, 0);
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
