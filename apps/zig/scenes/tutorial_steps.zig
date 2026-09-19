// --------------------------------------------------------------------------
// tutorial_steps.zig: the tutorial screen, stopped at any step of docs/TUTORIAL.md.
//
// WHY THIS IS A SEPARATE FILE FROM tutorial.zig:
// docs/TUTORIAL.html puts a "Run step N" button on every step, and running the
// FINISHED screen there would be a lie — step 2's prose says "a dark blue
// rectangle in a black border" while the finished cart shows a scroller, a
// copper bar and music. So the page needs a cart that can stop early.
//
// The gates could have lived in tutorial.zig, but that file is what the tutorial
// holds up as "the finished file, short enough to read in one sitting", and
// every snippet in TUTORIAL.md is quoted from it verbatim. Adding `if (step >= 5)`
// there would make the md's snippets subtly untrue of the real file.
//
// The copy is kept honest by a test, not by discipline: apps/tutorial_steps_check.mjs
// asserts this cart at step 7 renders frames byte-identical to demo-tutorial.wasm.
// If the two drift, the gate fails.
//
// The step arrives through setShadeMode — the sealed ABI's existing
// "per-scene mode switch" (see apps/zig/demo_main.zig) — which the loader calls
// for ?step=N. Nothing new was added to the ABI for this.
//
// Build: sh ./build.sh          Run: docs/index.html?demo=demo-tutorial-steps.wasm&step=3
// --------------------------------------------------------------------------
const zg = @import("zigos");
const ZigOS = zg.ZigOS;
const LogicalFB = zg.LogicalFB;
const Color = zg.Color;

const W: u16 = zg.WIDTH; // 320
const H: u16 = zg.HEIGHT; // 200

// palette indices
const SKY: u8 = 0;
const FLOOR_DARK: u8 = 1;
const FLOOR_LIGHT: u8 = 2;
const BLOCK: u8 = 3;
const TEXT_INK: u8 = 4;

const FLOOR_Y: u16 = 160;
const BLOCK_SIZE: i32 = 24;
const BAR_H: i32 = 16;

const TEXT = "HELLO FROM ZIG * THIS IS YOUR FIRST ZIGMACHINE SCREEN * ";
const TEXT_W: i32 = TEXT.len * 8; // the 8x8 system font

const MUSIC = "sos.sndh"; // a file under docs/music/

// Which step of docs/TUTORIAL.md to stop at. 7 = the whole screen, i.e. exactly
// what tutorial.zig draws. Set before init() by the host, via setShadeMode.
const LAST_STEP: u32 = 7;
var step: u32 = LAST_STEP;
// Re-run stage() on the next update(). Module scope, because setShadeMode is a
// free function (the ABI gives it no Demo pointer).
var restage: bool = true;

var copper_table: [1]zg.copper.Table = undefined;

fn rgb(r: u8, g: u8, b: u8) Color {
    return .{ .r = r, .g = g, .b = b, .a = 255 };
}

fn drawFloor(fb: *LogicalFB) void {
    for (FLOOR_Y..H) |y| {
        for (0..W) |x| {
            const light = ((x / 20 + y / 10) & 1) == 1;
            fb.setPixelValue(@intCast(x), @intCast(y), if (light) FLOOR_LIGHT else FLOOR_DARK);
        }
    }
}

fn fillRect(fb: *LogicalFB, x: i32, y: i32, w: i32, h: i32, index: u8) void {
    var j = y;
    while (j < y + h) : (j += 1) {
        var i = x;
        while (i < x + w) : (i += 1) fb.setPixelValue(@intCast(i), @intCast(j), index);
    }
}

// The host's ?step=N. It cannot arrive before init(): the sealed ABI only
// forwards setShadeMode once the cart is running (see apps/zig/demo_main.zig),
// and by then init() has already run. So init() sets fields ONLY and every
// step-dependent decision is made on the first update(), which is still before
// the host renders a plane — the reader never sees a frame of the wrong step.
//
// An out-of-range step is refused rather than clamped: a bad step means a broken
// link on the tutorial page, and a silent fallback would hide it
// (rules/shared/change-discipline.md).
pub const Demo = struct {
    block_x: i32,
    block_y: i32,
    block_dx: i32,
    block_dy: i32,
    bar_y: i32,
    bar_dy: i32,
    scroll_x: i32,

    // MUST be a method on Demo: the ABI gates on @hasDecl(Cart, "setShadeMode")
    // and Cart is this struct, so a module-level fn of the same name is never
    // found (it silently did nothing, and every step rendered the finished screen).
    pub fn setShadeMode(self: *Demo, mode: u32) void {
        _ = self;
        if (mode >= 1 and mode <= LAST_STEP) {
            step = mode;
            restage = true;
        }
    }

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        _ = zigos; // nothing is staged yet — see setShadeMode
        self.block_x = 40;
        self.block_y = 40;
        self.block_dx = 2;
        self.block_dy = 1;
        self.bar_y = 24;
        self.bar_dy = 2;
        self.scroll_x = 0;
        restage = true;
    }

    // Everything tutorial.zig does in init(), gated by how far the reader has got.
    fn stage(self: *Demo, zigos: *ZigOS) void {
        _ = self;
        if (step >= 7) zg.requestSong(MUSIC); // step 7: music

        zigos.setBackgroundColor(rgb(0, 0, 0));

        const fb = &zigos.lfbs[0];
        fb.is_enabled = step >= 2; // step 2: a plane and a palette
        if (step < 2) return; // step 1: an empty cart that boots, and nothing else

        fb.setPaletteEntry(SKY, rgb(0, 0, 40));
        fb.setPaletteEntry(FLOOR_DARK, rgb(60, 20, 90));
        fb.setPaletteEntry(FLOOR_LIGHT, rgb(140, 60, 180));
        fb.setPaletteEntry(BLOCK, rgb(255, 210, 0));
        fb.setPaletteEntry(TEXT_INK, rgb(255, 255, 255));
        fb.clearFrameBuffer(SKY);

        if (step >= 3) drawFloor(fb); // step 3: the checkerboard floor
        if (step >= 5) zg.copper.install(fb, &.{SKY}, &copper_table, .{}); // step 5: rasters
    }

    pub fn update(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = dt;
        if (restage) {
            self.stage(zigos);
            restage = false;
        }
        if (step >= 4) { // step 4: the block moves
            self.block_x += self.block_dx;
            self.block_y += self.block_dy;
            if (self.block_x <= 0 or self.block_x >= W - BLOCK_SIZE) self.block_dx = -self.block_dx;
            if (self.block_y <= 28 or self.block_y >= FLOOR_Y - BLOCK_SIZE) self.block_dy = -self.block_dy;
        }
        if (step >= 5) {
            self.bar_y += self.bar_dy;
            if (self.bar_y <= 24 or self.bar_y >= FLOOR_Y - BAR_H) self.bar_dy = -self.bar_dy;
        }
        if (step >= 6) self.scroll_x = @mod(self.scroll_x + 2, TEXT_W); // step 6: the scroller
    }

    pub fn render(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = dt;
        if (step < 4) return; // steps 1-3 are static: stage() drew them already
        const fb = &zigos.lfbs[0];
        @memset(fb.fb[0 .. @as(usize, FLOOR_Y) * W], SKY); // wipe last frame's sky
        fillRect(fb, self.block_x, self.block_y, BLOCK_SIZE, BLOCK_SIZE, BLOCK);
        if (step >= 5) self.buildCopper(zg.copper.visible(fb, 0));

        if (step >= 6) {
            // Two copies of the text, one text-width apart, so the loop has no gap.
            const x = -self.scroll_x;
            zigos.printText(fb, TEXT, @intCast(x), 8, TEXT_INK, SKY);
            zigos.printText(fb, TEXT, @intCast(x + TEXT_W), 8, TEXT_INK, SKY);
        }
    }

    // One colour per visible line: a sky gradient, with a copper bar over it.
    fn buildCopper(self: *const Demo, lines: *[H]u32) void {
        for (lines, 0..) |*colour, i| {
            const d = @as(i32, @intCast(i)) - self.bar_y;
            if (d >= 0 and d < BAR_H) {
                const k: u8 = @intCast(if (d < BAR_H / 2) d + 1 else BAR_H - d); // 1..8..1
                colour.* = rgb(k * 31, k * 24, k * 8).toRGBA();
            } else {
                colour.* = rgb(0, @intCast(i / 4), @intCast(40 + i / 2)).toRGBA();
            }
        }
    }
};
