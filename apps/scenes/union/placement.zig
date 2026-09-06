// --------------------------------------------------------------------------
// Union intro — efmain_intro "placement" animation: the 17 back_layer strips
// (sky bands, world, floor, ground, fade-in clouds, running-character sheet)
// fly/slide/fade in from off-screen to assemble the main-screen image, port
// of assets/oldies/UnionDemoCracktro/intro/efmain_intro.js (this.render).
//
// Physics table + embedded strips live in placement_strips.zig. Runs on
// fullscreen plane 0, one shared indexed palette (placement.pal); raw bytes
// ARE final palette indices (no per-strip base offset needed).
// --------------------------------------------------------------------------
const zg = @import("zigos");
const ZigOS = zg.ZigOS;
const Color = zg.Color;
const LogicalFB = zg.LogicalFB;
const convertU8ArraytoColors = zg.convertU8ArraytoColors;

const strips = @import("placement_strips.zig");
const STRIPS = strips.STRIPS;
const N: usize = STRIPS.len;

// FADE alpha reaches 1.0 at (1.0-0.001)/0.005 ~ 200 frames; the runner
// (the slowest SCROLL/ANIM strip) arrives at ~198 — 200 covers both.
const NFRAMES: u32 = 200;
const ORIGIN_X: i32 = 8;
const ORIGIN_Y: i32 = 5;
const FADE_STEP: f32 = 0.005;

// Runner sheet: 224x28 half-scale = 7 frames of 32x28. spriteNb advances
// 0.08 per LAYER in the JS (17 layers/frame => ~1.36/frame); we track it
// once per frame here, which is the "simple slow frame advance" the task
// allows in place of the exact per-layer accumulation.
const RUNNER_FW: usize = 32;
const RUNNER_FH: usize = 28;
const RUNNER_FRAMES: f32 = 7.0;
const RUNNER_STEP: f32 = 17.0 * 0.08;

const placement_pal = convertU8ArraytoColors(@embedFile("../../assets/screens/union_intro/placement/placement.pal"));
const BG = Color{ .r = 0, .g = 0, .b = 0, .a = 255 };

pub const Placement = struct {
    pos_x: [N]f32 = undefined,
    pos_y: [N]f32 = undefined,
    alpha: [N]f32 = undefined,
    frame: u32 = 0,
    sprite_nb: f32 = 0,

    pub fn init(self: *Placement, zigos: *ZigOS) void {
        self.frame = 0;
        self.sprite_nb = 0;
        for (STRIPS, 0..) |s, i| {
            self.pos_x[i] = s.ox;
            self.pos_y[i] = s.oy;
            self.alpha[i] = s.alpha0;
        }
        zigos.setBackgroundColor(BG);
        const p0: *LogicalFB = &zigos.lfbs[0];
        p0.is_enabled = true;
        p0.setFullscreen();
        p0.setPalette(placement_pal);
        p0.clearFrameBuffer(0);
    }

    // NOTE: takes (zigos, dt) — unused here — to match the Part call convention
    // used by trsi.zig/wab.zig (union_intro.zig's SEQ dispatches through a
    // tagged union with `inline else => |*p| p.update(zigos, dt)`, so every
    // Part in the sequence must share one signature). See placement.zig's
    // top-of-file comment / the integration report for the exact snippet.
    pub fn update(self: *Placement, zigos: *ZigOS, dt: f32) bool {
        _ = zigos;
        _ = dt;
        for (STRIPS, 0..) |s, i| {
            switch (s.kind) {
                .fade => {
                    self.alpha[i] = @min(1.0, self.alpha[i] + FADE_STEP);
                },
                .scroll, .anim => {
                    const dirx_f: f32 = @floatFromInt(s.dirx);
                    const diry_f: f32 = @floatFromInt(s.diry);
                    self.pos_x[i] = clampAxis(self.pos_x[i] + dirx_f * s.sx, s.dx, s.dirx);
                    self.pos_y[i] = clampAxis(self.pos_y[i] + diry_f * s.sy, s.dy, s.diry);
                },
            }
        }
        self.sprite_nb += RUNNER_STEP;
        if (self.sprite_nb >= RUNNER_FRAMES) self.sprite_nb = 0;
        self.frame += 1;
        return self.frame >= NFRAMES;
    }

    pub fn render(self: *Placement, zigos: *ZigOS, dt: f32) void {
        _ = dt;
        const p0: *LogicalFB = &zigos.lfbs[0];
        p0.clearFrameBuffer(0);
        for (STRIPS, 0..) |s, i| {
            if (s.kind == .fade) applyFade(p0, s, self.alpha[i]);
            const dx = ORIGIN_X + @as(i32, @intFromFloat(@round(self.pos_x[i])));
            const dy = ORIGIN_Y + @as(i32, @intFromFloat(@round(self.pos_y[i])));
            if (s.kind == .anim) {
                const f: usize = @intFromFloat(self.sprite_nb);
                blitRect(p0, s.raw, s.w, f * RUNNER_FW, 0, RUNNER_FW, RUNNER_FH, dx, dy);
            } else {
                blitRect(p0, s.raw, s.w, 0, 0, s.w, s.h, dx, dy);
            }
        }
    }
};

fn clampAxis(pos: f32, dest: f32, dir: i8) f32 {
    if (dir == 1 and pos >= dest) return dest;
    if (dir == -1 and pos <= dest) return dest;
    return pos;
}

// Fade-in: scale this strip's OWN palette range (non-overlapping with every
// other strip — see tools/union_intro_assets.py) from the original color by
// the current alpha, each frame, from the base placement_pal (never from an
// already-scaled value, or the fade would compound).
fn applyFade(fb: *LogicalFB, s: strips.StripDef, alpha: f32) void {
    if (alpha >= 1.0) return;
    var idx: usize = s.lo;
    while (idx <= s.hi) : (idx += 1) {
        const c = placement_pal[idx];
        fb.setPaletteEntry(@intCast(idx), Color{
            .r = @intFromFloat(@as(f32, @floatFromInt(c.r)) * alpha),
            .g = @intFromFloat(@as(f32, @floatFromInt(c.g)) * alpha),
            .b = @intFromFloat(@as(f32, @floatFromInt(c.b)) * alpha),
            .a = 255,
        });
    }
}

// Blit an src_w-strided sub-rectangle (src_x,src_y,w,h) of `raw` to (dx,dy) on
// `fb`, clipped to the framebuffer; raw bytes are final palette indices
// (index 0 = transparent, skipped).
fn blitRect(fb: *LogicalFB, raw: []const u8, src_w: usize, src_x: usize, src_y: usize, w: usize, h: usize, dx: i32, dy: i32) void {
    const pw: i32 = @intCast(fb.fb_w);
    const ph: i32 = @intCast(fb.fb_h);
    var ry: usize = 0;
    while (ry < h) : (ry += 1) {
        const py = dy + @as(i32, @intCast(ry));
        if (py < 0 or py >= ph) continue;
        const srow = (src_y + ry) * src_w + src_x;
        const drow = @as(usize, @intCast(py)) * fb.stride;
        var rx: usize = 0;
        while (rx < w) : (rx += 1) {
            const px = dx + @as(i32, @intCast(rx));
            if (px < 0 or px >= pw) continue;
            const idx = raw[srow + rx];
            if (idx == 0) continue;
            fb.fb[drow + @as(usize, @intCast(px))] = idx;
        }
    }
}
