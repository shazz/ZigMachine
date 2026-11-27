// --------------------------------------------------------------------------
// BAD APPLE!! tile-dictionary decoder ("BATL", cart 167; the byte layout is tools/badapple/tiles.py's).
// 40 x 25 slots of 8x8 1-bit tiles; a block carries its own dictionary (codes 0 black, 1 white, 2+ its tiles)
// and starts with a key frame, so it decodes on its own. A frame paints only the slots it names.
// Pure Zig (no ZigOS dependency): native tests in tiles_test.zig.
// --------------------------------------------------------------------------
const container = @import("container.zig");

pub const MAGIC = "BATL";
pub const MAX_PACKED: usize = 64 * 1024; // the real film's largest block: 35 KB packed
pub const MAX_RAW: usize = 96 * 1024; // ...and 56 KB raw
pub const MAX_TILES: usize = 16382;
pub const TW: usize = 8;
pub const COLS: usize = 40;
pub const ROWS: usize = 25;
const KEY: u8 = 1;
const DELTA: u8 = 0;

/// 4 pixels (0/1 bytes, the leftmost first in memory) from a nibble (its bit 3 = the leftmost).
const NIBBLE_PX: [16]u32 = blk: {
    var t: [16]u32 = undefined;
    for (0..16) |n| {
        var v: u32 = 0;
        for (0..4) |i| v |= @as(u32, (n >> (3 - i)) & 1) << @intCast(8 * i);
        t[n] = v;
    }
    break :blk t;
};

pub const State = struct {
    dict: []const u8 = &.{}, // the block's tiles, 8 bytes each
    first: bool = true, // the next frame is a block's first (it must be a key frame)

    pub fn reset(self: *State) void {
        self.* = .{};
    }

    /// Reads a block's dictionary; the offset of its first frame, or null if the dictionary overruns.
    pub fn beginBlock(self: *State, raw: []const u8) ?usize {
        if (raw.len < 2) return null;
        const n: usize = container.readU16Le(raw[0..2]);
        if (n > MAX_TILES or 2 + 8 * n > raw.len) return null;
        self.dict = raw[2 .. 2 + 8 * n];
        self.first = true;
        return 2 + 8 * n;
    }

    /// Paint one frame's named slots into `fb` (stride bytes a row). False on any malformed byte.
    pub fn decodeFrame(self: *State, bytes: []const u8, fb: []u8, stride: u16) bool {
        if (bytes.len == 0 or fb.len < @as(usize, stride) * container.HEIGHT or stride < container.WIDTH) return false;
        const flag = bytes[0];
        if ((flag != KEY and flag != DELTA) or (flag == KEY) != self.first) return false;
        self.first = false;
        var r = Reader{ .b = bytes, .p = 1, .limit = self.dict.len / 8 + 2 };
        if (flag == KEY) {
            for (0..ROWS * COLS) |s| {
                const code = r.code() orelse return false;
                self.paint(fb, stride, s, code);
            }
            return r.p == bytes.len;
        }
        // The masks are walked a BYTE at a time: a u32 / u64 assembled from them is merged by the compiler into
        // one unaligned wide load (a trap on the board) and costs i64 shifts on rv32.
        const rows = r.take(4) orelse return false;
        if (rows[3] >> 1 != 0) return false; // bits 25+: no such tile row
        var n_rows: usize = 0;
        for (rows) |b| n_rows += @popCount(b);
        const masks = r.take(5 * n_rows) orelse return false; // the slot masks come first, then the codes
        var m: usize = 0;
        for (0..ROWS) |row| {
            if ((rows[row >> 3] >> @intCast(row & 7)) & 1 == 0) continue;
            const mb = masks[5 * m ..][0..5];
            m += 1;
            if (mb[0] | mb[1] | mb[2] | mb[3] | mb[4] == 0) return false;
            for (mb, 0..) |bits, i| {
                if (bits == 0) continue;
                for (0..8) |bit| {
                    if ((bits >> @intCast(bit)) & 1 == 0) continue;
                    const code = r.code() orelse return false;
                    self.paint(fb, stride, row * COLS + i * 8 + bit, code);
                }
            }
        }
        return r.p == bytes.len;
    }

    fn paint(self: *const State, fb: []u8, stride: u16, slot: usize, code: usize) void {
        const x = slot % COLS * TW;
        const y = slot / COLS * TW;
        const st: usize = stride;
        const base = y * st + x;
        const aligned = (@intFromPtr(fb.ptr) + base) & 3 == 0 and st & 3 == 0;
        for (0..TW) |k| {
            const bits: u8 = switch (code) {
                0 => 0,
                1 => 0xFF,
                else => self.dict[(code - 2) * 8 + k],
            };
            const row = fb[base + k * st ..][0..TW];
            if (aligned) {
                const w: *[2]u32 = @ptrCast(@alignCast(row.ptr));
                w[0] = NIBBLE_PX[bits >> 4];
                w[1] = NIBBLE_PX[bits & 15];
            } else {
                for (0..TW) |i| row[i] = (bits >> @intCast(7 - i)) & 1;
            }
        }
    }
};

const Reader = struct {
    b: []const u8,
    p: usize,
    limit: usize, // codes are < limit

    fn take(self: *Reader, n: usize) ?[]const u8 {
        if (self.p + n > self.b.len) return null;
        self.p += n;
        return self.b[self.p - n .. self.p];
    }

    fn code(self: *Reader) ?usize {
        const lo = (self.take(1) orelse return null)[0];
        var v: usize = lo;
        if (lo & 0x80 != 0) v = (lo & 0x7F) | (@as(usize, (self.take(1) orelse return null)[0]) << 7);
        return if (v < self.limit) v else null;
    }
};
