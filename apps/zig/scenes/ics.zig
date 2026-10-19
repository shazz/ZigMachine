// --------------------------------------------------------------------------
// Imports
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const readU16Array = zg.readU16Array;
const readI16Array = zg.readI16Array;
const convertU8ArraytoColors = zg.convertU8ArraytoColors;

const ZigOS = zg.ZigOS;
const LogicalFB = zg.LogicalFB;
const RenderTarget = zg.RenderTarget;
const RenderBuffer = zg.RenderBuffer;
const Color = zg.Color;

const Scrolltext = zg.Scrolltext;
const Sprite = zg.Sprite;
const Background = zg.Background;

const Console = zg.Console;

// --------------------------------------------------------------------------
// Constants
// --------------------------------------------------------------------------
const HEIGHT: u16 = zg.HEIGHT;
const WIDTH: u16 = zg.WIDTH;

// music — the screen's own tune, played by its own 68000 (docs/music/).
// David Whittaker, "Leatherneck" (1988). Carries 3 subtunes; the player
// takes the image's own default.
const MUSIC = "leatherneck.sndh";

// scrolltext

// The font's ink is index 1; on the merged plane 1..6 are the grid's, so the ink
// becomes RASTER_IDX here, at compile time (the strip then holds 0 / RASTER_IDX).
const RASTER_IDX = 7;
const fonts_b: [24064]u8 = blk: {
    const raw = @embedFile("../assets/screens/ics/font_noics_pal.raw");
    @setEvalBranchQuota(raw.len * 4);
    var out: [raw.len]u8 = undefined;
    for (raw, 0..) |v, i| out[i] = if (v == 0) 0 else RASTER_IDX;
    break :blk out;
};
const SCROLL_TEXT = "    ICS PRESENTS YOU:         BUMPY'S     GAME CRACKED BY THE THREAT        ORIGINAL BY SLASH OF FRANCE       THIS INTRO WAS CODED, DESIGNED FOR I.C.S. BY  -EL PISTOLERO-..... (MANY THANKS!)     JUST AFTER THIS LITTLE INTRO YOU CAN READ A MESSAGE SENT TO SLASH BY SLEDGE, I THINK YOU'LL BE SURPRISED...           I WANT TO SAID A BIG HI TO  'NUKE' OUR NEW CRACKER, HE LIVES IN FRANCE LIKE A LOT OF MEMBERS OF ICS.      BIG HELLO TO SKINHEAD FROM GERMANY WHO GIVE US VERY HOT ORIGINALS (LIKE STONE AGE).      BIG HI TO SLASH AND BELGARION WHO ARE VERY GOOD/COOL GUYS!!!      AND OF COURSE I DON'T FORGET MR.FLY.        GREETINGS TO: SCSI, CYNIX, POMPEY PIRATES, DANNY FROM SINGAPORE, FUZION, THE REPLICANTS, AND YOU, IF YOU WANT!!!        WE LOOOKING FOR SUPPLIERS ALL OVER THE WORLD, IF YOU ARE INTRESTED WRITE TO THE P.O. BOX OR CALL ONE OF OUR BOARD.       THIS ALL FOR THIS TIME, SEE YOU SOON....              ";
const SCROLL_CHAR_WIDTH = 16; 
const SCROLL_CHAR_HEIGHT = 16;
const SCROLL_SPEED = 3;
const SCROLL_CHARS = " ! #$%&'()*+,-./0123456789:;<=>? ABCDEFGHIJKLMNOPQRSTUVWXYZ";
pub const NB_FONTS: u8 = WIDTH / SCROLL_CHAR_WIDTH + 1;
const g_y_offset_table_b = readI16Array(@embedFile("../assets/screens/ics/scroller_sin.dat"));

// palettes
const logo_pal = convertU8ArraytoColors(@embedFile("../assets/screens/ics/ics_logo_pal.dat"));
const grid_pal = convertU8ArraytoColors(@embedFile("../assets/screens/ics/grid_large_pal.dat"));

// rasters
// As RGBA words: a [256]Color is byte-aligned in the data segment, so reading one
// entry as a word is a misaligned load (a trap on ZIGGY) on every HBL line.
const rasters_rgba: [256]u32 = blk: {
    const colors = convertU8ArraytoColors(@embedFile("../assets/screens/ics/raster_pal.dat"));
    var out: [256]u32 = undefined;
    for (colors, 0..) |c, i| out[i] = c.toRGBA();
    break :blk out;
};

// logo
const logo_b = @embedFile("../assets/screens/ics/ics_logo.raw");
const grid_b = @embedFile("../assets/screens/ics/grid_large.raw");

// --------------------------------------------------------------------------
// One plane, not three. The cart stacked scroller (plane 0) < grid (1) < logo (2);
// FRESCO paints every enabled plane (~1.09 Mc each), so the three are merged:
//   rows 0..LOGO_TOP-1: the grid window, keyed over the scroller (grid index 0 is
//                       transparent, exactly as on plane 1);
//   rows LOGO_TOP..199: the logo band, opaque on plane 2 (black + the logo), drawn once.
// Palette: 1..6 the grid's, RASTER_IDX the scroller's raster, LOGO_BLACK the band's
// black; the logo's other colours are the grid's same RGBA (checked at compile time).
// --------------------------------------------------------------------------
const LOGO_TOP = HEIGHT - 37; // plane 2 was opaque from this row down
const LOGO_BLACK = 8;
const LOGO_W = 137;
const LOGO_X = WIDTH / 2 - 68;
const LOGO_Y = HEIGHT - 29;
const logo_map: [8]u8 = blk: {
    var m: [8]u8 = undefined;
    for (0..8) |k| {
        const c = logo_pal[k];
        m[k] = LOGO_BLACK;
        for (1..7) |j| {
            const g = grid_pal[j];
            if (g.r == c.r and g.g == c.g and g.b == c.b and g.a == c.a) m[k] = j;
        }
        if (m[k] == LOGO_BLACK and !(c.r == 0 and c.g == 0 and c.b == 0 and c.a == 255))
            @compileError("ics: a logo colour is neither a grid colour nor black");
    }
    break :blk m;
};

// --------------------------------------------------------------------------
// Variables
// --------------------------------------------------------------------------

// The scroller's letters are drawn into this strip first. The wave moves a letter
// at most 39 rows down (the sine table's peak), so nothing below row 54 is ever
// drawn: the strip is 56 rows, not the 200 of the plane. It lives in the first rows
// of plane 1, which is never enabled (FRESCO never paints it), so CHISEL can clear it.
const TEXT_ROWS = 56;
const ROW_WORDS = WIDTH / 4;
const STRIP_PLANE = 1;
var strip: [*]const u32 = undefined;
var strip_buffer: RenderBuffer = .{ .buffer = undefined, .width = WIDTH, .height = TEXT_ROWS };
// The plane's first row shows scroll row 32, and scroll row r is every non-zero
// pixel of strip rows r%16, r%16+16, ... r merged (the 'copy 9 times' pass), the
// topmost winning. So plane row k < 16 is the chain k, k+16, k+32 and every row
// from 16 down is the full chain of k%16 (strip rows past 55 are empty): 32 rows
// made, then the last 16 repeat down the plane.
const SCROLL_ROWS = 32;
var scroll_img: [SCROLL_ROWS * ROW_WORDS]u32 = undefined;
// The grid window's offset, from the cart's own wobble (always -32..-1 each way).
var grid_dx: i32 = -32;
var grid_dy: i32 = -32;
const GRID_W = 384;

/// 0xFF in every byte of `w` that is not 0.
inline fn opaqueBytes(w: u32) u32 {
    const high = (((w & 0x7f7f7f7f) +% 0x7f7f7f7f) | w) & 0x80808080;
    return (high >> 7) * 0xFF;
}

/// `acc` with strip row `row`'s word `i` filling its transparent pixels.
inline fn under(acc: u32, row: usize, i: usize) u32 {
    return acc | (strip[row * ROW_WORDS + i] & ~opaqueBytes(acc));
}

/// scroll_img rows b (chain b, b+16, b+32) and 16+b (the chain on to row 55).
fn buildScroll() void {
    for (0..16) |b| {
        for (0..ROW_WORDS) |i| {
            var acc = under(under(strip[b * ROW_WORDS + i], b + 16, i), b + 32, i);
            scroll_img[b * ROW_WORDS + i] = acc;
            if (b + 48 < TEXT_ROWS) acc = under(acc, b + 48, i);
            scroll_img[(16 + b) * ROW_WORDS + i] = acc;
        }
    }
}

// --------------------------------------------------------------------------
// Demo
// --------------------------------------------------------------------------
fn handler_scroller(fb: *LogicalFB, zigos: *ZigOS, line: u16, col: u16) void {
    // LOGICAL lines 0..199. The raster colours the scroller's ink; from LOGO_TOP down
    // the band covers it (the old plane blanked the entry at 165, under the logo).
    if (line < LOGO_TOP) fb.palette[RASTER_IDX] = rasters_rgba[line];
    _ = zigos;
    _ = col;
}

pub const Demo = struct {
    name: u8 = 0,
    scrolltext: Scrolltext(NB_FONTS) = undefined,
    scroller_target: RenderTarget = undefined,
    blitter: zg.Blitter = .{},
    sin_counter: zg.fixtrig.Angle = 0, // u32 turns, wraps exactly at 2 PI

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        Console.log("Demo init", .{});

        // Nothing happens until the user turns sound on — the request just waits.
        zg.requestSong(MUSIC);
        self.blitter.init();

        const fb: *LogicalFB = &zigos.lfbs[0];
        fb.is_enabled = true;
        for (1..7) |j| fb.setPaletteEntry(@intCast(j), grid_pal[j]);
        fb.setPaletteEntry(0, Color{ .r = 0, .g = 0, .b = 0, .a = 0 });
        fb.setPaletteEntry(LOGO_BLACK, Color{ .r = 0, .g = 0, .b = 0, .a = 255 });
        fb.setFrameBufferHBLHandler(0, handler_scroller);

        const sfb = &zigos.lfbs[STRIP_PLANE];
        strip = @ptrCast(@alignCast(sfb.fb));
        strip_buffer.buffer = sfb.fb[0 .. WIDTH * TEXT_ROWS];
        self.blitter.fill(sfb, 0, 0, WIDTH, TEXT_ROWS, 0);
        self.scroller_target = .{ .render_buffer = &strip_buffer };
        self.scrolltext = Scrolltext(NB_FONTS).init(self.scroller_target, &fonts_b, SCROLL_CHARS, SCROLL_CHAR_WIDTH, SCROLL_CHAR_HEIGHT, SCROLL_TEXT, SCROLL_SPEED, 0, null, &g_y_offset_table_b, false);

        // The logo band never changes: drawn once (what the logo misses is its black).
        fb.fillRect(0, LOGO_TOP, WIDTH, HEIGHT - LOGO_TOP, LOGO_BLACK);
        for (0..HEIGHT - LOGO_Y) |r| {
            for (0..LOGO_W) |c| fb.fb[(LOGO_Y + r) * WIDTH + LOGO_X + c] = logo_map[logo_b[r * LOGO_W + c]];
        }

        self.sin_counter = 0;
        Console.log("demo init done!", .{});
    }

    pub fn update(self: *Demo, zigos: *ZigOS, elapsed_time: f32) void {
        self.scrolltext.update();

        // sin/cos(-counter) * 32 * 3.2, truncated: 102.4 in Q16.16 is 6710886
        const neg = 0 -% self.sin_counter;
        const f_sin: i16 = @intCast(@divTrunc(@as(i64, zg.fixtrig.sin(neg)) * 6710886, 1 << 32));
        const f_cos: i16 = @intCast(@divTrunc(@as(i64, zg.fixtrig.cos(neg)) * 6710886, 1 << 32));
        grid_dx = -32 + @mod(f_sin, 32);
        grid_dy = -32 + @mod(f_cos, 32);

        self.sin_counter +%= zg.fixtrig.angle(0.034);
        _ = zigos;
        _ = elapsed_time;
    }

    pub fn render(self: *Demo, zigos: *ZigOS, elapsed_time: f32) void {
        self.blitter.fill(&zigos.lfbs[STRIP_PLANE], 0, 0, WIDTH, TEXT_ROWS, 0); // CHISEL, not a memset
        self.scrolltext.render();
        self.renderPlane(&zigos.lfbs[0]);
        _ = elapsed_time;
    }

    /// Rows 0..LOGO_TOP-1: the scroller picture by CHISEL (32 rows, then its last
    /// 16 down the plane), then the grid window keyed over it. The grid source
    /// starts at any byte: the blitter reads it, never a misaligned CPU load (each
    /// one traps and is emulated on ZIGGY: that made the board 2x slower than its model).
    fn renderPlane(self: *Demo, fb: *LogicalFB) void {
        buildScroll();
        const img: []const u8 = std.mem.sliceAsBytes(&scroll_img);
        self.blitter.blitImage(fb, 0, 0, img, WIDTH, 0, 0, WIDTH, SCROLL_ROWS, null);
        var y: u16 = SCROLL_ROWS;
        while (y < LOGO_TOP) : (y += 16) {
            self.blitter.blitImage(fb, 0, @intCast(y), img, WIDTH, 0, 16, WIDTH, @min(16, LOGO_TOP - y), null);
        }
        const x0: u16 = @intCast(-grid_dx);
        const y0: u16 = @intCast(-grid_dy);
        self.blitter.blitImage(fb, 0, 0, grid_b, GRID_W, x0, y0, WIDTH, LOGO_TOP, 0);
    }
};

