// --------------------------------------------------------------------------
// tutorial.zig: "your first screen", the Zig version of docs/TUTORIAL.md (step 7).
//
// A sky with a copper bar, a bouncing block, a checkerboard floor, a scroller
// and SNDH music. Zig scenes get ZigOS: planes, palettes, the copper helper,
// the 8x8 system font and the song request are library calls here, where the C
// and Rust versions (apps/c/scenes/tutorial.c, apps/rust/scenes/tutorial.rs)
// poke the sealed ABI by hand.
//
// Build: sh ./build.sh (or zig build -Drelease=true -Dwasm)
// Run:   docs/index.html?demo=demo-tutorial.wasm, or TUTORIAL in the menu
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

// The copper's per-line colours for SKY. Module scope and owned by the scene:
// an HBL handler gets no pointer to your Demo.
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

pub const Demo = struct {
    block_x: i32,
    block_y: i32,
    block_dx: i32,
    block_dy: i32,
    bar_y: i32,
    bar_dy: i32,
    scroll_x: i32,

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        // A cart's Demo is never built from field defaults: set every field here.
        self.block_x = 40;
        self.block_y = 40;
        self.block_dx = 2;
        self.block_dy = 1;
        self.bar_y = 24;
        self.bar_dy = 2;
        self.scroll_x = 0;

        zg.requestSong(MUSIC);

        zigos.setBackgroundColor(rgb(0, 0, 0));

        const fb = &zigos.lfbs[0];
        fb.is_enabled = true;
        fb.setPaletteEntry(SKY, rgb(0, 0, 40));
        fb.setPaletteEntry(FLOOR_DARK, rgb(60, 20, 90));
        fb.setPaletteEntry(FLOOR_LIGHT, rgb(140, 60, 180));
        fb.setPaletteEntry(BLOCK, rgb(255, 210, 0));
        fb.setPaletteEntry(TEXT_INK, rgb(255, 255, 255));
        fb.clearFrameBuffer(SKY);
        drawFloor(fb);

        // One HBL on plane 0 that rewrites SKY before every line.
        zg.copper.install(fb, &.{SKY}, &copper_table, .{});
    }

    pub fn update(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = zigos;
        _ = dt;
        self.block_x += self.block_dx;
        self.block_y += self.block_dy;
        if (self.block_x <= 0 or self.block_x >= W - BLOCK_SIZE) self.block_dx = -self.block_dx;
        if (self.block_y <= 28 or self.block_y >= FLOOR_Y - BLOCK_SIZE) self.block_dy = -self.block_dy;

        self.bar_y += self.bar_dy;
        if (self.bar_y <= 24 or self.bar_y >= FLOOR_Y - BAR_H) self.bar_dy = -self.bar_dy;

        self.scroll_x = @mod(self.scroll_x + 2, TEXT_W);
    }

    pub fn render(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = dt;
        const fb = &zigos.lfbs[0];
        @memset(fb.fb[0 .. @as(usize, FLOOR_Y) * W], SKY); // wipe last frame's sky
        fillRect(fb, self.block_x, self.block_y, BLOCK_SIZE, BLOCK_SIZE, BLOCK);
        self.buildCopper(zg.copper.visible(fb, 0));

        // Two copies of the text, one text-width apart, so the loop has no gap.
        const x = -self.scroll_x;
        zigos.printText(fb, TEXT, @intCast(x), 8, TEXT_INK, SKY);
        zigos.printText(fb, TEXT, @intCast(x + TEXT_W), 8, TEXT_INK, SKY);
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
