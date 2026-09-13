// --------------------------------------------------------------------------
// ZX0 packer: the build-time half of zx0.zig.
//
// It emits the ZigMachine container described in zx0.zig (magic, version,
// depack effect, depacked length, optional message, ZX0 v2 stream). It sits next to the depacker so the tests can
// round-trip the two directly. It needs an allocator, so it is a host tool
// (tools/zx0pack/main.zig) and never linked into a cart.
//
// The parse is near-optimal, in the style of Emmanuel Marty's salvador rather
// than the ZX0 reference's exhaustive search. Every position keeps the K
// cheapest ways of arriving there. They are told apart by last offset and by
// whether the arrival ended on literals, because a repeat match is only legal
// straight after literals. Each arrival is extended by one literal, by repeat
// matches at its own last offset and (from the cheapest arrival only, since a
// new offset forgets history) by new-offset matches. New-offset matches come
// from a two-byte hash chain.
//
// Costs are exact bit counts. Two shortcuts keep it fast:
//   - match lengths beyond 16 are only tried at Elias-gamma cost boundaries
//     (2^k-1, 2^k, 2^k+1) and at the maximum;
//   - inside a match of NICE or more bytes, the chain is not walked again: the
//     same offset, one byte shorter, is carried forward instead.
// --------------------------------------------------------------------------
const std = @import("std");
/// Re-exported so the host tool can verify what it packs.
pub const zx0 = @import("zx0.zig");

const K = 4; // arrivals kept per position
const CHAIN_DEPTH = 256;
const NICE = 256;
const MAX_CMP = 65535;
const REP_CMP = 4096;
const INF = std.math.maxInt(u32);

const Kind = enum(u2) { start, literal, rep, match };

const Arrival = struct {
    cost: u32 = INF,
    offset: u32 = 1,
    len: u32 = 0,
    parent_pos: u32 = 0,
    parent_slot: u8 = 0,
    kind: Kind = .start,
};

const Block = struct { kind: Kind, len: u32, offset: u32 };
const Match = struct { offset: u32, len: u32 };

pub const Error = error{ OutOfMemory, TooLarge, TextRequired, TextNotAllowed, TextTooLong, TextNotPrintable, BarsRequired, BarsNotAllowed };

/// The depack effect recorded in the container (see zx0.zig).
pub const Options = struct {
    fx: zx0.Fx = .none,
    /// Required with fx == .text, rejected otherwise.
    text: []const u8 = "",
    /// AtariDecrunch's MaxBarHeight: required with fx == .automation, rejected
    /// otherwise. Kick Off 2 (CODEF 168) uses 100, Elite Snooker (CODEF 422) 30.
    bars: ?u8 = null,
};

/// The effect named on a command line, or null for a name that is not one.
pub fn parseFx(name: []const u8) ?zx0.Fx {
    return std.meta.stringToEnum(zx0.Fx, name);
}

fn validate(options: Options) Error!void {
    if (options.fx == .automation and options.bars == null) return error.BarsRequired;
    if (options.fx != .automation and options.bars != null) return error.BarsNotAllowed;
    if (options.fx != .text) {
        if (options.text.len != 0) return error.TextNotAllowed;
        return;
    }
    if (options.text.len == 0) return error.TextRequired;
    if (options.text.len > zx0.MAX_TEXT) return error.TextTooLong;
    if (!zx0.isPrintable(options.text)) return error.TextNotPrintable;
}

/// Pack `input` into a ZigMachine ZX0 container. The caller owns the result.
pub fn pack(gpa: std.mem.Allocator, input: []const u8, options: Options) Error![]u8 {
    if (input.len > std.math.maxInt(u32) - 1) return error.TooLarge;
    try validate(options);
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    try out.appendSlice(gpa, zx0.MAGIC);
    try out.appendSlice(gpa, &.{ zx0.VERSION, @intFromEnum(options.fx) });
    var len_le: [4]u8 = undefined;
    std.mem.writeInt(u32, &len_le, @intCast(input.len), .little);
    try out.appendSlice(gpa, &len_le);
    if (options.fx == .text) {
        try out.append(gpa, @intCast(options.text.len));
        try out.appendSlice(gpa, options.text);
    }
    if (options.fx == .automation) try out.append(gpa, options.bars.?);
    if (input.len == 0) return out.toOwnedSlice(gpa);

    const blocks = try parse(gpa, input);
    defer gpa.free(blocks);
    var w = Writer{ .gpa = gpa, .out = &out };
    try emit(&w, input, blocks);
    return out.toOwnedSlice(gpa);
}

fn gammaBits(v: u32) u32 {
    return 2 * (31 - @as(u32, @clz(v))) + 1;
}

fn newMatchBits(offset: u32, len: u32) u32 {
    // 1 indicator + gamma(msb) + 7 (the low byte shares a bit with the length) + gamma(len-1)
    return 1 + gammaBits((offset - 1) / 128 + 1) + 7 + gammaBits(len - 1);
}

fn parse(gpa: std.mem.Allocator, input: []const u8) Error![]Block {
    const n = input.len;
    const arr = try gpa.alloc(Arrival, (n + 1) * K);
    defer gpa.free(arr);
    @memset(arr, .{});
    arr[0] = .{ .cost = 0, .kind = .start };

    var finder = try Finder.init(gpa, input);
    defer finder.deinit(gpa);

    for (0..n) |p| {
        const here = arr[p * K ..][0..K];
        finder.find(p);
        var best: ?u8 = null;
        for (here, 0..) |a, s| {
            if (a.cost == INF) continue;
            const slot: u8 = @intCast(s);
            offerLiteral(arr, p, slot, a);
            if (a.kind == .literal) offerReps(arr, &finder, p, slot, a);
            if (a.kind != .start and (best == null or a.cost < here[best.?].cost)) best = slot;
        }
        if (best) |b| offerMatches(arr, &finder, p, b, here[b].cost);
        finder.insert(p);
    }
    return backtrack(gpa, arr, n);
}

fn offer(slots: []Arrival, cand: Arrival) void {
    var worst: usize = 0;
    for (slots, 0..) |*s, i| {
        if (s.cost != INF and s.offset == cand.offset and isLiteral(s.kind) == isLiteral(cand.kind)) {
            if (cand.cost < s.cost) s.* = cand;
            return;
        }
        if (s.cost > slots[worst].cost) worst = i;
    }
    if (cand.cost < slots[worst].cost) slots[worst] = cand;
}

fn isLiteral(k: Kind) bool {
    return k == .literal;
}

fn slotsAt(arr: []Arrival, q: usize) []Arrival {
    return arr[q * K ..][0..K];
}

fn offerLiteral(arr: []Arrival, p: usize, s: u8, a: Arrival) void {
    const c: Arrival = if (a.kind == .literal) .{
        .cost = a.cost + 8 + gammaBits(a.len + 1) - gammaBits(a.len),
        .offset = a.offset,
        .len = a.len + 1,
        .parent_pos = a.parent_pos,
        .parent_slot = a.parent_slot,
        .kind = .literal,
    } else .{
        .cost = a.cost + 1 + 1 + 8,
        .offset = a.offset,
        .len = 1,
        .parent_pos = @intCast(p),
        .parent_slot = s,
        .kind = .literal,
    };
    offer(slotsAt(arr, p + 1), c);
}

fn offerReps(arr: []Arrival, f: *Finder, p: usize, s: u8, a: Arrival) void {
    if (a.offset > p) return;
    const max = f.repLen(p, a.offset);
    var buf: [64]u32 = undefined;
    for (lengthSet(1, max, &buf)) |l| {
        offer(slotsAt(arr, p + l), .{
            .cost = a.cost + 1 + gammaBits(l),
            .offset = a.offset,
            .len = l,
            .parent_pos = @intCast(p),
            .parent_slot = s,
            .kind = .rep,
        });
    }
}

fn offerMatches(arr: []Arrival, f: *Finder, p: usize, s: u8, base: u32) void {
    var prev: u32 = 1;
    var buf: [64]u32 = undefined;
    for (f.found[0..f.nfound]) |m| {
        for (lengthSet(prev + 1, m.len, &buf)) |l| {
            offer(slotsAt(arr, p + l), .{
                .cost = base + newMatchBits(m.offset, l),
                .offset = m.offset,
                .len = l,
                .parent_pos = @intCast(p),
                .parent_slot = s,
                .kind = .match,
            });
        }
        prev = m.len;
    }
}

/// The lengths worth costing in [lo, hi]: everything up to 16, then only the
/// Elias-gamma cost boundaries, then hi itself. Ascending, no duplicates.
fn lengthSet(lo: u32, hi: u32, buf: *[64]u32) []u32 {
    var n: usize = 0;
    var l = lo;
    while (l <= hi and l <= 16) : (l += 1) {
        buf[n] = l;
        n += 1;
    }
    var k: u5 = 5;
    while (k < 31 and (@as(u32, 1) << k) - 1 <= hi) : (k += 1) {
        const p2 = @as(u32, 1) << k;
        for ([_]u32{ p2 - 1, p2, p2 + 1 }) |c| {
            if (c >= l and c < hi) {
                buf[n] = c;
                n += 1;
                l = c + 1;
            }
        }
    }
    if (hi >= l) {
        buf[n] = hi;
        n += 1;
    }
    return buf[0..n];
}

fn backtrack(gpa: std.mem.Allocator, arr: []Arrival, n: usize) Error![]Block {
    const end = slotsAt(arr, n);
    var slot: usize = 0;
    for (end, 0..) |a, i| if (a.cost < end[slot].cost) {
        slot = i;
    };
    var blocks: std.ArrayList(Block) = .empty;
    errdefer blocks.deinit(gpa);
    var pos = n;
    while (pos > 0) {
        const a = arr[pos * K + slot];
        try blocks.append(gpa, .{ .kind = a.kind, .len = a.len, .offset = a.offset });
        pos = a.parent_pos;
        slot = a.parent_slot;
    }
    std.mem.reverse(Block, blocks.items);
    return blocks.toOwnedSlice(gpa);
}

fn emit(w: *Writer, input: []const u8, blocks: []const Block) Error!void {
    var pos: usize = 0;
    for (blocks, 0..) |b, i| {
        switch (b.kind) {
            .literal => {
                if (i != 0) try w.bit(0);
                try w.gamma(b.len, false);
                try w.out.appendSlice(w.gpa, input[pos..][0..b.len]);
            },
            .rep => {
                try w.bit(0);
                try w.gamma(b.len, false);
            },
            .match => {
                try w.bit(1);
                try w.gamma((b.offset - 1) / 128 + 1, true);
                try w.out.append(w.gpa, @intCast((127 - (b.offset - 1) % 128) << 1));
                w.backtrack = true;
                try w.gamma(b.len - 1, false);
            },
            .start => unreachable,
        }
        pos += b.len;
    }
    try w.bit(1);
    try w.gamma(256, true);
}

const Writer = struct {
    gpa: std.mem.Allocator,
    out: *std.ArrayList(u8),
    bit_index: usize = 0,
    mask: u8 = 0,
    backtrack: bool = false,

    fn bit(self: *Writer, v: u1) Error!void {
        if (self.backtrack) {
            if (v == 1) self.out.items[self.out.items.len - 1] |= 1;
            self.backtrack = false;
            return;
        }
        self.mask >>= 1;
        if (self.mask == 0) {
            self.mask = 0x80;
            self.bit_index = self.out.items.len;
            try self.out.append(self.gpa, 0);
        }
        if (v == 1) self.out.items[self.bit_index] |= self.mask;
    }

    fn gamma(self: *Writer, value: u32, invert: bool) Error!void {
        var i = @as(u32, 1) << @intCast(31 - @as(u32, @clz(value)));
        while (true) {
            i >>= 1;
            if (i == 0) break;
            try self.bit(0);
            try self.bit(@intFromBool((value & i != 0) != invert));
        }
        try self.bit(1);
    }
};

const Finder = struct {
    input: []const u8,
    head: []i32,
    prev: []i32,
    found: [48]Match = undefined,
    nfound: usize = 0,
    carry: Match = .{ .offset = 0, .len = 0 },

    fn init(gpa: std.mem.Allocator, input: []const u8) Error!Finder {
        const head = try gpa.alloc(i32, 1 << 16);
        errdefer gpa.free(head);
        const prev = try gpa.alloc(i32, input.len);
        @memset(head, -1);
        return .{ .input = input, .head = head, .prev = prev };
    }

    fn deinit(self: *Finder, gpa: std.mem.Allocator) void {
        gpa.free(self.head);
        gpa.free(self.prev);
    }

    fn key(self: *const Finder, p: usize) usize {
        return @as(usize, self.input[p]) << 8 | self.input[p + 1];
    }

    fn insert(self: *Finder, p: usize) void {
        if (p + 2 > self.input.len) return;
        const k = self.key(p);
        self.prev[p] = self.head[k];
        self.head[k] = @intCast(p);
    }

    fn matchLen(self: *const Finder, p: usize, offset: usize, cap: usize) u32 {
        const max = @min(cap, self.input.len - p);
        var l: usize = 0;
        while (l < max and self.input[p + l] == self.input[p + l - offset]) l += 1;
        return @intCast(l);
    }

    fn repLen(self: *const Finder, p: usize, offset: u32) u32 {
        if (self.carry.len > 0 and offset == self.carry.offset) return self.carry.len;
        return self.matchLen(p, offset, REP_CMP);
    }

    /// Fill `found` with matches at p, ascending offset, each longer than the last.
    fn find(self: *Finder, p: usize) void {
        self.nfound = 0;
        if (self.carry.len > NICE) {
            self.carry.len -= 1;
            self.found[0] = self.carry;
            self.nfound = 1;
            return;
        }
        self.carry.len = 0;
        if (p + 2 > self.input.len) return;
        var cand = self.head[self.key(p)];
        var best: u32 = 1;
        var depth: usize = 0;
        while (cand >= 0 and depth < CHAIN_DEPTH) : (depth += 1) {
            const offset = p - @as(usize, @intCast(cand));
            if (offset > zx0.MAX_OFFSET) break;
            const l = self.matchLen(p, offset, MAX_CMP);
            if (l > best) {
                best = l;
                self.found[self.nfound] = .{ .offset = @intCast(offset), .len = l };
                self.nfound += 1;
                if (l >= NICE or self.nfound == self.found.len) break;
            }
            cand = self.prev[@intCast(cand)];
        }
        if (best >= NICE) self.carry = self.found[self.nfound - 1];
    }
};
