// --------------------------------------------------------------------------
// KESTREL BOOT: the stoop. The bird's texture (bird.zig) is drawn by CHISEL AFFINE, a
// span a screen row, over only the rows and columns it covers, while it dives from the
// upper right at 3x and banked to the centre at exactly 1:1 (timeline.EASE, which
// overshoots and settles: the bird brakes into its hover). Once landed nothing is
// drawn again: a hovering kestrel does not move.
// Integer only: zg.fixtrig angles, Q16.16 steps, i64 products.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const trig = zg.fixtrig;
const v2 = zg.chisel_v2;
const tl = @import("timeline.zig");
const bird = @import("bird.zig");

const SW: i32 = 320;
const SH: i32 = 200;
pub const REST_X: i32 = 160; // where texel CENTRE lands, visible pixels
pub const REST_Y: i32 = 66;
const FROM_X: i32 = 300;
const FROM_Y: i32 = -20;
const FROM_SCALE: i32 = 3 * tl.ONE;
const FROM_ANGLE: i64 = -(1 << 32) / 11; // about -33 degrees: banked into the dive

pub const Pose = struct { x: i32, y: i32, scale: i32, angle: trig.Angle };

fn along(a: i64, b: i64, e: i64) i64 {
    return a + @divFloor((b - a) * e, tl.ONE);
}

/// The bird's pose `k` frames into the stoop (0..STOOP_FRAMES): exactly 1:1 at the end.
pub fn pose(k: u32) Pose {
    const e: i64 = tl.EASE[@min(k, tl.STOOP_FRAMES)];
    const ang = along(FROM_ANGLE, 0, e);
    return .{
        .x = @intCast(along(FROM_X, REST_X, e)),
        .y = @intCast(along(FROM_Y, REST_Y, e)),
        .scale = @intCast(@max(tl.ONE / 4, along(FROM_SCALE, tl.ONE, e))),
        .angle = @truncate(@as(u64, @bitCast(ang))),
    };
}

pub const Box = struct { x0: i32, y0: i32, x1: i32, y1: i32 };

pub const Stoop = struct {
    spans: []v2.Span,
    tex: v2.Texture,
    last: ?Box = null, // what the previous frame drew, to clear

    /// Draws the bird at `p` on `fb` (clearing where it was): one FILL, one AFFINE.
    pub fn draw(s: *Stoop, fb: *zg.LogicalFB, p: Pose) void {
        if (s.last) |b| fb.fillRect(b.x0, b.y0, @intCast(b.x1 - b.x0), @intCast(b.y1 - b.y0), 0);
        const c: i64 = trig.cos(p.angle);
        const sn: i64 = trig.sin(p.angle);
        const extent: i64 = @as(i64, @intCast(@abs(c))) + @as(i64, @intCast(@abs(sn))); // |cos| + |sin|, Q16
        const half: i32 = @intCast(@divFloor(@as(i64, bird.CENTRE) * p.scale * extent, @as(i64, tl.ONE) * tl.ONE) + 2);
        const b = Box{ .x0 = @max(0, p.x - half), .y0 = @max(0, p.y - half), .x1 = @min(SW, p.x + half), .y1 = @min(SH, p.y + half) };
        if (b.x0 >= b.x1 or b.y0 >= b.y1) {
            s.last = null;
            return;
        }
        s.last = b;
        const n = fill(s.spans, b, p, c, sn);
        v2.affine(fb, s.tex, s.spans[0..n], .{ .key = 0 });
    }
};

/// The spans of box `b`: screen pixel (x, y) reads texel CENTRE + R(-angle) (x - px, y - py) / scale.
fn fill(spans: []v2.Span, b: Box, p: Pose, c: i64, sn: i64) usize {
    const inv: i64 = @divFloor(@as(i64, 1) << 32, p.scale); // 1 / scale, Q16
    const du: i64 = @divFloor(c * inv, tl.ONE);
    const dv: i64 = @divFloor(-sn * inv, tl.ONE);
    const ru: i64 = @divFloor(sn * inv, tl.ONE); // per row
    const rv: i64 = @divFloor(c * inv, tl.ONE);
    const ox: i64 = b.x0 - p.x;
    var n: usize = 0;
    var y = b.y0;
    while (y < b.y1 and n < spans.len) : (y += 1) {
        const oy: i64 = y - p.y;
        const u = (@as(i64, bird.CENTRE) << 16) + du * ox + ru * oy;
        const v = (@as(i64, bird.CENTRE) << 16) + dv * ox + rv * oy;
        spans[n] = .{ .x0 = @intCast(b.x0), .x1 = @intCast(b.x1), .y = @intCast(y), .u0 = wrap(u), .v0 = wrap(v), .du = wrap(du), .dv = wrap(dv) };
        n += 1;
    }
    return n;
}

fn wrap(v: i64) u32 {
    return @truncate(@as(u64, @bitCast(v)));
}
