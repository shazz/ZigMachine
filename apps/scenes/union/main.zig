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

// Spare palette entries (p0.pal uses 1..36) for the solid ground bands.
const FLOOR: u8 = 40; // pink band under the walkway
const BOTTOM: u8 = 41; // white band to the screen bottom

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

fn skyHandler(fb: *LogicalFB, zigos: *ZigOS, line: u16, x: u16) void {
    _ = zigos;
    _ = x;
    if (line < PH) fb.setPaletteEntry(0, SKY[line]);
}

const Parallax5 = zg.parallax.Parallax(5);
const Layer = zg.parallax.Layer;

pub const Demo = struct {
    px: Parallax5 = undefined,

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        const p0: *LogicalFB = &zigos.lfbs[0];
        p0.is_enabled = true;
        p0.setFullscreen();
        p0.setPalette(p0_pal);
        p0.setPaletteEntry(0, SKY[0]);
        p0.setPaletteEntry(FLOOR, Color{ .r = 192, .g = 96, .b = 128, .a = 255 });
        p0.setPaletteEntry(BOTTOM, Color{ .r = 224, .g = 224, .b = 224, .a = 255 });
        p0.setFrameBufferHBLHandler(0, skyHandler); // per-scanline sky gradient
        self.px = .{ .layers = .{
            .{ .raw = layer_b1, .w = 384, .h = 16, .y = 195, .speed = 11 },
            .{ .raw = layer_b2, .w = 384, .h = 16, .y = 179, .speed = 7 },
            .{ .raw = clouds1, .w = 320, .h = 16, .y = 67, .speed = 1, .transparent = true },
            .{ .raw = clouds2, .w = 320, .h = 16, .y = 51, .speed = 1.5, .transparent = true },
            .{ .raw = clouds3, .w = 320, .h = 16, .y = 35, .speed = 2, .transparent = true },
        } };
    }

    pub fn update(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = zigos;
        _ = dt;
        self.px.update();
    }

    pub fn render(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = dt;
        const p0: *LogicalFB = &zigos.lfbs[0];
        p0.clearFrameBuffer(0); // index 0 = sky, recoloured per scanline by the HBL
        self.px.draw(p0, 0, @intCast(PW));
        // Ground bands (floorback pink, bottomback white) under the (future) tiles.
        fill(p0, 163, 211, FLOOR);
        fill(p0, 211, @intCast(PH), BOTTOM);
    }

    fn fill(fb: *LogicalFB, y0: i16, y1: i16, idx: u8) void {
        var y: i16 = y0;
        while (y < y1) : (y += 1) {
            var x: i16 = 0;
            while (x < PW) : (x += 1) fb.setPixelValue(@intCast(x), @intCast(y), idx);
        }
    }
};
