// --------------------------------------------------------------------------
// Blitter demo — the seven drawing modes. Every pixel goes through `gfx`
// (fill / triangle / bob / copy), so the same code draws on CHISEL or on ZIGGY.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const ZigOS = zg.ZigOS;
const LogicalFB = zg.LogicalFB;
const geom = @import("geom.zig");
const Cube = geom.Cube;
const gfx = @import("gfx.zig");
pub const Gfx = gfx.Gfx;
const Wobble = @import("wobble.zig").Wobble;

const WIDTH: i32 = zg.WIDTH;
const HEIGHT: i32 = zg.HEIGHT;

// TILE: render the cube once into a TILE_W×TILE_H corner of a scratch plane, then
// block-copy that tile across a GRID_X×GRID_Y grid — the whole screen for the
// cost of copies, one rasterisation.
const TILE_W: u16 = 74;
const TILE_H: u16 = 60;
const GRID_X: u16 = 10; // overlapping grid (step < tile) so tile COUNT drives the
const GRID_Y: u16 = 8; //  pixels-copied cost — watch the FPS readout vs the count
const TILE_STEP_X: u16 = 34;
const TILE_STEP_Y: u16 = 26;
const TILE_ORIGIN_X: i16 = -20; // pull the grid left so the first column hugs the border

// DELAY: a video-feedback grid. Each frame renders one small tile of the cube
// and pushes it into a ring of the last DN tiles (kept packed side-by-side in a
// spare plane buffer); grid cell g displays the slot from g frames ago, so the
// grid reads as a trail through time. DGX*DGY must equal DN.
const DTILE_W: u16 = 26;
const DTILE_H: u16 = 20;
const DGX: u16 = 12;
const DGY: u16 = 10;
const DN: u32 = 120; // ring length = tile count; DN*DTILE_W*DTILE_H (62400) must fit a plane (64000)

// Fixed UI palette indices, kept ABOVE the glenz bit-combo range (1..63) so the
// glenz palette reprogram never clobbers the frame / halftone-bg / text colours.
pub const FRAME_COL: u8 = 200;
pub const HT_BG: u8 = 201;
pub const TEXT_COL: u8 = 202;

pub const Fx = struct {
    gfx: Gfx = .{},
    cube: Cube = .{},
    wob: f32 = 0, // rubber-wobble phase
    wobble: Wobble = .{}, // RUBBER's per-row offsets (wobble.zig)
    head: u32 = 0, // DELAY ring write position

    pub fn init(self: *Fx) void {
        self.gfx.init();
        self.wobble.init();
    }

    pub fn step(self: *Fx) void {
        self.cube.spin();
        self.wob += 0.14;
        self.cube.project(geom.FOV, @divTrunc(WIDTH, 2), @divTrunc(HEIGHT, 2));
    }

    pub fn render(self: *Fx, zigos: *ZigOS, mode: u8) void {
        const fb: *LogicalFB = &zigos.lfbs[0];
        self.gfx.clearHalftone();
        self.gfx.clear(fb, 0);
        self.drawFrame(fb);
        switch (mode) {
            3 => self.renderGlenz(fb),
            4 => self.renderRubber(zigos, fb),
            5 => self.renderTile(zigos, fb),
            6 => self.renderDelay(zigos, fb),
            else => self.renderSolid(fb, mode == 2),
        }
    }

    // RUBBER: render the cube (flat) into a scratch plane once, then strip-blit it
    // back with a per-row sine X offset — a bitmap deformation (the classic
    // "rubber" wobble). Only the rows and columns the cube can cover are copied
    // (the rest of the scratch is the key colour, which a keyed blit skips
    // anyway), and rows that share an offset go in one blit: the same pixels as
    // 200 full-width one-row blits, for a fraction of the calls.
    fn renderRubber(self: *Fx, zigos: *ZigOS, fb: *LogicalFB) void {
        const scratch = &zigos.lfbs[1];
        self.gfx.clear(scratch, 0);
        self.drawFacesFlat(scratch);
        const box = self.cube.bounds(WIDTH, HEIGHT) orelse return;
        const w: u16 = @intCast(box.x1 - box.x0 + 1);
        var y = box.y0;
        var dx = self.wobble.dx(@intCast(y), self.wob);
        while (y <= box.y1) {
            var end = y + 1;
            var next: i16 = dx;
            while (end <= box.y1) : (end += 1) {
                next = self.wobble.dx(@intCast(end), self.wob);
                if (next != dx) break;
            }
            self.gfx.bob(fb, @intCast(box.x0 + dx), @intCast(y), scratch, @intCast(box.x0), @intCast(y), w, @intCast(end - y), 0);
            y = end;
            dx = next;
        }
    }

    // TILE: render the cube small ONCE into a TILE_W×TILE_H corner of a scratch
    // plane, then block-copy that tile across the grid — the whole screen filled
    // with cubes for one rasterisation + cheap copies.
    fn renderTile(self: *Fx, zigos: *ZigOS, fb: *LogicalFB) void {
        const scratch = &zigos.lfbs[1];
        const g = &self.gfx;
        g.fill(scratch, 0, 0, TILE_W, TILE_H, 0);
        self.cube.project(geom.FOV * @as(f32, @floatFromInt(TILE_W)) / @as(f32, @floatFromInt(WIDTH)), TILE_W / 2, TILE_H / 2);
        self.drawFacesFlat(scratch);
        self.cube.project(geom.FOV, @divTrunc(WIDTH, 2), @divTrunc(HEIGHT, 2)); // restore
        var gy: u16 = 0;
        while (gy < GRID_Y) : (gy += 1) {
            var gx: u16 = 0;
            while (gx < GRID_X) : (gx += 1) {
                g.bob(fb, @as(i16, @intCast(gx * TILE_STEP_X)) + TILE_ORIGIN_X, @intCast(gy * TILE_STEP_Y), scratch, 0, 0, TILE_W, TILE_H, 0);
            }
        }
        zigos.printText(fb, "TILES:80", 250, 8, TEXT_COL, 0);
    }

    // DELAY: render one mini-tile of the cube, push it into a ring of the last DN
    // tiles (packed side-by-side in plane 1), then show cell g from g frames ago —
    // a video-feedback trail. Ring stride = DN*DTILE_W keeps it one tile
    // tall, so the machine's stride->height clip leaves the slots addressable.
    fn renderDelay(self: *Fx, zigos: *ZigOS, fb: *LogicalFB) void {
        const g = &self.gfx;
        var tile = gfx.view(&zigos.lfbs[2], DTILE_W, DTILE_W, DTILE_H); // current-frame tile
        var ring = gfx.view(&zigos.lfbs[1], @intCast(DN * DTILE_W), @intCast(DN * DTILE_W), DTILE_H);

        g.fill(&tile, 0, 0, DTILE_W, DTILE_H, 0);
        self.cube.project(geom.FOV * @as(f32, @floatFromInt(DTILE_W)) / @as(f32, @floatFromInt(WIDTH)), DTILE_W / 2, DTILE_H / 2);
        self.drawFacesFlat(&tile);
        self.cube.project(geom.FOV, @divTrunc(WIDTH, 2), @divTrunc(HEIGHT, 2)); // restore
        g.blitCopy(&ring, @intCast(self.head * DTILE_W), 0, &tile, 0, 0, DTILE_W, DTILE_H);

        var n: u32 = 0;
        var gy: u16 = 0;
        while (gy < DGY) : (gy += 1) {
            var gx: u16 = 0;
            while (gx < DGX) : (gx += 1) {
                const slot = (self.head + DN - n) % DN; // n frames old
                g.bob(fb, @intCast(gx * DTILE_W), @intCast(gy * DTILE_H), &ring, @intCast(slot * DTILE_W), 0, DTILE_W, DTILE_H, 0);
                n += 1;
            }
        }
        self.head = (self.head + 1) % DN;
    }

    // Flat-shaded cube into an arbitrary target (used by RUBBER/TILE/DELAY scratch).
    fn drawFacesFlat(self: *Fx, target: *LogicalFB) void {
        var order = [6]u8{ 0, 1, 2, 3, 4, 5 };
        self.cube.sortFaces(&order);
        for (order) |f| self.face(target, f, f + 1, .copy);
    }

    // FLAT / LIT / HALFTONE: opaque faces, painter's sort (far first).
    fn renderSolid(self: *Fx, fb: *LogicalFB, halftone: bool) void {
        var order = [6]u8{ 0, 1, 2, 3, 4, 5 };
        self.cube.sortFaces(&order);
        for (order) |f| {
            if (halftone) self.gfx.setHalftone(geom.genHalftone(self.cube.brightness(f)));
            self.face(fb, f, f + 1, .copy);
        }
    }

    // GLENZ: every face drawn with a single-bit colour OR'd into the buffer; the
    // bit-combo palette (geom.programPalette) turns overlaps into blended shades.
    fn renderGlenz(self: *Fx, fb: *LogicalFB) void {
        for (0..6) |f| self.face(fb, @intCast(f), @as(u8, 1) << @intCast(f), .glenz);
    }

    // One quad face = two triangles. Copy faces carry HT_BG for the halftone's
    // clear bits; glenz faces OR a zero background (a no-op).
    fn face(self: *Fx, target: *LogicalFB, f: u8, color: u8, mt: zg.Minterm) void {
        const q = geom.FACES[f];
        const v = self.cube.screen;
        const bg: u8 = if (mt == .glenz) 0 else HT_BG;
        self.gfx.triangleEx(target, v[q[0]], v[q[1]], v[q[2]], color, bg, mt);
        self.gfx.triangleEx(target, v[q[0]], v[q[2]], v[q[3]], color, bg, mt);
    }

    fn drawFrame(self: *Fx, fb: *LogicalFB) void {
        const g = &self.gfx;
        const w: u16 = @intCast(WIDTH);
        const h: u16 = @intCast(HEIGHT);
        g.fill(fb, 0, 0, w, 4, FRAME_COL);
        g.fill(fb, 0, @intCast(HEIGHT - 4), w, 4, FRAME_COL);
        g.fill(fb, 0, 0, 4, h, FRAME_COL);
        g.fill(fb, @intCast(WIDTH - 4), 0, 4, h, FRAME_COL);
    }
};
