// Tests for effects/blit_rows.zig: the word-store row against the plain byte
// loop it replaces, on every destination alignment, lengths 0..40, every ink
// rule, keyed and not, with runs of keyed pixels (whole words skipped, whole
// words drawn, words merged) -- and an overlapping row, which must keep the
// byte loop's order.
const std = @import("std");
const r = @import("blit_rows.zig");

const KEY: u8 = 7;

fn reference(out: []u8, in: []const u8, ctx: anytype, comptime pick: anytype) void {
    for (in, out, 0..) |p, *d, i| {
        const px: r.Px = pick(ctx, p, d.*, i);
        if (px != r.skip) d.* = @truncate(px);
    }
}

// Source bytes with long keyed runs and long drawn runs, so the word loop sees
// all-skip, all-draw and mixed words.
fn fillSource(rng: std.Random, buf: []u8) void {
    var i: usize = 0;
    while (i < buf.len) {
        const run = rng.intRangeAtMost(usize, 1, 9);
        const keyed = rng.boolean();
        var k: usize = 0;
        while (k < run and i < buf.len) : ({
            k += 1;
            i += 1;
        }) buf[i] = if (keyed) KEY else rng.int(u8);
    }
}

fn check(rng: std.Random, ctx: anytype, comptime pick: anytype, comptime reads_dst: bool) !void {
    var src: [64]u8 = undefined;
    var a: [64]u8 align(4) = undefined;
    var b: [64]u8 align(4) = undefined;
    for (0..4) |align_off| for (0..41) |len| for (0..3) |src_off| {
        fillSource(rng, &src);
        rng.bytes(&a);
        b = a;
        const in = src[src_off..][0..len];
        reference(a[align_off..][0..len], in, ctx, pick);
        r.row(b[align_off..][0..len], in, ctx, pick, reads_dst);
        try std.testing.expectEqualSlices(u8, &a, &b);
    };
}

test "keyed copy matches the byte loop" {
    var prng = std.Random.DefaultPrng.init(1);
    try check(prng.random(), KEY, r.keyedCopy, false);
}

test "every ink, keyed and not, matches the byte loop" {
    var prng = std.Random.DefaultPrng.init(2);
    const rng = prng.random();
    var lut: [256]u8 = undefined;
    rng.bytes(&lut);
    var pat: [64]u8 = undefined;
    rng.bytes(&pat);
    var set: [256]bool = undefined;
    for (&set) |*s| s.* = rng.boolean();
    const Sel = struct { set: *const [256]bool, inside: bool };
    inline for (.{ false, true }) |keyed| {
        try check(rng, r.Inked(u8, keyed){ .key = KEY, .v = 0x5A }, r.Inked(u8, keyed).flat, false);
        try check(rng, r.Inked(u8, keyed){ .key = KEY, .v = 0x81 }, r.Inked(u8, keyed).offset, false);
        try check(rng, r.Inked(*const [256]u8, keyed){ .key = KEY, .v = &lut }, r.Inked(*const [256]u8, keyed).lut, false);
        try check(rng, r.Inked([]const u8, keyed){ .key = KEY, .v = &pat }, r.Inked([]const u8, keyed).pattern, false);
        inline for (.{ false, true }) |inside| {
            try check(rng, r.Inked(Sel, keyed){ .key = KEY, .v = .{ .set = &set, .inside = inside } }, r.Inked(Sel, keyed).select, true);
        }
    }
}

test "an overlapping row keeps the byte loop's smear" {
    var a: [40]u8 = undefined;
    for (&a, 0..) |*p, i| p.* = @intCast(i + 1);
    var b = a;
    reference(a[1..33], a[0..32], KEY, r.keyedCopy);
    r.row(b[1..33], b[0..32], KEY, r.keyedCopy, false);
    try std.testing.expectEqualSlices(u8, &a, &b);
}
