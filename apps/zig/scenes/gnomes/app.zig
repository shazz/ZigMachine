// --------------------------------------------------------------------------
// THE GNOMES GROUP "BB25": the frame loop. gnomes.zig carries the port notes;
// tables.zig the raster tables, text.zig the strings, draw.zig the font/art,
// tty.zig the cyan panel.
//
// Board cost: the logo, the boxes and SpongeBob are drawn once; per frame the
// copper's rainbow table is rolled (280 copies of precomputed words), the big
// band is cleared by one CHISEL fill and redrawn as ink runs, and the TTY draws
// one 8x8 glyph. No float anywhere.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const ZigOS = zg.ZigOS;
const Color = zg.Color;
const blit = zg.blit;
const copper = zg.copper;

const T = @import("tables.zig");
const text = @import("text.zig");
const draw = @import("draw.zig");
pub const tty = @import("tty.zig");

/// The intro's SNDH: David Whittaker's "Custodian", 6 subtunes, F1-F6 as the
/// screen's own message says. The SNDH archive's rip (docs/music/custodian.sndh,
/// = prototypes/sndh_lf/Whittaker_David/Custodian.sndh), NOT the intro's
/// embedded Grazey rip: the two write the same periods frame for frame, but the
/// intro's copy left every volume at 0 on subtune 3 (silent for 20 s here) and
/// on the first frames of the others.
pub const MUSIC = "custodian.sndh";

pub const PLANE = 0;

// --- geometry (physical rows of the 400x280 overscan plane) ----------------
pub const BAND_Y = 244;
pub const BAND_GLYPH = 32; // the 8x8 font at 4x
pub const BAND_ADV = 40;
const BAND_STEP = 2; // px a frame, rolling left
const BAND_SLOTS = (zg.PHYSICAL_WIDTH + BAND_ADV - 1) / BAND_ADV + 1;

// --- palette layout --------------------------------------------------------
pub const INK_BAND = 0; // rainbow; the copper rewrites it every line
pub const INK_BRICK = 1; // T2; boxes + big-band glyphs
pub const INK_LOGO = 2; // T1; the logo's fill rows
const INK_RIM = 3; // boot-table orange, static
pub const INK_STRIP = 4; // T1[15], static cyan, the TTY ink
const SPRITE_BASE = 16; // 18..31: SpongeBob's registers 2..15 (16/17 unused)

const K_F1: u32 = 0xE001;
const K_F6: u32 = 0xE006;
const K_ESC: u32 = 0xE012;
const DIR_BACK: u8 = 6;

// --- rasters: one copper on the overscan plane, three slots ----------------
const SLOTS = [3]u8{ INK_BAND, INK_BRICK, INK_LOGO };
var tables: [SLOTS.len]copper.Table = undefined;

fn fillTables() void {
    for (0..zg.PHYSICAL_HEIGHT) |y| {
        tables[0][y] = T.RAINBOW_RGBA[y % T.RAINBOW.len];
        tables[1][y] = T.st(T.T2[y % T.T2.len]);
        // T1 rides the logo's own rows: rows 12..35 = one full 24-word cycle.
        tables[2][y] = T.st(T.T1[(y + zg.PHYSICAL_HEIGHT - draw.LOGO_Y) % T.T1.len]);
    }
}

fn rollRainbow(rot: u16) void {
    for (0..zg.PHYSICAL_HEIGHT) |y|
        tables[0][y] = T.RAINBOW_RGBA[(y + rot) % T.RAINBOW.len];
}

// --- state: module level, so testapi.zig can read every word ---------------
pub var wants_quit: bool = false;
pub var frame: u32 = 0;
pub var rain_rot: u16 = 0;
pub var band_first: usize = 0; // the text index of the left-most glyph slot
pub var band_pos: i32 = 0; // scroll position within one glyph advance

fn drawBand(whole: blit.Dst) void {
    const band = whole.window(0, BAND_Y, zg.PHYSICAL_WIDTH, BAND_GLYPH);
    band.fill(0, 0, band.w, band.h, 0); // one CHISEL fill
    for (0..BAND_SLOTS) |i| {
        const ch = text.BIG_TEXT[(band_first + i) % text.BIG_TEXT.len];
        if (ch == ' ') continue;
        const x: i32 = @as(i32, @intCast(i * BAND_ADV)) - band_pos;
        draw.drawGlyph(band, ch, x, 0, 4, INK_BRICK);
    }
}

// --------------------------------------------------------------------------
pub const Demo = struct {
    pub fn init(self: *Demo, zigos: *ZigOS) void {
        _ = self;
        wants_quit = false;
        frame = 0;
        rain_rot = 0;
        band_first = 0;
        band_pos = 0;
        tty.reset();

        zg.requestSongTune(MUSIC, 1);
        zigos.setBackgroundColor(Color{ .r = 0, .g = 0, .b = 0, .a = 255 });

        const fb = &zigos.lfbs[PLANE];
        fb.is_enabled = true;
        fb.openBorders(.all);
        // The copper replaces openBorders()'s handler and flickers every line
        // itself, so the rainbow runs through all four open borders.
        copper.install(fb, &SLOTS, &tables, .{ .flicker = true });
        // AFTER install: install() seeds every table with the entry's current
        // colour, so the per-line rasters are written over them here.
        fillTables();
        fb.palette[INK_RIM] = T.st(0x760);
        fb.palette[INK_STRIP] = T.st(T.T1[15]); // 0x077, cyan
        for (T.SBOB_PAL, 2..) |w, i| fb.palette[SPRITE_BASE + i] = T.st(w);

        fb.clearFrameBuffer(0);
        // the static art, drawn once (the original kept these in screen
        // memory between VBLs too)
        const d = blit.Dst.plane(fb);
        draw.drawSprite(d, SPRITE_BASE, INK_BRICK);
        draw.drawBoxes(d, INK_BRICK);
        draw.drawLogo(d, INK_RIM, INK_LOGO);
    }

    pub fn update(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = self;
        _ = zigos;
        _ = dt; // frame-based: one step a rendered frame
        frame += 1;
        rain_rot += 1; // the rainbow rolls one word a frame
        if (rain_rot >= T.RAINBOW.len) rain_rot -= T.RAINBOW.len;
        rollRainbow(rain_rot);
        band_pos += BAND_STEP; // the big band: 2 px a frame, a slot every 40
        if (band_pos >= BAND_ADV) {
            band_pos -= BAND_ADV;
            band_first = (band_first + 1) % text.BIG_TEXT.len;
        }
        tty.step(); // one action per frame, exactly as the dis drives it
    }

    pub fn render(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = self;
        _ = dt;
        const whole = blit.Dst.plane(&zigos.lfbs[PLANE]);
        drawBand(whole);
        tty.render(whole, INK_STRIP);
    }

    /// F1-F6: the six "Custodian" subtunes, as the message says. Escape and
    /// the host's Back leave (declaring key() owns every key).
    pub fn key(self: *Demo, cp: u32) void {
        _ = self;
        if (cp >= K_F1 and cp <= K_F6) {
            zg.requestSongTune(MUSIC, @intCast(1 + (cp - K_F1)));
        } else if (cp == K_ESC) {
            wants_quit = true;
        }
    }

    pub fn input(self: *Demo, dir: u8) void {
        _ = self;
        if (dir == DIR_BACK) wants_quit = true;
    }

    pub fn pollCart(self: *Demo) i32 {
        _ = self;
        return if (wants_quit) -1 else 0;
    }
};
