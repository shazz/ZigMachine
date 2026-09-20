// The B.I.G. Demo, KEY 1 — Colorright, the third Psych-O-Screen.
//
// An ornate zigzag frame round a starfield, a TEX cube in the middle, a rainbow
// band sweeping up and down through all of it, and a COLORRIGHT BY TEX panel
// below. The CODEF remake has none of it; this is built from the real machine.
//
// THE SWEEP is the whole motion, and it is unlike the other four screens:
// nothing scrolls and no table shifts — the RASTER SPLIT LINE ITSELF MOVES.
// Timer B is loaded straight from a counter that walks 3 -> 180 -> 3, one line
// a frame: 177 lines each way, 354 frames, about 7.1 seconds a cycle. Wherever
// it stops, the HBL steps fifteen words from $1478A one per scanline into
// COLOUR 0. Fifteen, because `d3 = $E` counts the table — the band is 15 rows
// wide wherever it is, and the two split lines do not set its size.
//
// Measured against the capture before the code was read: the border carries a
// 15-row rainbow and nothing else, and its fifteen words are $1478A's fifteen
// in order. Colour 0 is the border, which is why a raster meant for the picture
// shows up out there at all.
//
// THE STARS ACCUMULATE. Not motion, not re-randomisation — the generator plots
// new ones and NOTHING ever erases. Two consecutive frames of the real demo
// share 5,656 stars with zero removed and 21 added; 400 frames later every one
// of the original 5,656 is still there and 4,203 more have joined. So the port
// keeps no star table and takes no step: it draws into the plane and never
// clears it, which is what the machine does.
//
// The placement is rejection-sampled and the three constants are visible in the
// bitmap: 3,023 of 3,023 stars at an EVEN x, x in 46..274, y in 23..175, pens
// 4..15 near-uniform and never 1, 2 or 3. `andi.l #$fe` / reject > $E7 / +$2C,
// reject > $98 / +$17, reject pen <= 3 — all three readable from the data.
//
// THE PANEL, display lines 200..239, is NOT in the 32,000-byte bitmap: it is
// drawn into the opened bottom border from another buffer. It is recovered from
// the capture, and it recovers exactly — it uses precisely the sixteen words of
// the palette at $147E4 and not one other colour. That palette had no known
// consumer; this is it.
//
// TWO THINGS ARE NOT HERE, both named rather than fudged:
//   * the SELECTOR at $14780. Thirteen dispatch arms write the band's colour to
//     thirteen different pens, one step per sweep cycle, so the colour walks
//     across the pen range over about 92 seconds. Only arm 0 (pen 0) and arm 1
//     (pen 4) have been read; eleven are unknown, so this drives pen 0 always.
//     That is right for the first seven seconds of every visit and wrong after.
//   * the star VALIDITY test at $14118. The rate of new stars falls as the
//     field fills, which is what an "is this pixel taken?" test would do, so
//     that is what is implemented — inferred from the rate, not read. It also
//     leaves one real anomaly unexplained: of the 116 even columns in 44..274,
//     exactly ONE never holds a star, x = 44, while x = 46 carries double the
//     mean.
const zg = @import("zigos");
const LogicalFB = zg.LogicalFB;
const D = @import("key1_data.zig");

const W: usize = 320;
const H: usize = 200;
const X0: usize = (zg.PHYSICAL_WIDTH - W) / 2; // 40
const Y0: usize = (zg.PHYSICAL_HEIGHT - H) / 2; // 40
const PANEL_W: usize = 384; // the capture's full width: 32 + 320 + 32
const PANEL_H: usize = 40;
const PANEL_X: usize = (zg.PHYSICAL_WIDTH - PANEL_W) / 2; // 8
const PANEL_Y: usize = Y0 + H; // the opened bottom border
const PANEL_PEN: u8 = 16; // the panel's own sixteen, above the picture's

/// New stars a frame. Measured directly on two consecutive frames of the real
/// demo, at one point on the fill curve.
const PLOTS: usize = 21;

const picture = @embedFile("../../assets/screens/big_demo/key1_screen.raw");
const panel = @embedFile("../../assets/screens/big_demo/key1_panel.raw");

/// The copper's table for palette entry 0, one colour per PHYSICAL row. Module
/// scope because the scene owns copper storage (libs/zig/effects/copper.zig).
var bar: [1]zg.copper.Table = undefined;

pub fn palette() [256]zg.Color {
    var p: [256]zg.Color = @splat(.{ .r = 0, .g = 0, .b = 0, .a = 255 });
    for (D.LIVE, 0..) |w, i| p[i] = colour(w);
    for (D.PANEL_PAL, 0..) |w, i| p[PANEL_PEN + i] = colour(w);
    return p;
}

fn colour(w: u16) zg.Color {
    return .{
        .r = @intCast((w >> 8 & 7) * 255 / 7),
        .g = @intCast((w >> 4 & 7) * 255 / 7),
        .b = @intCast((w & 7) * 255 / 7),
        .a = 255,
    };
}

pub const Key1 = struct {
    split: i32, // $147DE, the sweep counter — and Timer B itself
    down: bool, // $147E0
    seed: u32,

    pub fn enter(self: *Key1, fb: *LogicalFB) void {
        self.split = D.SWEEP_LO;
        self.down = true;
        self.seed = 0x14000;
        fb.setPalette(palette());
        // Pen 0 everywhere, so the side borders and the bands above and below
        // the picture all follow the sweep — which is what makes a raster meant
        // for the picture visible out in the border.
        fb.clearFrameBuffer(0);
        for (0..H) |y| {
            @memcpy(fb.fb[(Y0 + y) * zg.PHYSICAL_WIDTH + X0 ..][0..W], picture[y * W ..][0..W]);
        }
        for (0..PANEL_H) |r| {
            const src = panel[r * PANEL_W ..][0..PANEL_W];
            const dst = fb.fb[(PANEL_Y + r) * zg.PHYSICAL_WIDTH + PANEL_X ..][0..PANEL_W];
            for (src, dst) |s, *d| d.* = PANEL_PEN + s;
        }
        // One entry, every border open: the sides ARE open on this screen (the
        // capture is 384 px wide) and the band runs out into them.
        zg.copper.install(fb, &.{0}, &bar, .{ .flicker = true });
    }

    pub fn draw(self: *Key1, fb: *LogicalFB) void {
        const t = zg.copper.table(fb, 0);
        @memset(t, colour(D.LIVE[0]).toRGBA());
        const top: usize = @intCast(Y0 + @as(usize, @intCast(self.split)));
        for (D.RAMP, 0..) |w, i| {
            const row = top + i;
            if (row < t.len) t[row] = colour(w).toRGBA();
        }
        self.sweep();
        self.plot(fb);
    }

    /// $142EC: one line a frame, reversing at 180 and at 3.
    fn sweep(self: *Key1) void {
        if (self.down) {
            self.split += 1;
            if (self.split >= D.SWEEP_HI) self.down = false;
        } else {
            self.split -= 1;
            if (self.split <= D.SWEEP_LO) self.down = true;
        }
    }

    /// $14072: roll a position and a pen, reject out of range, reject a taken
    /// pixel, plot. Nothing is ever erased.
    fn plot(self: *Key1, fb: *LogicalFB) void {
        for (0..PLOTS) |_| {
            const x = D.STAR_X0 + (self.next() % ((D.STAR_X1 - D.STAR_X0) / 2 + 1)) * 2;
            const y = D.STAR_Y0 + self.next() % (D.STAR_Y1 - D.STAR_Y0 + 1);
            const pen: u8 = @intCast(4 + self.next() % 12);
            const p = &fb.fb[(Y0 + y) * zg.PHYSICAL_WIDTH + X0 + x];
            if (p.* != 0) continue; // the taken-pixel rejection, inferred
            p.* = pen;
        }
    }

    fn next(self: *Key1) usize {
        self.seed ^= self.seed << 13;
        self.seed ^= self.seed >> 17;
        self.seed ^= self.seed << 5;
        return self.seed;
    }
};

comptime {
    if (picture.len != W * H) @compileError("key1_screen.raw is not 320x200");
    if (panel.len != PANEL_W * PANEL_H) @compileError("key1_panel.raw is not 384x40");
    if (PANEL_Y + PANEL_H > zg.PHYSICAL_HEIGHT) @compileError("the panel runs off the plane");
    if (D.RAMP.len != 15) @compileError("the band is 15 words: d3 = $E counts them");
}
