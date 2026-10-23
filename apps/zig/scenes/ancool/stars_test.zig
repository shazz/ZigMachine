// Native proof of what stars.zig relies on: AN Cool's starfield (zg.Starfield3D,
// seed 0, 300 stars, speed 5, use_lines false) draws, from frame STEADY on,
// exactly what it drew PERIOD frames before. The state below is the library's
// (libs/zig/effects/starfield_3D.zig init + update) with the same f32
// expressions; stars.zig cannot be imported here (it needs the zigos module),
// so its two constants are repeated and checked against each other.
const std = @import("std");

const STEADY = 104; // stars.zig
const PERIOD = 52; // stars.zig: 260 / 5
const NB = 300;
const FRAMES = 4000;

const Star = struct { x: f32, y: f32, z: f32, px: f32 = 0, py: f32 = 0, ppx: f32 = 0, ppy: f32 = 0 };

const Field = struct {
    stars: [NB]Star,
    const w: f32 = 320;
    const h: f32 = 200;
    const cx = w / 2;
    const cy = h / 2;
    const cz = (w + h) / 2;

    fn init() Field {
        var rnd = std.Random.DefaultPrng.init(0);
        var f: Field = undefined;
        for (&f.stars) |*s| {
            const x = rnd.random().float(f32) * (w * 1.0) - cx * 1.0;
            const y = rnd.random().float(f32) * (h * 1.0) - cy * 1.0;
            const z = rnd.random().float(f32) * cz;
            s.* = .{ .x = x, .y = y, .z = z };
        }
        return f;
    }

    fn update(f: *Field) void {
        for (&f.stars) |*s| {
            s.ppx = s.px;
            s.ppy = s.py;
            s.z -= 5;
            if (s.z > cz) s.z -= cz;
            if (s.z < 0) s.z += cz;
            s.px = cx + (s.x / s.z) * 100;
            s.py = cy + (s.y / s.z) * 100;
        }
    }
};

test "the starfield repeats every PERIOD frames from STEADY on, bit for bit" {
    var f = Field.init();
    const hist = try std.testing.allocator.alloc([NB]Star, FRAMES + 1);
    defer std.testing.allocator.free(hist);
    for (1..FRAMES + 1) |n| {
        f.update();
        hist[n] = f.stars;
    }
    for (STEADY..FRAMES + 1) |n| {
        for (hist[n], hist[n - PERIOD]) |a, b| {
            try std.testing.expect(@as(u32, @bitCast(a.z)) == @as(u32, @bitCast(b.z)));
            try std.testing.expect(a.px == b.px and a.py == b.py and a.ppx == b.ppx and a.ppy == b.ppy);
        }
    }
}

fn same(a: [NB]Star, b: [NB]Star) bool {
    for (a, b) |p, q| {
        if (p.z != q.z or p.px != q.px or p.py != q.py or p.ppx != q.ppx or p.ppy != q.ppy) return false;
    }
    return true;
}

test "STEADY is the first frame from which the field repeats (the start is a real transient)" {
    var f = Field.init();
    var hist: [STEADY + 1][NB]Star = undefined;
    for (1..STEADY + 1) |n| {
        f.update();
        hist[n] = f.stars;
    }
    try std.testing.expect(same(hist[STEADY], hist[STEADY - PERIOD]));
    try std.testing.expect(!same(hist[STEADY - 1], hist[STEADY - 1 - PERIOD]));
}
