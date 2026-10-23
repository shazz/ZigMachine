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
// The flight (wab_table.zig) and the fade (wab_fade.zig) are precomputed at
// compile time from the port's own f64 maths, so a frame runs no float: it walks
// that frame's entries and draws each with wab_turn.zig.
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const ZigOS = zg.ZigOS;
const Color = zg.Color;
const LogicalFB = zg.LogicalFB;

const wt = @import("wab_table.zig");
const turn = @import("wab_turn.zig");
const fade = @import("wab_fade.zig");
// index.html:39-41 run while startFrame <= f < endFrame (sequencer.js:120): the
// entry renders 600..748, 749 holds; the fade renders 750..948, 949 holds.
const ENTRY_FRAMES: u32 = 750 - 600;
const FADE_FRAMES: u32 = 950 - 750;

const LOGO: usize = turn.LOGO;
const LOGO_X: i16 = (768 - 264) / 2 / 2 + 8; // 134: (CANVAS_W - IMAGE) / 2 / 2 + ORIGIN_X
const LOGO_Y: i16 = (540 - 264) / 2 / 2 + 5; // 74
const LEVELS: usize = 32; // wab_shade.dat rows + the untouched level

const wab_raw = @embedFile("../../assets/screens/union_intro/wab.raw");
const wab_pal = zg.convertU8ArraytoColors(@embedFile("../../assets/screens/union_intro/wab_pal.dat"));
const wab_shade = @embedFile("../../assets/screens/union_intro/wab_shade.dat");
const BG = Color{ .r = 0, .g = 0, .b = 0, .a = 255 };

comptime { // the table was built for this tile mask and this plane
    const tiles = @embedFile("../../assets/screens/union_intro/wab_tiles.dat");
    for (wt.MASK, 0..) |m, i| std.debug.assert(m == @intFromBool(tiles[i] != 0));
    std.debug.assert(zg.PHYSICAL_WIDTH == 400 and zg.PHYSICAL_HEIGHT == 280);
}

const Phase = enum { entry, fade };
/// Plane 0's picture: the last part's, the whole logo, or entry frame n's tiles.
const Shown = union(enum) { other, logo, flight: u32 };

/// Plane pixels [x0, x1) x [y0, y1).
const Rect = struct {
    x0: i16,
    y0: i16,
    x1: i16,
    y1: i16,

    fn of(e: wt.Entry) Rect {
        return .{ .x0 = e.x0, .y0 = e.y0, .x1 = e.x0 + e.w, .y1 = e.y0 + e.h };
    }

    fn join(a: Rect, b: Rect) Rect {
        return .{ .x0 = @min(a.x0, b.x0), .y0 = @min(a.y0, b.y0), .x1 = @max(a.x1, b.x1), .y1 = @max(a.y1, b.y1) };
    }

    fn area(r: Rect) usize {
        return @as(usize, @intCast(r.x1 - r.x0)) * @as(usize, @intCast(r.y1 - r.y0));
    }

    fn fill(r: Rect, bl: *zg.Blitter, p0: *LogicalFB) void {
        bl.fill(p0, r.x0, r.y0, @intCast(r.x1 - r.x0), @intCast(r.y1 - r.y0), 0);
    }
};

// union_intro.zig starts a part as `.{}`, hence the defaults; init() assigns all.
pub const Part = struct {
    blitter: zg.Blitter = .{},
    phase: Phase = .entry,
    frame: u32 = 0, // frames into the current phase
    fade_k: u32 = fade.NONE, // the scale the palette holds (wab_fade.zig)
    shown: Shown = .other, // what plane 0 holds (only what changes is redrawn)

    pub fn init(self: *Part, zigos: *ZigOS) void {
        self.blitter = .{};
        self.blitter.init();
        self.phase = .entry;
        self.frame = 0;
        self.fade_k = fade.NONE;
        self.shown = .other;
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
                self.fade_k = fade.apply(&zigos.lfbs[0], self.fade_k, fade.K[self.frame]);
            },
        }
        return false;
    }

    pub fn render(self: *Part, zigos: *ZigOS, dt: f32) void {
        _ = dt;
        const p0: *LogicalFB = &zigos.lfbs[0];
        // From ENDVBL every tile is at rest, unturned, at full alpha: the whole logo,
        // exactly (apps/union_intro_wab_check.mjs proves those frames are wab.raw).
        // It is drawn ONCE; the fade after it only scales the palette.
        if (self.phase == .fade or self.frame >= wt.ENDVBL) {
            if (self.shown == .logo) return;
            self.erase(p0);
            self.blitter.blitImage(p0, LOGO_X, LOGO_Y, wab_raw, LOGO, 0, 0, LOGO, LOGO, 0);
            self.shown = .logo;
            return;
        }
        self.erase(p0);
        // animatedTile.draw for every tile on this frame's render, in tile order.
        for (wt.ENTRIES[wt.FIRST[self.frame]..wt.FIRST[self.frame + 1]]) |e| {
            const shade = if (e.level < LEVELS) wab_shade[(@as(usize, e.level) - 1) * 256 ..][0..256] else null;
            turn.blit(p0.fb, p0.stride, e, wab_raw, shade);
        }
        self.shown = .{ .flight = self.frame };
    }

    /// Back to black only where the plane is not: under the tiles of the frame it
    /// shows (each tile's span, or their bounding box when that is fewer blitter
    /// clocks), or all of it when it holds another part's picture. A CHISEL fill.
    fn erase(self: *Part, p0: *LogicalFB) void {
        const f = switch (self.shown) {
            .other, .logo => return self.blitter.clear(p0, 0),
            .flight => |f| f,
        };
        const tiles = wt.ENTRIES[wt.FIRST[f]..wt.FIRST[f + 1]];
        if (tiles.len == 0) return;
        var box = Rect.of(tiles[0]);
        var area: usize = 0;
        for (tiles) |e| {
            box = box.join(Rect.of(e));
            area += @as(usize, e.w) * e.h;
        }
        // a fill costs ~BLIT_CALL clocks to start, then ~1.85 a pixel (cost_model.mjs)
        if (box.area() * 185 + 18_000 <= area * 185 + tiles.len * 18_000) return box.fill(&self.blitter, p0);
        for (tiles) |e| Rect.of(e).fill(&self.blitter, p0);
    }
};
