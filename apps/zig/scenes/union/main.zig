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
const tileset_raw = @embedFile("../../assets/screens/union_main/tileset.raw");
const gradtiles_raw = @embedFile("../../assets/screens/union_main/gradtiles.raw");
const world_dat = @embedFile("../../assets/screens/union_main/world.dat");
const anim_dat = @embedFile("../../assets/screens/union_main/anim.dat");
const clouds_dat = @embedFile("../../assets/screens/union_main/clouds.dat");

// Spare palette entries (p0.pal uses 1..36) for the solid ground bands.
const FLOOR: u8 = 40; // pink band under the walkway
const BOTTOM: u8 = 41; // white band to the screen bottom

// gradTiles red pixels are palette-animated (RED_A idx 35, RED_B idx 36), a
// 5-step ping-pong every 12 frames (efmain.js: 224->192->128->64->0).
const RED_A = [5]u8{ 224, 192, 128, 64, 0 };
const RED_B = [5]u8{ 255, 192, 128, 64, 0 };
const GRAD_RED_A: u8 = 35;
const GRAD_RED_B: u8 = 36;
const WORLD_W: usize = 802;
const SCROLL_WRAP: f32 = 778; // pinpinPos wraps here (map tail repeats the head)

// Tile world: tileset (17x7 of 16x16) for world+clouds; gradTiles (8-wide) for
// the animated rows. Faithful to efmain.js scroll (0.3 tiles/frame) + rows.
const Tile = zg.tilemap;
const tileset = Tile.TileSheet{ .raw = tileset_raw, .sheet_w = 272, .tw = 16, .th = 16, .cols = 17 };
const grad = Tile.TileSheet{ .raw = gradtiles_raw, .sheet_w = 128, .tw = 16, .th = 16, .cols = 8 };
const world_layer = Tile.Layer{ .sheet = &tileset, .map = world_dat, .map_w = WORLD_W, .rows = 9, .id_base = 1, .dst_y = 35 };
const anim_layer = Tile.Layer{ .sheet = &grad, .map = anim_dat, .map_w = WORLD_W, .rows = 5, .id_base = 120, .dst_y = 83 };
const clouds_layer = Tile.Layer{ .sheet = &tileset, .map = clouds_dat, .map_w = WORLD_W, .rows = 1, .id_base = 1, .dst_y = 131 };

// Sky gradient: background.png horizontal bands (efmain.js). Physical row ->
// original row = (r-5)*2; the machine re-reads palette[0] per scanline via an
// HBL handler, so the gradient costs zero pixels.
const Band = struct { max_orig: i32, r: u8, g: u8, b: u8 };
const BANDS = [_]Band{
    .{ .max_orig = 21, .r = 0, .g = 0, .b = 0 },     .{ .max_orig = 23, .r = 0, .g = 0, .b = 32 },
    .{ .max_orig = 25, .r = 0, .g = 0, .b = 0 },     .{ .max_orig = 59, .r = 0, .g = 0, .b = 32 },
    .{ .max_orig = 61, .r = 0, .g = 0, .b = 64 },    .{ .max_orig = 63, .r = 0, .g = 0, .b = 32 },
    .{ .max_orig = 91, .r = 0, .g = 0, .b = 64 },    .{ .max_orig = 93, .r = 0, .g = 0, .b = 96 },
    .{ .max_orig = 95, .r = 0, .g = 0, .b = 64 },    .{ .max_orig = 123, .r = 0, .g = 0, .b = 96 },
    .{ .max_orig = 125, .r = 0, .g = 0, .b = 128 },  .{ .max_orig = 127, .r = 0, .g = 0, .b = 96 },
    .{ .max_orig = 155, .r = 0, .g = 0, .b = 128 },  .{ .max_orig = 157, .r = 0, .g = 32, .b = 160 },
    .{ .max_orig = 159, .r = 0, .g = 0, .b = 128 },  .{ .max_orig = 187, .r = 0, .g = 32, .b = 160 },
    .{ .max_orig = 189, .r = 0, .g = 64, .b = 192 }, .{ .max_orig = 191, .r = 0, .g = 32, .b = 160 },
    .{ .max_orig = 219, .r = 0, .g = 64, .b = 192 }, .{ .max_orig = 221, .r = 0, .g = 96, .b = 224 },
    .{ .max_orig = 223, .r = 0, .g = 64, .b = 192 }, .{ .max_orig = 283, .r = 0, .g = 96, .b = 224 },
};

// Per-physical-row sky colour, resolved at comptime from BANDS.
const SKY: [PH]Color = blk: {
    @setEvalBranchQuota(20000);
    var t: [PH]Color = undefined;
    for (0..PH) |r| {
        var orig: i32 = (@as(i32, @intCast(r)) - 5) * 2;
        if (orig < 0) orig = 0;
        for (BANDS) |b| {
            if (orig <= b.max_orig) {
                t[r] = Color{ .r = b.r, .g = b.g, .b = b.b, .a = 255 };
                break;
            }
        } else t[r] = Color{ .r = 0, .g = 96, .b = 224, .a = 255 };
    }
    break :blk t;
};

// Merged with the overscan trick: the parallax/tile world spans the full
// 400-wide plane, so borders must stay open every line too. Both effects are
// per-scanline palette/latch writes with no pixel-column sensitivity, so they
// share one HBL handler registered at OVERSCAN_MAGIC_X (a single per-plane
// handler slot — see docs/HW_API.md "Opening the borders").
fn skyHandler(fb: *LogicalFB, zigos: *ZigOS, line: u16, x: u16) void {
    _ = zigos;
    _ = x;
    if (line < PH) fb.setPaletteEntry(0, SKY[line]);
    fb.flickerBorder();
}

const Parallax5 = zg.parallax.Parallax(5);
const Runner = @import("runner.zig").Runner;
const Dragonballs = @import("dragonball.zig").Dragonballs;
const Scroller = @import("scroller.zig").Scroller;
const Credits = @import("credits.zig").Credits;

pub const Demo = struct {
    px: Parallax5 = undefined,
    runner: Runner = .{},
    balls: Dragonballs = .{},
    scroller: Scroller = .{},
    credits: Credits = .{},
    pos: f32 = 0, // world scroll in tiles
    speed: f32 = 0.3, // scroll tiles/frame; host may slow it (0.3 = nominal)
    frame: u32 = 0,
    grad_idx: u8 = 0, // gradTiles palette-animation step
    grad_inc: i8 = 1,
    // This scene OWNS its playlist (host holds none): tunes under docs/music/.
    // Tracks 1, 2, 5 and 6 play the real SNDH replay routine (smaller, and the
    // authentic player, not a register-dump recording). Proof: YM regs 0-5,8-10
    // (volume masked 0x1f) of the SNDH vs the old .ymraw, % of register cells
    // equal over 800 frames, offsets -50..+400, every subtune, rendered
    // headless through the real demo-audio + machine-audio modules (SNDH
    // images at $10002 since #91):
    //   1 SharpnessBuzztone.ymraw == Jess/Sharpness_Buzztone.sndh: 99.8% at
    //     offset 0, tune default. FLAG ~ay audible headless (peak 0.55-0.80).
    //   5 Lap33.ymraw (header "LAP 22 (e.g. BMT screen/PYM)", Lap/Next, conv.
    //     Senser/Vectronix) == Lap/Lap_33.sndh: 100.0% (every frame whole) at
    //     offset -24, its only tune; FLAG ~y, peak 0.68. The "22" was a typo.
    // SID tunes (tracks 2 and 6). A 50 Hz dump cannot record a timer SID
    // effect: the replay's timer zeroes a voice's volume between the dump's
    // samples, so those volume cells miss even when the tune is the original.
    // Matt's rule, 2026-09-13: accept a SID SNDH whose period registers 0-5
    // match 100% and whose only misses are those SID-zeroed volumes.
    //   2 150mph.ymraw (TAO of ACF, conv. Leonard) == Tao/Steps/150_mph.sndh,
    //     its only tune, offset 0: periods 100%, 94.3% of cells, 49.4% of
    //     frames whole; every miss is vol 9 zeroed by its timer A/D SID. It
    //     replaced Tao/Songs_That_Make_U_Go_Mmh2/150_mph.sndh (95.9% of cells,
    //     78.1% of frames, but channel A an octave apart: another arrangement).
    //     TSD_STe/150_mph is STE DMA (~ey): silent here, 42.6%.
    //   6 Reality.ymraw (Gunnar Gaubatz (Big Alec), conv. Oedipus) ==
    //     Big_Alec/Reality.sndh, its only tune, offset 0: periods 100%, 94.5%
    //     of cells, 50.1% of frames whole; every miss is vol 10 zeroed by its
    //     timer-D SID. Nemo/Reality_Enraged.sndh: 0%.
    // Tracks 3 and 4 stay .ymraw (archive searched by TITL/COMM/filename):
    //   Androids: Tao/Steps/Androids.sndh 89.4% of cells, 27.4% of frames
    //     (periods 100%, its SID zeroes vols 9 AND 10); Mmh2 version 76.8%.
    //   Drooling: 505/Drooling.sndh 61.6% (an STE DMA replay, not this dump).
    pub const TRACKS = [_][]const u8{
        "union/sharpness_buzztone.sndh",
        "union/150_mph.sndh",
        "union/Androids.ymraw",
        "union/Drooling.ymraw",
        "union/lap_33.sndh",
        "union/reality.sndh",
    };

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        self.pos = 0;
        self.frame = 0;
        self.grad_idx = 0;
        self.grad_inc = 1;
        requestTrack(TRACKS[0]); // autoplay track 1, unless union_intro already started it
        const p0: *LogicalFB = &zigos.lfbs[0];
        p0.is_enabled = true;
        p0.setOverscanBuffer();
        p0.setPalette(p0_pal);
        p0.setPaletteEntry(0, SKY[0]);
        p0.setPaletteEntry(FLOOR, Color{ .r = 192, .g = 96, .b = 128, .a = 255 });
        p0.setPaletteEntry(BOTTOM, Color{ .r = 224, .g = 224, .b = 224, .a = 255 });
        p0.setFrameBufferHBLHandler(zg.OVERSCAN_MAGIC_X, skyHandler); // sky gradient + overscan flicker
        self.runner.init(zigos); // sets up plane 1 (actors)
        self.balls.init(zigos); // dragonballs share plane 1, own palette slots
        self.credits.init(zigos); // credits pages on plane 1 (top, faded)
        self.scroller.init(zigos); // sets up plane 2 (scrolltext)
        self.px = .{ .layers = .{
            .{ .raw = layer_b1, .w = 384, .h = 16, .y = 195, .speed = 11 },
            .{ .raw = layer_b2, .w = 384, .h = 16, .y = 179, .speed = 7 },
            .{ .raw = clouds1, .w = 320, .h = 16, .y = 67, .speed = 1, .transparent = true },
            .{ .raw = clouds2, .w = 320, .h = 16, .y = 51, .speed = 1.5, .transparent = true },
            .{ .raw = clouds3, .w = 320, .h = 16, .y = 35, .speed = 2, .transparent = true },
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
        p0.clearFrameBuffer(0); // index 0 = sky, recoloured per scanline by the HBL
        self.px.draw(p0, 0, @intCast(PW));
        // Ground: floorback is a 16px pink strip (behind world row 8); the
        // scrolling layer_b1/b2 parallax fills 179..211 below it; bottomback
        // white to the screen bottom. (Don't over-fill and hide the floor
        // parallax.)
        fill(p0, 163, 179, FLOOR);
        fill(p0, 211, @intCast(PH), BOTTOM);
        // Tile world: clouds (behind) -> animated rows -> world tiles (on top).
        clouds_layer.draw(p0, self.pos);
        anim_layer.draw(p0, self.pos);
        world_layer.draw(p0, self.pos);
        self.runner.draw(zigos, self.speed / 0.3); // ghost trail scales with speed
        self.balls.draw(zigos); // dragonballs on plane 1, after the runner
        self.credits.draw(zigos); // credits pages on plane 1 (top area)
        self.scroller.draw(zigos); // plane 2 (scrolltext) on top
    }

    // Keys 1-6 switch the YM tune — request the track BY NAME (host plays it).
    pub fn setShadeMode(self: *Demo, mode: u32) void {
        _ = self;
        if (mode < TRACKS.len) requestTrack(TRACKS[mode]);
    }

    /// Ask the host for `name` unless it is the tune asked for last, so a
    /// playing track is never restarted. union_intro starts track 1 with the
    /// TRSI logo and main must not start it again. The Codef remake's keys 1-6
    /// do the same: they only switch when `currentTrack != n`.
    pub fn requestTrack(name: []const u8) void {
        if (@import("std").mem.eql(u8, zg.songNamePtr()[0..zg.songNameLen()], name)) return;
        zg.requestSong(name);
    }

    fn fill(fb: *LogicalFB, y0: i16, y1: i16, idx: u8) void {
        var y: i16 = y0;
        while (y < y1) : (y += 1) {
            var x: i16 = 0;
            while (x < PW) : (x += 1) fb.setPixelValue(@intCast(x), @intCast(y), idx);
        }
    }
};
