// --------------------------------------------------------------------------
// AN Cool's 3D starfield as a frame table, built ONCE at init.
//
// The cart used to run zg.Starfield3D every frame: 300 stars, two f32
// divides each, plus the f32 render tests and conversions. The field is a
// closed system (seed 0, every star's z steps by -5 and wraps by +260), so
// what it draws is a function of the frame number alone, and it is
// PERIODIC: once every star has wrapped once and settled (frame STEADY), the
// whole state repeats every 260 / 5 = 52 frames bit for bit (each -5 step is
// exact, and a settled wrap adds back exactly the 260 the steps took off;
// stars_test.zig asserts it over 4,000 frames and that STEADY is the first).
//
// So init runs the library's own update() for the transient plus one period
// (LEN frames) and records, per frame and star, the pixel the original render()
// would have set. The float maths therefore stays the original's, with the
// same casts in the same compiler (out-of-range projections included, which
// the original leaves to the wasm conversion), and runs once at init (the
// project's rule allows float when building a table); the frame only indexes
// the table. ~182 KB of cart RAM (zg.mem), nothing in the data segment.
// --------------------------------------------------------------------------
const zg = @import("zigos");

pub const NB = 300;
const SPEED = 5;
const PERIOD = 52; // 260 / SPEED
// Frames 1..STEADY-1 are the one-off start; from STEADY on, frame n draws
// what frame n - PERIOD drew (stars_test.zig checks both numbers).
pub const STEADY = 104;
pub const LEN = STEADY + PERIOD; // frames 1..LEN-1 recorded, slot 0 unused
pub const NONE: u32 = 0xFFFF_FFFF; // star not drawn this frame

// The star colours sit at palette entries BASE + 1 .. BASE + 35 of the merged
// plane (entry 1 is the scroller's raster ink). Starfield3D's own palette, as
// it was on plane 0: entry 0 clear, 1..10 opaque white, 11..30 white fading,
// 31..35 never set (zero = transparent, as on plane 0; the projection reaches
// index 35 near the far plane).
pub const BASE = 1;
pub const GRADIENT_STEPS = 30;

const Field = zg.Starfield3D(NB);
var sim: Field = undefined;
var scratch_buf: [1]u8 = undefined;
var scratch: zg.RenderBuffer = .{ .buffer = &scratch_buf, .width = 1, .height = 1 };

/// One entry: (pixel offset in a 320-wide plane) | (palette entry << 16), or NONE.
pub fn build(table: []u32) void {
    sim = Field.init(.{ .render_buffer = &scratch }, zg.WIDTH, zg.HEIGHT, SPEED, false);
    for (1..LEN) |frame| {
        sim.update();
        for (sim.starfield_table, 0..) |star, i| table[frame * NB + i] = plotOf(star);
    }
}

// What Starfield3D.render (use_lines = false) does for one star, with the
// same expressions and casts; setPixelValue's clip folded in.
fn plotOf(star: anytype) u32 {
    const s = &sim;
    if (!(star.prev_proj_x > 0 and star.prev_proj_x < s.width and star.prev_proj_y > 0 and star.prev_proj_y < s.height)) return NONE;
    const pal_index = 1 + s.color_ratio * star.z * 1.2 * @as(f32, @floatFromInt(GRADIENT_STEPS - 1));
    const x: u16 = @as(u16, @intFromFloat(star.proj_x));
    const y: u16 = @as(u16, @intFromFloat(star.proj_y));
    if (x >= zg.WIDTH or y >= zg.HEIGHT) return NONE;
    const pal: u8 = @as(u8, @intFromFloat(pal_index));
    return (@as(u32, y) * zg.WIDTH + x) | (@as(u32, pal + BASE) << 16);
}

/// The table frame that frame `n` (1-based update count) draws.
pub fn slot(n: u32) u32 {
    if (n < STEADY) return n;
    return STEADY + (n - STEADY) % PERIOD;
}

/// The palette entries the stars use, set on the merged plane.
pub fn setPalette(fb: *zg.LogicalFB) void {
    var i: u8 = 0;
    while (i < 10) : (i += 1) fb.setPaletteEntry(BASE + i + 1, .{ .r = 255, .g = 255, .b = 255, .a = 255 });
    while (i < GRADIENT_STEPS) : (i += 1) {
        fb.setPaletteEntry(BASE + i + 1, .{ .r = 255, .g = 255, .b = 255, .a = 255 - (i * (255 / GRADIENT_STEPS - 1)) });
    }
}

/// Plot one frame's stars, in the original star order.
pub fn draw(pixels: [*]u8, table: []const u32, n: u32) void {
    const row = table[slot(n) * NB ..][0..NB];
    for (row) |e| {
        if (e == NONE) continue;
        pixels[e & 0xFFFF] = @truncate(e >> 16);
    }
}
