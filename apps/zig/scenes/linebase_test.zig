// --------------------------------------------------------------------------
// LINE LIST TEST: the STE line list (HW 1.10.0, fpga/review/COPPER_LINEBASE.md): every line's source
// address (copper LBASE, the STE video counter), its fine scroll (REG HSCROLL, now honoured on
// overscan planes) and colour 0 come from a list zg.linelist rebuilds each frame; no HBL handler.
// Two phases of PHASE frames each, the second first:
//
//   A  plane 0 overscan, all four borders open (FLICK in the list), the CPU draws nothing:
//        lines   0..99   a sine wobble: rows scroll down the image, HSCROLL bends each line
//        lines 100..179  a line zoom: one image row stretched over several lines, breathing
//        lines 180..279  16-line bands, alternately flipped (an LBASE a line) and straight (one
//                        LBASE, the counter runs on by itself)
//        colour 0        a moving ST-legal raster through every border
//   B  plane 1, a 320x400 scroll plane whose window (FB_BASE) is static; its list flips rows
//      200..399 into it, where the CPU moves a bar: what the board's dirty-line planner must
//      redraw although the list and the window's rows never change (fpga/cycles/vdlist.h).
//
// The proof cart: apps/linebase_test_headless.mjs, fpga/tests/test_vdirty.py, the board sims.
// Integer maths only (fixtrig tables).
// --------------------------------------------------------------------------
const zg = @import("zigos");
const ZigOS = zg.ZigOS;
const LogicalFB = zg.LogicalFB;
const Color = zg.Color;
const ft = zg.fixtrig;

const ROWS: usize = zg.PHYSICAL_HEIGHT; // 280 raster lines, borders included
const VIS: usize = zg.HEIGHT; // 200
const IMG_W: u16 = 400;
const IMG_H: u16 = 560; // twice the raster: rows to scroll through
const B_W: u16 = 320;
const B_H: u16 = 400;
const INK: u8 = 65;
const BAR: u8 = 66;
const PHASE: u32 = 150;

const WOBBLE_STEP = ft.angle(0.09); // per line
const PHASE_STEP = ft.angle(0.045); // per frame
const ZOOM_STEP = ft.angle(0.03);

// ST colour words (nibble * 32 per channel, the 0..7 grid) for the colour-0 raster.
const bars = [_]u16{ 0x001, 0x002, 0x113, 0x224, 0x335, 0x446, 0x556, 0x667, 0x777, 0x666, 0x444, 0x333, 0x111, 0x000 };

var lines_a: [ROWS]zg.linelist.Line = undefined;
var lines_b: [VIS]zg.linelist.Line = undefined;

pub const Demo = struct {
    fc: u32 = 0,
    list_a: ?[]u32 = null,
    list_b: ?[]u32 = null,
    bar_y: u16 = 0,

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        const a: *LogicalFB = &zigos.lfbs[0];
        a.setOverscanScrollPlane(IMG_W, IMG_H);
        rainbow(a);
        paint(zigos, a, IMG_W, IMG_H);
        self.list_a = zg.linelist.install(a, ROWS, true);
        const b: *LogicalFB = &zigos.lfbs[1];
        b.setScrollPlane(B_W, B_H);
        rainbow(b);
        b.setPaletteEntry(0, .{ .r = 0, .g = 0, .b = 64, .a = 255 });
        b.setPaletteEntry(BAR, .{ .r = 255, .g = 255, .b = 255, .a = 255 });
        paint(zigos, b, B_W, B_H);
        self.list_b = zg.linelist.install(b, VIS, false);
    }

    pub fn update(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = dt;
        const in_b = (self.fc / PHASE) % 2 == 0;
        zigos.lfbs[0].is_enabled = !in_b;
        zigos.lfbs[1].is_enabled = in_b;
        self.fc +%= 1;
    }

    pub fn render(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = dt;
        if (zigos.lfbs[1].is_enabled) return self.renderB(&zigos.lfbs[1]);
        const fb: *LogicalFB = &zigos.lfbs[0];
        const l = self.list_a orelse return;
        const phase: ft.Angle = self.fc *% PHASE_STEP;
        for (&lines_a, 0..) |*ln, y| ln.* = lineA(fb, @intCast(y), self.fc, phase);
        _ = zg.linelist.build(l, &lines_a, .{ .plane = fb.id, .stride = IMG_W, .flicker = true }) catch {};
    }

    // The bar moves in rows 200..399, which only the list shows (flipped); the window is static.
    fn renderB(self: *Demo, fb: *LogicalFB) void {
        const l = self.list_b orelse return;
        fb.fillRect(0, 200 + @as(i32, self.bar_y), B_W, 8, 0); // last frame's bar, gone
        self.bar_y = @intCast((self.fc * 3) % (B_H - 200 - 8));
        fb.fillRect(0, 200 + @as(i32, self.bar_y), B_W, 8, BAR);
        for (&lines_b, 0..) |*ln, ly| ln.* = .{ .base = fb.lineAddr(0, @intCast(B_H - 1 - ly)) };
        _ = zg.linelist.build(l, &lines_b, .{ .plane = fb.id, .stride = B_W, .first_row = zg.VERTICAL_BORDERS_HEIGHT, .hscroll = false, .colour_entry = null }) catch {};
    }
};

// Line y's source row, fine scroll and colour 0 this frame (phase A).
fn lineA(fb: *const LogicalFB, y: u32, fc: u32, phase: ft.Angle) zg.linelist.Line {
    const colour = stColour(bars[(y / 3 + fc) % bars.len]);
    if (y < 100) { // wobble: rows drift down, each line bent by a travelling sine (1..31 px)
        const s = ft.sin(phase +% y *% WOBBLE_STEP);
        const hs: u16 = @intCast((16 * ft.ONE + 15 * s) >> 16);
        return .{ .base = fb.lineAddr(0, (y + fc) % (IMG_H - ROWS)), .hscroll = hs, .colour = colour };
    }
    if (y < 180) { // zoom: row = 200 + (y - 100) * k / 256, k breathing between 64 and 192
        const k: u32 = @intCast((128 * ft.ONE + 64 * ft.sin(fc *% ZOOM_STEP)) >> 16);
        return .{ .base = fb.lineAddr(0, 200 + ((y - 100) * k >> 8)), .colour = colour };
    }
    // 16-line bands, alternately flipped (a new LBASE every line, rows going up) and straight (one
    // LBASE at the band's top, the lines below run on by the stride: linelist emits none for them).
    const band = (y - 180) / 16;
    const k = (y - 180) % 16;
    const flipped = (band + fc / 32) % 2 == 1;
    return .{ .base = fb.lineAddr(0, 300 + band * 16 + (if (flipped) 15 - k else k)), .colour = colour };
}

fn stColour(w: u16) u32 {
    const c = Color{ .r = @intCast(((w >> 8) & 7) * 32), .g = @intCast(((w >> 4) & 7) * 32), .b = @intCast((w & 7) * 32), .a = 255 };
    return c.toRGBA();
}

// An XOR moire of the rainbow entries over index 0 (the raster shows through), with banners.
fn paint(zigos: *ZigOS, fb: *LogicalFB, w: u16, h: u16) void {
    var y: u16 = 0;
    while (y < h) : (y += 1) {
        var x: u16 = 0;
        while (x < w) : (x += 1) {
            const v: u8 = @intCast(((@as(u32, x) ^ @as(u32, y)) >> 2) & 0x3F);
            fb.setPixelValue(x, y, if (v & 0x8 != 0) 0 else v | 1);
        }
    }
    var row: u16 = 20;
    while (row < h) : (row += 60) zigos.printText(fb, "ZIGMACHINE * HW 1.10 LINE LIST *", 8, @intCast(row), INK, 0);
}

// A 63-step rainbow from integer ramps (init only), and the banners' ink.
fn rainbow(fb: *LogicalFB) void {
    var i: u8 = 1;
    while (i < 64) : (i += 1) {
        const f: u8 = (i % 11) * 23;
        fb.setPaletteEntry(i, switch (i / 11) {
            0 => .{ .r = 255, .g = f, .b = 0, .a = 255 },
            1 => .{ .r = 255 - f, .g = 255, .b = 0, .a = 255 },
            2 => .{ .r = 0, .g = 255, .b = f, .a = 255 },
            3 => .{ .r = 0, .g = 255 - f, .b = 255, .a = 255 },
            4 => .{ .r = f, .g = 0, .b = 255, .a = 255 },
            else => .{ .r = 255, .g = 0, .b = 255 - f, .a = 255 },
        });
    }
    fb.setPaletteEntry(INK, .{ .r = 245, .g = 245, .b = 255, .a = 255 });
}
