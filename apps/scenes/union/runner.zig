// --------------------------------------------------------------------------
// Union main — the running character (efmain.js sprite). 7 frames of 32x28 on
// plane 1 (actors), fixed on screen while the world scrolls under it, with a
// 4-copy palette-dimmed ghost trail. Faithful to efmain.js: pinpinNb += 0.6,
// wraps >7 (drawn frame = floor) → a 12-frame cycle; ghosts at x-1/-2/-4/-5
// with alpha 0.7/0.5/0.3/0.1.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const ZigOS = zg.ZigOS;
const Color = zg.Color;
const LogicalFB = zg.LogicalFB;
const convertU8ArraytoColors = zg.convertU8ArraytoColors;

const SW: usize = 224; // sprite sheet width
const FW: i16 = 32; // frame w
const FH: i16 = 28; // frame h
const X0: i16 = 200; // fixed top-left on the fullscreen plane (centre 216,133)
const Y0: i16 = 119;

const sprites = @embedFile("../../assets/screens/union_main/sprites.raw");
const p1_pal = convertU8ArraytoColors(@embedFile("../../assets/screens/union_main/p1.pal"));

const CENTER_X: f32 = 216; // X0 + FW/2 (the runner is drawn centred here)
// Trailing ghost copies: progressively further left and MORE x-zoomed than the
// literal efmain.js values (which, under an opaque main, barely showed) so the
// speed streak reads clearly. Centre offset + horizontal zoom + alpha per copy.
const GHOST_CX = [4]f32{ -4, -10, -17, -25 };
const GHOST_Z = [4]f32{ 1.5, 2.0, 2.5, 3.0 };
const GHOST_A = [4]u8{ 179, 128, 77, 26 }; // 0.7/0.5/0.3/0.1
const GHOST_BASE: u8 = 16; // ghost g uses palette [GHOST_BASE + g*8 + idx]

pub const Runner = struct {
    nb: f32 = 0,

    pub fn init(self: *Runner, zigos: *ZigOS) void {
        self.nb = 0;
        const p1: *LogicalFB = &zigos.lfbs[1];
        p1.is_enabled = true;
        p1.setFullscreen();
        p1.setPalette(p1_pal);
        p1.setPaletteEntry(0, Color{ .r = 0, .g = 0, .b = 0, .a = 0 }); // transparent
        // Dimmed/alpha copies of the 7 sprite colours for the ghost trail.
        for (0..4) |g| {
            const base: u8 = GHOST_BASE + @as(u8, @intCast(g)) * 8;
            var c: u8 = 1;
            while (c < 8) : (c += 1) {
                const col = p1_pal[c];
                p1.setPaletteEntry(base + c, Color{ .r = col.r, .g = col.g, .b = col.b, .a = GHOST_A[g] });
            }
        }
    }

    pub fn update(self: *Runner) void {
        self.nb += 0.6;
        if (self.nb > 7) self.nb = 0;
    }

    pub fn draw(self: *Runner, zigos: *ZigOS) void {
        const p1: *LogicalFB = &zigos.lfbs[1];
        p1.clearFrameBuffer(0);
        const f: usize = @intFromFloat(self.nb);
        // Ghosts outermost (dimmest) first — each horizontally x-zoomed about its
        // centre for the speed streak — then the opaque runner on top.
        var g: usize = 4;
        while (g > 0) {
            g -= 1;
            blitStretch(p1, f, CENTER_X + GHOST_CX[g], Y0, GHOST_Z[g], GHOST_BASE + @as(u8, @intCast(g)) * 8);
        }
        blitFrame(p1, f, X0, Y0, 0);
    }
};

// Blit sprite frame `f` centred at x=cx, stretched horizontally by `z` (the
// ghost speed-streak); non-zero pixel idx -> palette (base + idx).
fn blitStretch(fb: *LogicalFB, f: usize, cx: f32, y: i16, z: f32, base: u8) void {
    const pw: i16 = @intCast(fb.fb_w);
    const ph: i16 = @intCast(fb.fb_h);
    const scaled: f32 = @as(f32, @floatFromInt(FW)) * z;
    const x0: i16 = @intFromFloat(cx - scaled * 0.5);
    const cols: i16 = @intFromFloat(@ceil(scaled));
    const sx0: usize = f * @as(usize, @intCast(FW));
    var dc: i16 = 0;
    while (dc < cols) : (dc += 1) {
        const src: usize = @intFromFloat(@as(f32, @floatFromInt(dc)) / z);
        if (src >= @as(usize, @intCast(FW))) break;
        const px = x0 + dc;
        if (px < 0 or px >= pw) continue;
        var ry: i16 = 0;
        while (ry < FH) : (ry += 1) {
            const py = y + ry;
            if (py < 0 or py >= ph) continue;
            const idx = sprites[@as(usize, @intCast(ry)) * SW + sx0 + src];
            if (idx == 0) continue;
            fb.fb[@as(usize, @intCast(py)) * fb.stride + @as(usize, @intCast(px))] = base + idx;
        }
    }
}

// Blit sprite frame `f` at (x,y); non-zero pixel idx -> palette (base + idx).
fn blitFrame(fb: *LogicalFB, f: usize, x: i16, y: i16, base: u8) void {
    const pw: i16 = @intCast(fb.fb_w);
    const ph: i16 = @intCast(fb.fb_h);
    const sx0: usize = f * @as(usize, @intCast(FW));
    var ry: i16 = 0;
    while (ry < FH) : (ry += 1) {
        const py = y + ry;
        if (py < 0 or py >= ph) continue;
        const srow = @as(usize, @intCast(ry)) * SW + sx0;
        const drow = @as(usize, @intCast(py)) * fb.stride;
        var rx: i16 = 0;
        while (rx < FW) : (rx += 1) {
            const px = x + rx;
            if (px < 0 or px >= pw) continue;
            const idx = sprites[srow + @as(usize, @intCast(rx))];
            if (idx == 0) continue;
            fb.fb[drow + @as(usize, @intCast(px))] = base + idx;
        }
    }
}
