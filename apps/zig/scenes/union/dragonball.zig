// --------------------------------------------------------------------------
// Union main-screen DRAGONBALLS (efmain.js "dragonball" object + codef_3d.js).
// 6 bouncing balls along the bottom of P1: each shows a flat-shaded spinning
// 5-point star (5 overlapping copies at 72deg phase offsets, per the JS) over
// a translucent squashing disc. Self-contained: caller must set up P1
// (fullscreen + palette) first — see runner.zig's init for the pattern this
// module deliberately does NOT repeat (no setFullscreen/setPalette here).
//
// Geometry/animation constants faithful to codef_dragonball.js + efmain.js
// (:207-210, :317-324) — see dragonball_math.zig for the vertex/triangle data.
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const ZigOS = zg.ZigOS;
const Color = zg.Color;
const LogicalFB = zg.LogicalFB;
const gm = @import("dragonball_math.zig");

const TWO_PI: f32 = std.math.pi * 2.0;
const BS = gm.BALL_SIZE; // 64
const DISC_R: f32 = 26.0; // codef_dragonball.js mycircle radius 52, halved

const PAL_DISC: u8 = 64; // translucent disc over background
const PAL_FRONT: u8 = 128; // star front (kolor 0xD94345), opaque
const PAL_BACK: u8 = 129; // star back, opaque, dimmer (drawn under the disc)
const PAL_DISC_ON_BACK: u8 = 192; // precomputed disc(a=0.5) over PAL_BACK, opaque

var ball_buf: [BS * BS]u8 = undefined; // module-level scratch (heap-free)

pub const Dragonballs = struct {
    rotx: f32 = 0, // shared star rotation.x (all 5 phases share one accumulator)
    roty: f32 = 0, // shared star rotation.y
    u: f32 = 0, // disc squash phase
    angle: f32 = 0, // bounce phase

    pub fn init(self: *Dragonballs, zigos: *ZigOS) void {
        self.* = .{};
        const p1: *LogicalFB = &zigos.lfbs[1];
        p1.setPaletteEntry(PAL_DISC, Color{ .r = 224, .g = 160, .b = 160, .a = 128 });
        p1.setPaletteEntry(PAL_FRONT, Color{ .r = 217, .g = 67, .b = 69, .a = 255 });
        p1.setPaletteEntry(PAL_BACK, Color{ .r = 160, .g = 50, .b = 52, .a = 255 });
        // disc(224,160,160,a=0.502) over PAL_BACK(160,50,52), pre-blended opaque.
        p1.setPaletteEntry(PAL_DISC_ON_BACK, Color{ .r = 192, .g = 105, .b = 106, .a = 255 });
    }

    pub fn update(self: *Dragonballs) void {
        self.rotx = wrap(self.rotx + 0.01);
        self.roty = wrap(self.roty + 0.06);
        self.u = wrap(self.u + 0.2);
        self.angle = wrap(self.angle + 0.05);
    }

    // @mod(v, 2pi) for a phase that was already in [0, 2pi) and grew by < 2pi:
    // fmod's answer is v - 2pi, exact (Sterbenz), without the fmodf call.
    fn wrap(v: f32) f32 {
        return if (v >= TWO_PI) v - TWO_PI else v;
    }

    pub fn draw(self: *Dragonballs, zigos: *ZigOS) void {
        self.renderBall();
        // Squash the WHOLE ball (stars + disc together) at blit time — matches
        // the original (scale the composited sprite), so star tips never poke
        // outside the disc when it shrinks.
        const sx = 1.0 + @sin(self.u) / 6.0;
        const sy = 1.0 + @sin(self.u + 10.0) / 6.0;
        const p1: *LogicalFB = &zigos.lfbs[1];
        const cols = buildCols(sx);
        var i: usize = 0;
        while (i < 6) : (i += 1) {
            const fi: f32 = @floatFromInt(i);
            const cx = 40.0 + 64.0 * fi;
            const cy = 307.0 - 64.0 * @abs(@sin(self.angle + 0.25 * fi));
            blitBall(p1, cx, cy, sx, sy, &cols);
        }
    }

    // Render one ball (5 overlapping spinning stars + squashed translucent
    // disc) into `ball_buf`. Painter's order: back-facing tris -> disc
    // (composited via precomputed palette entries, see PAL_DISC_ON_BACK) ->
    // front-facing tris on top, matching mycanvasb/mycanvas3d/mycanvas3d2
    // compositing in codef_dragonball.js draw().
    fn renderBall(self: *Dragonballs) void {
        @memset(&ball_buf, 0);

        // One sin/cos pair per angle (rotx for every star, one roty per star),
        // not one per vertex: 12 libm calls a ball instead of 220.
        var proj: [gm.NSTARS][gm.NVERTS]gm.Vec2 = undefined;
        const rx = gm.sincos(self.rotx);
        for (0..gm.NSTARS) |s| {
            const phase: f32 = @as(f32, @floatFromInt(s)) * (TWO_PI / @as(f32, gm.NSTARS));
            const ry = gm.sincos(self.roty + phase);
            for (0..gm.NVERTS) |v| proj[s][v] = gm.project(gm.rotateSC(gm.VERTS[v], rx, ry));
        }

        drawStars(&proj, false); // back-facing first (under the disc)
        drawDisc(); // fixed-size disc; the squash is applied to the whole ball at blit time
        drawStars(&proj, true); // front-facing on top, opaque
    }

    fn drawStars(proj: *const [gm.NSTARS][gm.NVERTS]gm.Vec2, front: bool) void {
        for (0..gm.NSTARS) |s| {
            for (gm.TRIS) |t| {
                const v0 = proj[s][t[0]];
                const v1 = proj[s][t[1]];
                const v2 = proj[s][t[2]];
                const is_front = gm.signedArea(v0, v1, v2) <= 0;
                if (is_front != front) continue;
                gm.fillTriangle(&ball_buf, v0, v1, v2, if (front) PAL_FRONT else PAL_BACK);
            }
        }
    }

    fn drawDisc() void {
        for (DISC, 0..) |span, y| {
            if (span.x1 <= span.x0) continue;
            for (ball_buf[y * BS + span.x0 .. y * BS + span.x1]) |*p| {
                p.* = switch (p.*) {
                    PAL_BACK => PAL_DISC_ON_BACK,
                    0 => PAL_DISC,
                    else => p.*,
                };
            }
        }
    }
};

// The disc never changes size (the squash is applied at blit time), so which
// pixels it covers is a table: per row the run x0..x1 (exclusive) of pixels with
// dx*dx + dy*dy <= 1, from the same f32 expressions drawDisc used to evaluate
// 4096 times a frame. The compile fails if a row's pixels are not one run.
const Span = struct { x0: u8, x1: u8 };
const DISC: [BS]Span = blk: {
    @setEvalBranchQuota(100_000);
    var t: [BS]Span = undefined;
    for (0..BS) |y| {
        const dy = (@as(f32, @floatFromInt(y)) + 0.5 - gm.CENTER) / DISC_R;
        var x0: usize = BS;
        var x1: usize = 0;
        var n: usize = 0;
        for (0..BS) |x| {
            const dx = (@as(f32, @floatFromInt(x)) + 0.5 - gm.CENTER) / DISC_R;
            if (dx * dx + dy * dy > 1.0) continue;
            if (n == 0) x0 = x;
            x1 = x + 1;
            n += 1;
        }
        if (n != 0 and x1 - x0 != n) @compileError("dragonball disc row is not one run");
        t[y] = .{ .x0 = if (n == 0) 0 else x0, .x1 = if (n == 0) 0 else x1 };
    }
    break :blk t;
};

// Blit the BSxBS ball sprite centred at (cx,cy), scaled by (sx,sy) about its
// centre (the squash), onto `fb`, clipped to bounds; index 0 is transparent.
// Inverse-mapped (iterate dest, sample source) so there are no gaps.
fn blitBall(fb: *LogicalFB, cx: f32, cy: f32, sx: f32, sy: f32, cols: *const [COLS]i8) void {
    const pw: i32 = @intCast(fb.fb_w);
    const cxi: i32 = @intFromFloat(cx); // 40 + 64 i: a whole number, so px - cxi is exact
    const ph: i32 = @intCast(fb.fb_h);
    const hw_ = gm.CENTER * sx; // scaled half-width
    const hh_ = gm.CENTER * sy;
    const px0: i32 = @intFromFloat(@floor(cx - hw_));
    const px1: i32 = @intFromFloat(@ceil(cx + hw_));
    const py0: i32 = @intFromFloat(@floor(cy - hh_));
    const py1: i32 = @intFromFloat(@ceil(cy + hh_));
    var py: i32 = py0;
    while (py < py1) : (py += 1) {
        if (py < 0 or py >= ph) continue;
        const svy = gm.CENTER + (@as(f32, @floatFromInt(py)) + 0.5 - cy) / sy;
        if (svy < 0 or svy >= @as(f32, BS)) continue;
        const srow = @as(usize, @intFromFloat(svy)) * BS;
        const drow = @as(usize, @intCast(py)) * fb.stride;
        var px: i32 = @max(px0, 0);
        const pend = @min(px1, pw);
        while (px < pend) : (px += 1) {
            const col = cols[@intCast(px - cxi + COL_OFF)];
            if (col < 0) continue;
            const idx = ball_buf[srow + @as(usize, @intCast(col))];
            if (idx == 0) continue;
            fb.fb[drow + @as(usize, @intCast(px))] = idx;
        }
    }
}

// Source column for destination column cx + d: the same
// BALL_CENTER + (d + 0.5) / sx the per-pixel loop divided out for every pixel of
// every ball (d + 0.5 is exactly px + 0.5 - cx). The squash is one sx for all
// six balls, so one table a frame replaces ~19,000 divides. -1: outside the sprite.
const COLS = 96;
const COL_OFF = 48; // a squashed ball spans d in [-38, 38)
fn buildCols(sx: f32) [COLS]i8 {
    var t: [COLS]i8 = undefined;
    for (&t, 0..) |*c, i| {
        const d: f32 = @floatFromInt(@as(i32, @intCast(i)) - COL_OFF);
        const svx = gm.CENTER + (d + 0.5) / sx;
        c.* = if (svx < 0 or svx >= @as(f32, BS)) -1 else @intCast(@as(usize, @intFromFloat(svx)));
    }
    return t;
}
