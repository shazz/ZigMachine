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
        self.rotx = @mod(self.rotx + 0.01, TWO_PI);
        self.roty = @mod(self.roty + 0.06, TWO_PI);
        self.u = @mod(self.u + 0.2, TWO_PI);
        self.angle = @mod(self.angle + 0.05, TWO_PI);
    }

    pub fn draw(self: *Dragonballs, zigos: *ZigOS) void {
        self.renderBall();
        // Squash the WHOLE ball (stars + disc together) at blit time — matches
        // the original (scale the composited sprite), so star tips never poke
        // outside the disc when it shrinks.
        const sx = 1.0 + @sin(self.u) / 6.0;
        const sy = 1.0 + @sin(self.u + 10.0) / 6.0;
        const p1: *LogicalFB = &zigos.lfbs[1];
        var i: usize = 0;
        while (i < 6) : (i += 1) {
            const fi: f32 = @floatFromInt(i);
            const cx = 40.0 + 64.0 * fi;
            const cy = 307.0 - 64.0 * @abs(@sin(self.angle + 0.25 * fi));
            blitBall(p1, cx, cy, sx, sy);
        }
    }

    // Render one ball (5 overlapping spinning stars + squashed translucent
    // disc) into `ball_buf`. Painter's order: back-facing tris -> disc
    // (composited via precomputed palette entries, see PAL_DISC_ON_BACK) ->
    // front-facing tris on top, matching mycanvasb/mycanvas3d/mycanvas3d2
    // compositing in codef_dragonball.js draw().
    fn renderBall(self: *Dragonballs) void {
        @memset(&ball_buf, 0);

        var proj: [gm.NSTARS][gm.NVERTS]gm.Vec2 = undefined;
        for (0..gm.NSTARS) |s| {
            const phase: f32 = @as(f32, @floatFromInt(s)) * (TWO_PI / @as(f32, gm.NSTARS));
            const ay = self.roty + phase;
            for (0..gm.NVERTS) |v| proj[s][v] = gm.project(gm.rotate(gm.VERTS[v], self.rotx, ay));
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
        var y: usize = 0;
        while (y < BS) : (y += 1) {
            const dy = (@as(f32, @floatFromInt(y)) + 0.5 - gm.CENTER) / DISC_R;
            var x: usize = 0;
            while (x < BS) : (x += 1) {
                const dx = (@as(f32, @floatFromInt(x)) + 0.5 - gm.CENTER) / DISC_R;
                if (dx * dx + dy * dy > 1.0) continue;
                const idx = y * BS + x;
                ball_buf[idx] = switch (ball_buf[idx]) {
                    PAL_BACK => PAL_DISC_ON_BACK,
                    0 => PAL_DISC,
                    else => ball_buf[idx],
                };
            }
        }
    }
};

// Blit the BSxBS ball sprite centred at (cx,cy), scaled by (sx,sy) about its
// centre (the squash), onto `fb`, clipped to bounds; index 0 is transparent.
// Inverse-mapped (iterate dest, sample source) so there are no gaps.
fn blitBall(fb: *LogicalFB, cx: f32, cy: f32, sx: f32, sy: f32) void {
    const pw: i32 = @intCast(fb.fb_w);
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
        var px: i32 = px0;
        while (px < px1) : (px += 1) {
            if (px < 0 or px >= pw) continue;
            const svx = gm.CENTER + (@as(f32, @floatFromInt(px)) + 0.5 - cx) / sx;
            if (svx < 0 or svx >= @as(f32, BS)) continue;
            const idx = ball_buf[srow + @as(usize, @intFromFloat(svx))];
            if (idx == 0) continue;
            fb.fb[drow + @as(usize, @intCast(px))] = idx;
        }
    }
}
