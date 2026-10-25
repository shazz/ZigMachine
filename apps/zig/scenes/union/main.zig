// --------------------------------------------------------------------------
// Union intro — MAIN SCREEN (efmain.js). Built up milestone by milestone:
//   M1 (here): sky gradient (per-scanline HBL) + 5 parallax layers + floor/
//   bottom bands, on a fullscreen (400x280) plane.
//   Next: tile world, running sprite, scroller, dragonballs, doors, music.
//
// Coordinate mapping: Codef canvas 768x540 -> ZigMachine 400x280 fullscreen at
// 1/2 scale, image origin at physical (8,5). Layer y-positions/speeds are the
// exact efmain.js values halved (see Fable's spec). Faithful to codef_parallax.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const ZigOS = zg.ZigOS;
const Color = zg.Color;
const gpu = @import("../union_common/gpu.zig");
const LogicalFB = zg.LogicalFB;
const convertU8ArraytoColors = zg.convertU8ArraytoColors;

const PW: i16 = @intCast(zg.PHYSICAL_WIDTH); // 400
const PH: usize = zg.PHYSICAL_HEIGHT; // 280

const p0_pal = convertU8ArraytoColors(@embedFile("../../assets/screens/union_main/p0.pal"));
const layer_b1 = @embedFile("../../assets/screens/union_main/layer_b1.raw");
const layer_b2 = @embedFile("../../assets/screens/union_main/layer_b2.raw");
const clouds1 = @embedFile("../../assets/screens/union_main/clouds1.raw");
const clouds2 = @embedFile("../../assets/screens/union_main/clouds2.raw");
const clouds3 = @embedFile("../../assets/screens/union_main/clouds3.raw");

// Spare palette entries (p0.pal uses 1..36) for the solid ground bands.
const WORLD_TOP: i16 = 35; // first row anything but the sky is drawn on
const FLOOR_TOP: i16 = 163; // from here the bands and parallax cover every pixel
// The three cloud strips tile rows 35..83 exactly (16 rows each, wrapped across the plane), and
// their colour 0 is the sky's: drawn as plain copies they repaint those rows whole, so only
// rows CLOUDS_END.. are erased (each strip's "transparent" 0 lands on sky 0 either way).
const CLOUDS_END: i16 = 83;
const FLOOR: u8 = 40; // pink band under the walkway
const BOTTOM: u8 = 41; // white band to the screen bottom
const BOTTOM_TOP: i16 = sq.DISC_TOP; // its first row: the dragonballs' discs are blended over it
const BOTTOM_RGB = Color{ .r = 224, .g = 224, .b = 224, .a = 255 };

// gradTiles red pixels are palette-animated (RED_A idx 35, RED_B idx 36), a
// 5-step ping-pong every 12 frames (efmain.js: 224->192->128->64->0).
const RED_A = [5]u8{ 224, 192, 128, 64, 0 };
const RED_B = [5]u8{ 255, 192, 128, 64, 0 };
const GRAD_RED_A: u8 = 35;
const GRAD_RED_B: u8 = 36;
const SCROLL_WRAP: f32 = 778; // pinpinPos wraps here (map tail repeats the head)


const wd = @import("world_draw.zig");
const sky = @import("sky.zig"); // P0's HBL: the sky raster + its borders open
const Parallax5 = zg.parallax.Parallax(5);
const Runner = @import("runner.zig").Runner;
const Dragonballs = @import("dragonball.zig").Dragonballs;
const Scroller = @import("scroller.zig").Scroller;
const Credits = @import("credits.zig").Credits;
const sq = @import("dragonball_squash.zig");
const split = @import("p1_split.zig");
const WorldRing = @import("world_ring.zig").Ring;

pub const Demo = struct {
    px: Parallax5 = undefined,
    runner: Runner = .{},
    balls: Dragonballs = .{},
    scroller: Scroller = .{},
    credits: Credits = .{},
    ring: WorldRing = .{}, // map rows 3..7 (plane rows 83..163), on plane 2, never enabled
    pos: f32 = 0, // world scroll in tiles
    speed: f32 = 0.3, // scroll tiles/frame; host may slow it (0.3 = nominal)
    frame: u32 = 0,
    fresh: bool = true, // the planes have not been cleared whole yet
    grad_idx: u8 = 0, // gradTiles palette-animation step
    grad_inc: i8 = 1,
    // Keys 1-6: the playlist and its SNDH proofs live in tracks.zig.
    pub const TRACKS = @import("tracks.zig").TRACKS;

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        gpu.init();
        self.pos = 0;
        self.frame = 0;
        self.fresh = true;
        self.grad_idx = 0;
        self.grad_inc = 1;
        autoplay(); // track 1, unless the cracktro already started a tune
        const p0: *LogicalFB = &zigos.lfbs[0];
        p0.is_enabled = true;
        p0.setOverscanBuffer();
        p0.setPalette(p0_pal);
        p0.palette[0] = sky.SKY[0];
        p0.setPaletteEntry(FLOOR, Color{ .r = 192, .g = 96, .b = 128, .a = 255 });
        p0.setPaletteEntry(BOTTOM, BOTTOM_RGB);
        p0.setFrameBufferHBLHandlerPure(zg.OVERSCAN_MAGIC_X, sky.handler); // sky gradient + overscan flicker
        self.runner.init(zigos); // sets up plane 1 (actors)
        split.init(&zigos.lfbs[1]); // P1's palette split: actors above, scrolltext below
        self.balls.init(zigos, BOTTOM_RGB); // dragonballs on plane 0, over the bottom band
        self.credits.init(zigos); // credits pages on plane 1 (top, faded)
        self.scroller.init(zigos); // scrolltext on plane 1, under the split
        self.ring.init(&zigos.lfbs[2]);
        self.px = .{ .layers = .{
            .{ .raw = layer_b1, .w = 384, .h = 16, .y = 195, .speed = 11 },
            .{ .raw = layer_b2, .w = 384, .h = 16, .y = 179, .speed = 7 },
            .{ .raw = clouds1, .w = 320, .h = 16, .y = 67, .speed = 1 },
            .{ .raw = clouds2, .w = 320, .h = 16, .y = 51, .speed = 1.5 },
            .{ .raw = clouds3, .w = 320, .h = 16, .y = 35, .speed = 2 },
        } };
    }

    pub fn update(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = dt;
        self.px.update(self.speed / 0.3); // parallax follows the scroll speed
        self.pos += self.speed; // world scroll (nominal 0.3 tiles/frame)
        if (self.pos >= SCROLL_WRAP) self.pos -= SCROLL_WRAP;
        self.frame += 1;
        if (self.frame % 12 == 0) { // gradTiles palette ping-pong
            const p0: *LogicalFB = &zigos.lfbs[0];
            p0.setPaletteEntry(GRAD_RED_A, Color{ .r = RED_A[self.grad_idx], .g = 0, .b = 0, .a = 255 });
            p0.setPaletteEntry(GRAD_RED_B, Color{ .r = RED_B[self.grad_idx], .g = 0, .b = 0, .a = 255 });
            if (self.grad_idx == 4) self.grad_inc = -1;
            if (self.grad_idx == 0) self.grad_inc = 1;
            self.grad_idx = @intCast(@as(i16, self.grad_idx) + self.grad_inc);
        }
        self.runner.update();
        self.balls.update();
        self.credits.update(zigos);
        self.scroller.update();
    }

    pub fn render(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = dt;
        const p0: *LogicalFB = &zigos.lfbs[0];
        // Index 0 = sky, recoloured per scanline by the HBL. Rows 0..34 are never drawn
        // on, the clouds repaint 35..82 whole, rows 83..162 are copied whole out of the
        // world ring (world_ring.zig: the cells over 0) and rows 163.. are covered whole
        // by the floor, the parallax and the bottom band: only the first frame clears.
        if (self.fresh) gpu.clear(p0, 0);
        wd.parallax(&self.px, p0, @intCast(PW)); // CHISEL strips (zg.parallax's CPU copies were a megacycle)
        // Ground: floorback is a 16px pink strip (behind world row 8); the
        // scrolling layer_b1/b2 parallax fills 179..211 below it; bottomback
        // white to the screen bottom. (Don't over-fill and hide the floor
        // parallax.)
        fill(p0, FLOOR_TOP, 179, FLOOR);
        fill(p0, BOTTOM_TOP, @intCast(PH), BOTTOM);
        // Tile world: clouds (behind) -> animated rows -> world tiles (on top).
        wd.world(p0, self.pos, &self.ring); // clouds -> animated rows -> world, pre-composited cells (world_cells.zig)
        self.balls.draw(zigos); // dragonballs on plane 0, last
        split.erase(&zigos.lfbs[1], self.fresh);
        self.fresh = false;
        self.runner.draw(zigos, self.speed / 0.3); // ghost trail scales with speed
        self.credits.draw(zigos); // credits pages on plane 1 (top area)
        self.scroller.draw(zigos); // scrolltext on plane 1, under the split
    }

    // Keys 1-6 switch the YM tune — request the track BY NAME (host plays it).
    pub fn setShadeMode(self: *Demo, mode: u32) void {
        _ = self;
        if (mode < TRACKS.len) requestTrack(TRACKS[mode]);
    }

    /// Keys 1-6: ask the host for `name` unless it is the tune asked for last,
    /// so pressing the playing track's key never restarts it. The Codef remake's
    /// keys do the same: they only switch when `currentTrack != n`.
    /// Start track 1, unless a tune was already asked for in this cart. In the
    /// cracktro, union_intro starts it with the TRSI logo, and the viewer may have
    /// picked another with 1-6 since. The remake's main part never touches the music.
    pub fn autoplay() void {
        if (zg.songNameLen() == 0) zg.requestSong(TRACKS[0]);
    }

    pub fn requestTrack(name: []const u8) void {
        if (@import("std").mem.eql(u8, zg.songNamePtr()[0..zg.songNameLen()], name)) return;
        zg.requestSong(name);
    }

    // Solid bands: one CHISEL fill each (was a setPixelValue call per pixel,
    // 400 x 85 of them a frame).
    fn fill(fb: *LogicalFB, y0: i16, y1: i16, idx: u8) void {
        gpu.fill(fb, 0, y0, @min(PW, @as(i16, @intCast(fb.fb_w))), y1 - y0, idx);
    }
};

comptime { // the cloud strips (Demo.init) cover WORLD_TOP..CLOUDS_END, one after the other
    if (WORLD_TOP + 3 * 16 != CLOUDS_END) @compileError("the cloud strips no longer tile WORLD_TOP..CLOUDS_END");
    const rows = @import("world_ring.zig");
    if (rows.TOP != CLOUDS_END or rows.TOP + (rows.ROW1 - rows.ROW0) * 16 != FLOOR_TOP) @compileError("the world ring no longer covers CLOUDS_END..FLOOR_TOP");
}
