// RACER natively: the clipper (near plane + guard band), the frame's sort and the benchmark's
// bookkeeping. `--break clip` is clip.break_canonical: faces sharing an edge then cut it at two
// different points (a visible seam), which the shared-edge test must see.
const std = @import("std");
const bench = @import("bench.zig");
const cam = @import("cam.zig");
const clip = @import("clip.zig");
const data = @import("data.zig");
const frame = @import("frame.zig");
const trk = @import("trk.zig");
const xf = @import("xform.zig");

const Q = 65536;

fn quad(pts: [4]clip.V3) clip.Poly {
    var p = clip.Poly{ .n = 4 };
    p.p[0..4].* = pts;
    return p;
}

test "a polygon behind the near plane vanishes; one in front is untouched" {
    var behind = quad(.{ .{ 0, 0, 100 }, .{ Q, 0, 100 }, .{ Q, Q, 100 }, .{ 0, Q, 100 } });
    clip.clip(&behind, 1);
    try std.testing.expectEqual(@as(usize, 0), behind.n);
    var front = quad(.{ .{ 0, 0, 2 * Q }, .{ Q, 0, 2 * Q }, .{ Q, Q, 3 * Q }, .{ 0, Q, 3 * Q } });
    const before = front;
    clip.clip(&front, 0x1F);
    try std.testing.expectEqual(@as(usize, 4), front.n);
    try std.testing.expectEqualSlices(clip.V3, before.p[0..4], front.p[0..4]);
}

test "a quad across the near plane gains a vertex and every vertex has z >= NEAR, the cuts at NEAR" {
    var p = quad(.{ .{ -Q, 0, -Q }, .{ Q, 0, -Q }, .{ Q, 0, 4 * Q }, .{ -Q, 0, 4 * Q } });
    clip.clip(&p, 1);
    try std.testing.expectEqual(@as(usize, 4), p.n);
    var cuts: u32 = 0;
    for (p.p[0..p.n]) |v| {
        try std.testing.expect(v[2] >= clip.NEAR);
        if (v[2] == clip.NEAR) cuts += 1;
    }
    try std.testing.expectEqual(@as(u32, 2), cuts);
}

test "the guard band: a vertex far to the side is cut to |x| <= 3z; all planes at once give at most nine vertices" {
    var p = quad(.{ .{ -50 * Q, -50 * Q, Q }, .{ 50 * Q, -50 * Q, Q }, .{ 50 * Q, 50 * Q, 40 * Q }, .{ -50 * Q, 50 * Q, 40 * Q } });
    clip.clip(&p, 0x1F);
    try std.testing.expect(p.n >= 3 and p.n <= clip.MAXV);
    for (p.p[0..p.n]) |v| try std.testing.expect(v[2] >= clip.NEAR and @abs(v[0]) <= 3 * v[2] + 256 and @abs(v[1]) <= 3 * v[2] + 256);
}

/// Two quads that share the edge (a, b), both crossing z = NEAR: the seam's cut points.
fn seamCuts(flip: bool) [2]clip.V3 {
    const a: clip.V3 = .{ 40 * Q + 123, 3 * Q + 7, 7 * Q + 11 };
    const b: clip.V3 = .{ -31 * Q + 55, 9 * Q + 91, -5 * Q + 3 };
    var one = quad(.{ a, b, .{ -31 * Q, 20 * Q, -5 * Q }, .{ 40 * Q, 20 * Q, 7 * Q } });
    var two = quad(.{ b, a, .{ 40 * Q, -9 * Q, 7 * Q }, .{ -31 * Q, -9 * Q, -5 * Q } }); // the edge walked the other way
    clip.break_canonical = flip;
    defer clip.break_canonical = false;
    clip.clip(&one, 1);
    clip.clip(&two, 1);
    var out: [2]clip.V3 = undefined;
    for ([_]*clip.Poly{ &one, &two }, 0..) |p, k| {
        for (p.p[0..p.n]) |v| if (v[2] == clip.NEAR and v[1] >= 3 * Q and v[1] <= 9 * Q + 100) {
            out[k] = v; // the cut on the shared edge: its y lies between the edge's ends
        };
    }
    return out;
}

test "two faces sharing an edge cut it at the very same point; --break clip makes them differ" {
    const ok = seamCuts(false);
    try std.testing.expectEqualSlices(i32, &ok[0], &ok[1]);
    const bad = seamCuts(true);
    try std.testing.expect(!std.mem.eql(i32, &bad[0], &bad[1]));
}

test "the sort is far to near, stable, keeps a decal behind its parent, and a full buffer drops and counts" {
    const t = try trk.parse(data.city);
    var f = try newFrame(t.verts.len, t.faces.len, frame.MAXP);
    defer freeFrame(&f);
    const v = cam.view(cam.fixedPose(&t, 2));
    f.visibility(&t, &v, 5);
    f.collect(&t, &v, true);
    f.sort();
    try std.testing.expect(f.stats.polys > 300 and f.stats.back > 100 and f.stats.faces > f.stats.polys / 3);
    var last: u16 = 0;
    var last_i: u16 = 0;
    for (f.order[0..f.stats.polys]) |i| {
        const k = f.key[i];
        try std.testing.expect(k > last or (k == last and i > last_i) or (k == 0 and last == 0));
        last = k;
        last_i = i;
    }
    var small = try newFrame(t.verts.len, t.faces.len, 10);
    defer freeFrame(&small);
    small.visibility(&t, &v, 5);
    small.collect(&t, &v, true);
    try std.testing.expectEqual(@as(u32, 10), small.stats.polys);
    try std.testing.expect(small.stats.dropped > 0);
}

test "decals off draws fewer polygons than decals on" {
    const t = try trk.parse(data.oval);
    var f = try newFrame(t.verts.len, t.faces.len, frame.MAXP);
    defer freeFrame(&f);
    const v = cam.view(cam.fixedPose(&t, 2));
    f.visibility(&t, &v, 5);
    f.collect(&t, &v, true);
    const on = f.stats.polys;
    f.visibility(&t, &v, 5);
    f.collect(&t, &v, false);
    try std.testing.expect(f.stats.polys < on);
}

fn newFrame(nv: usize, nf: usize, cap: usize) !frame.Frame {
    const a = std.testing.allocator;
    const count = try a.create([frame.BUCKETS + 1]u32);
    const e = try a.alloc(xf.Entry, nv);
    @memset(e, std.mem.zeroes(xf.Entry));
    const seen = try a.alloc(u32, nf);
    @memset(seen, 0);
    return .{
        .cache = .{ .e = e },
        .kept = try a.alloc(frame.Rec, cap),
        .key = try a.alloc(u16, cap),
        .order = try a.alloc(u16, cap),
        .count = count,
        .seen = seen,
    };
}

fn freeFrame(f: *frame.Frame) void {
    const a = std.testing.allocator;
    a.free(f.cache.e);
    a.free(f.kept);
    a.free(f.key);
    a.free(f.order);
    a.destroy(f.count);
    a.free(f.seen);
}

var fake_now: u32 = 0;
fn fakeClock() u32 {
    return fake_now;
}

test "the bench: stages add up, a window closes after 32 frames, the CSV and summary lines are what the harness reads" {
    var b = bench.Bench{ .now = fakeClock };
    var closed: u32 = 0;
    for (0..64) |i| {
        fake_now = @intCast(1000 + i * 20000);
        b.frameStart();
        fake_now += 4000;
        b.lap(.vis);
        fake_now += 6000;
        b.lap(.fill);
        fake_now += 1000;
        if (b.frameEnd()) {
            closed += 1;
            b.resetWindow();
        }
    }
    try std.testing.expectEqual(@as(u32, 2), closed);
    try std.testing.expectEqual(@as(u32, 4000), b.stage_us[0]);
    try std.testing.expectEqual(@as(u32, 6000), b.stage_us[4]);
    try std.testing.expectEqual(@as(u32, 11000), b.avg_us);
    try std.testing.expectEqual(@as(u32, 500), b.fps10); // 20 ms a frame = 50 fps
    var buf: [200]u8 = undefined;
    const k = bench.Knobs{ .track = "OVAL", .r = 5, .cpu = true, .mul = "mulsh" };
    const line = b.csv(&buf, 64, k, .{ .tiles = 20, .faces = 300, .verts = 800, .polys = 250, .spans = 4000, .pixels = 90000 });
    try std.testing.expect(std.mem.startsWith(u8, line, "racer,csv,64,OVAL,5,cpu,mulsh,20,300,800,250,4000,90000,4000,0,0,0,6000,0,11000,"));
    try std.testing.expect(std.mem.startsWith(u8, b.summary(&buf, k, 0xABCD), "racer,lap,64,OVAL R5 cpu mulsh,11000,"));
    var tiny: [8]u8 = undefined;
    try std.testing.expectEqualStrings("racer,csv,overflow", b.csv(&tiny, 1, k, .{}));
}
