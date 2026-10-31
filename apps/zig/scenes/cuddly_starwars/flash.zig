// --------------------------------------------------------------------------
// CUDDLY STARWARS — the logo flash: bg.png at (30,10) drawn with canvas alpha
// fade * 0.05, invisible except a 39-frame fade-out every 301 frames.
//
// The original's fade is a double: 20 at frame 280, minus 0.5 a frame down to 0.
// It only ever holds a whole number of halves, so it runs here as `half` (40..0)
// and the two palette entries of each step are built at COMPILE time by the
// same f64 maths (zg.palette.scale, rounded), evaluated by the compiler: the
// frame indexes a table instead of multiplying doubles (soft-float on ZIGGY).
// --------------------------------------------------------------------------

const zg = @import("zigos");

const LogicalFB = zg.LogicalFB;
const Color = zg.Color;

const FLASH_WRAP: u32 = 300;
const FLASH_AT: u32 = 280;
const FADE_START_HALVES: u32 = 40; // fade = 20
const FADE_ALPHA: f64 = 0.05;
const ENTRIES = [_]u8{ 8, 9 }; // BG_ORANGE, BG_GREY: the logo's only colours
const BG_X: i16 = 30;
const BG_Y: i16 = 10;
const BG_W: u16 = 260;
const BG_H: u16 = 73;
const bg_b = @embedFile("../../assets/screens/cuddly_starwars/bg.raw");

comptime {
    if (bg_b.len != @as(usize, BG_W) * BG_H) @compileError("bg.raw size");
}

/// The entries' colours at each fade step, index = fade in halves (0 unused).
fn steps(comptime base: [256]Color) [FADE_START_HALVES + 1][ENTRIES.len]Color {
    @setEvalBranchQuota(10_000);
    var t: [FADE_START_HALVES + 1][ENTRIES.len]Color = undefined;
    for (0..FADE_START_HALVES + 1) |h| {
        const fade: f64 = @as(f64, @floatFromInt(h)) * 0.5; // exact, as the original's
        const alpha: f64 = fade * FADE_ALPHA;
        for (ENTRIES, 0..) |e, i| {
            t[h][i] = zg.palette.scale(base[e], alpha, .{ .rounding = .round, .alpha = .{ .set = 255 } });
        }
    }
    return t;
}

pub fn Flash(comptime base: [256]Color) type {
    const table = steps(base);
    return struct {
        counter: u32,
        half: u32, // the original's fade, in halves

        pub const init: @This() = .{ .counter = 0, .half = 0 };

        /// The original's per-frame step, in its order.
        pub fn step(self: *@This()) void {
            self.counter += 1;
            if (self.counter > FLASH_WRAP) self.counter = 0;
            if (self.counter == FLASH_AT) self.half = FADE_START_HALVES;
            if (self.half > 0) self.half -= 1;
        }

        pub fn draw(self: *const @This(), fb: *LogicalFB, blitter: *zg.Blitter) void {
            if (self.half == 0) return;
            for (ENTRIES, table[self.half]) |e, c| fb.setPaletteEntry(e, c);
            blitter.blitImage(fb, BG_X, BG_Y, bg_b, BG_W, 0, 0, BG_W, BG_H, 0);
        }
    };
}
