// --------------------------------------------------------------------------
// Union intro — WAB logo part: eflogowabentry.js, then eflogowab.js's fade. The
// logo is cut into 33x33 canvas tiles; each flies from a random point of the WHOLE
// 768x540 canvas to its place, turning 720 degrees and fading in, all landing on
// vbl 110 (codef_animatedtiles.js). Canvas -> plane is the intro's canvas/2 + (8,5)
// on a 400x280 overscan plane (placement.zig), so pieces starting in the border
// area are seen there. eflogowab5.png is composited over black and box-halved to
// 132x132 (tools/private_tools/union_wab_assets.py). Where the port differs from
// the browser: nearest sampling where the canvas filters the turning tiles; the
// piece's globalAlpha is one of 32 shade levels (wab_shade.dat); a piece over
// another replaces it rather than blending; Math.random is a seeded mulberry32.
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const ZigOS = zg.ZigOS;
const Color = zg.Color;
const LogicalFB = zg.LogicalFB;

const CANVAS_W: f64 = 768; // index.html:58 sequencer_InitAndStart(768, 540, ...)
const CANVAS_H: f64 = 540;
const IMAGE: f64 = 264; // eflogowab5.png
const TILE: f64 = 33; // eflogowabentry.js:31
const HALF_TILE: f64 = TILE / 2; // setmidhandle: drawPart translates by -partw/2
const GRID: usize = 8;
const NT: usize = GRID * GRID;
const ENDVBL: u32 = 110; // eflogowabentry.js:53, generateTilesHelper's aSpeed
const STAGGER: f64 = 40; // startvbl = Math.ceil(40*Math.random())
const TURNS_DEG: f64 = 360 * 2; // rotangle += (360*2)/speed per move
// index.html:39-41 run while startFrame <= f < endFrame (sequencer.js:120): the
// entry renders 600..748, 749 holds; the fade renders 750..948, 949 holds.
const ENTRY_FRAMES: u32 = 750 - 600;
const FADE_RENDERS: u32 = 949 - 750;
const FADE_FRAMES: u32 = 950 - 750;
const ALPHA_INCR: f64 = 0.005; // eflogowab.js:138

const PLANE_W: i32 = @intCast(zg.PHYSICAL_WIDTH);
const PLANE_H: i32 = @intCast(zg.PHYSICAL_HEIGHT);
const ORIGIN_X: f64 = 8; // canvas (0,0) on the plane, as placement.zig
const ORIGIN_Y: f64 = 5;
const LOGO: usize = 132; // wab.raw is 132x132
const LOGO_F: f64 = LOGO;
const LOGO_X: i16 = @intFromFloat((CANVAS_W - IMAGE) / 2 / 2 + ORIGIN_X); // 134
const LOGO_Y: i16 = @intFromFloat((CANVAS_H - IMAGE) / 2 / 2 + ORIGIN_Y); // 74
const LEVELS: f64 = 32; // wab_shade.dat rows + the untouched level
// A rotated tile reaches half its diagonal from its centre, plus the edge pixel.
const REACH: f64 = HALF_TILE * std.math.sqrt2 + 1;
const SEED: u32 = 0x77ab5;

const wab_raw = @embedFile("../../assets/screens/union_intro/wab.raw");
const wab_pal = zg.convertU8ArraytoColors(@embedFile("../../assets/screens/union_intro/wab_pal.dat"));
const wab_shade = @embedFile("../../assets/screens/union_intro/wab_shade.dat");
const wab_tiles = @embedFile("../../assets/screens/union_intro/wab_tiles.dat");
const BG = Color{ .r = 0, .g = 0, .b = 0, .a = 255 };

const Phase = enum { entry, fade };

/// mulberry32: a Math.random stand-in the harness can replay bit for bit.
const Random = struct {
    state: u32,
    fn next(self: *Random) f64 {
        self.state +%= 0x6D2B79F5;
        var t = (self.state ^ (self.state >> 15)) *% (self.state | 1);
        t = (t +% ((t ^ (t >> 7)) *% (t | 61))) ^ t;
        return @as(f64, @floatFromInt(t ^ (t >> 14))) / 4294967296.0;
    }
};

const Tile = struct { start_x: f64, start_y: f64, startvbl: u32 };

// union_intro.zig starts a part as `.{}`, hence the defaults; init() assigns all.
pub const Part = struct {
    blitter: zg.Blitter = .{},
    phase: Phase = .entry,
    frame: u32 = 0, // frames into the current phase
    alpha: f64 = 1, // eflogowab's this.alpha and this.alphaIncr
    alpha_incr: f64 = ALPHA_INCR,
    tiles: [NT]Tile = undefined,

    pub fn init(self: *Part, zigos: *ZigOS) void {
        self.blitter = .{};
        self.blitter.init();
        self.phase = .entry;
        self.frame = 0;
        self.alpha = 1;
        self.alpha_incr = ALPHA_INCR;
        // generateTilesHelper: only tiles with some alpha get an animatedTile, and
        // each draws startvbl, then currX, then currY (argument order, then init).
        var rng = Random{ .state = SEED };
        for (&self.tiles, 0..) |*t, i| {
            t.* = .{ .start_x = 0, .start_y = 0, .startvbl = 0 };
            if (wab_tiles[i] == 0) continue;
            t.startvbl = @intFromFloat(@ceil(STAGGER * rng.next()));
            t.start_x = CANVAS_W * rng.next();
            t.start_y = CANVAS_H * rng.next();
        }
        zigos.setBackgroundColor(BG);
        const p0: *LogicalFB = &zigos.lfbs[0];
        p0.is_enabled = true;
        p0.openBorders(.all);
        p0.setPalette(wab_pal);
        p0.setPaletteEntry(0, BG);
    }

    pub fn update(self: *Part, zigos: *ZigOS, dt: f32) bool {
        _ = dt;
        switch (self.phase) {
            .entry => {
                self.frame += 1;
                if (self.frame < ENTRY_FRAMES) return false;
                self.phase = .fade; // this frame is the fade's first, at alpha 1
                self.frame = 0;
            },
            .fade => {
                self.frame += 1;
                if (self.frame == FADE_FRAMES) return true;
                if (self.frame < FADE_RENDERS) self.stepAlpha(); // else hold, as frame 949
                // A globalAlpha above 1 is ignored, which leaves the canvas at 1: the clamp.
                zg.palette.scaleRange(&zigos.lfbs[0], wab_pal, 1, 255, self.alpha, .{ .alpha = .{ .set = 255 } });
            },
        }
        return false;
    }

    /// eflogowab.js:186-188, after each render: 1, 1.005, 1, 0.995 ... 0.02.
    fn stepAlpha(self: *Part) void {
        self.alpha += self.alpha_incr;
        if (self.alpha > 0.99) self.alpha_incr = -ALPHA_INCR;
        if (self.alpha < 0.001) self.alpha = 0.001;
    }

    pub fn render(self: *Part, zigos: *ZigOS, dt: f32) void {
        _ = dt;
        const p0: *LogicalFB = &zigos.lfbs[0];
        p0.clearFrameBuffer(0);
        switch (self.phase) {
            .entry => for (0..NT) |i| self.drawTile(p0, i),
            .fade => self.blitter.blitImage(p0, LOGO_X, LOGO_Y, wab_raw, LOGO, 0, 0, LOGO, LOGO, 0),
        }
    }

    /// animatedTile.draw on this.frame's render, after its advance().
    fn drawTile(self: *const Part, fb: *LogicalFB, i: usize) void {
        const t = self.tiles[i];
        if (wab_tiles[i] == 0 or self.frame < t.startvbl) return; // draws once vbl > startvbl
        const speed: f64 = @floatFromInt(ENDVBL - t.startvbl);
        const moves: f64 = @floatFromInt(@min(self.frame - t.startvbl, ENDVBL - t.startvbl));
        // globalAlpha = (vbl-startvbl)/(endvbl-startvbl); above 1 the canvas ignores it.
        const alpha = @min(1.0, @as(f64, @floatFromInt(self.frame + 1 - t.startvbl)) / speed);
        const level: usize = @intFromFloat(@round(alpha * LEVELS));
        if (level == 0) return;

        const tx: f64 = @floatFromInt(i % GRID);
        const ty: f64 = @floatFromInt(i / GRID);
        const final_x = tx * TILE + (CANVAS_W - IMAGE) / 2;
        const final_y = ty * TILE + (CANVAS_H - IMAGE) / 2;
        // At rest the tile sits at its place, unturned (720 degrees): the identity, exactly.
        const flying = moves < speed;
        const x = if (flying) t.start_x + (final_x - t.start_x) / speed * moves else final_x;
        const y = if (flying) t.start_y + (final_y - t.start_y) / speed * moves else final_y;
        const rad = if (flying) TURNS_DEG / speed * moves * std.math.pi / 180.0 else 0;
        blitTurned(fb, tx, ty, x + HALF_TILE, y + HALF_TILE, @cos(rad), @sin(rad), level);
    }
};

/// Tile (tx,ty) centred on canvas (cx,cy), turned by (cs,sn), in halved logo texels.
fn blitTurned(fb: *LogicalFB, tx: f64, ty: f64, cx: f64, cy: f64, cs: f64, sn: f64, level: usize) void {
    const x0 = planeSpan(cx - REACH, ORIGIN_X, PLANE_W, false);
    const x1 = planeSpan(cx + REACH, ORIGIN_X, PLANE_W, true);
    const y0 = planeSpan(cy - REACH, ORIGIN_Y, PLANE_H, false);
    const y1 = planeSpan(cy + REACH, ORIGIN_Y, PLANE_H, true);
    const shade = if (level < LEVELS) wab_shade[(level - 1) * 256 ..][0..256] else null;
    var py = y0;
    while (py < y1) : (py += 1) {
        const qy = 2 * (@as(f64, @floatFromInt(py)) - ORIGIN_Y) + 1 - cy;
        const row = @as(usize, @intCast(py)) * @as(usize, fb.stride);
        var px = x0;
        while (px < x1) : (px += 1) {
            const qx = 2 * (@as(f64, @floatFromInt(px)) - ORIGIN_X) + 1 - cx;
            const u = cs * qx + sn * qy + HALF_TILE;
            const v = -sn * qx + cs * qy + HALF_TILE;
            // Drawn when the pixel's 2x2 canvas box overlaps the tile: a texel split by
            // an odd tile edge belongs to BOTH tiles, or an empty (never animated)
            // neighbour would leave a hole in the assembled logo.
            if (u <= -1 or u >= TILE + 1 or v <= -1 or v >= TILE + 1) continue;
            const sx = @floor((tx * TILE + u) / 2);
            const sy = @floor((ty * TILE + v) / 2);
            if (sx < 0 or sx >= LOGO_F or sy < 0 or sy >= LOGO_F) continue;
            const idx = wab_raw[@as(usize, @intFromFloat(sy)) * LOGO + @as(usize, @intFromFloat(sx))];
            if (idx == 0) continue;
            fb.fb[row + @as(usize, @intCast(px))] = if (shade) |s| s[idx] else idx;
        }
    }
}

/// First (or one past the last) plane coordinate whose pixel can reach canvas `c`.
fn planeSpan(c: f64, origin: f64, limit: i32, end: bool) i32 {
    const p = (c - 1) / 2 + origin;
    const v: i32 = @intFromFloat(if (end) @floor(p) + 2 else @floor(p));
    return std.math.clamp(v, 0, limit);
}
