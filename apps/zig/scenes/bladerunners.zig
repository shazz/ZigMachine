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
const Color = zg.Color;
const RenderTarget = zg.RenderTarget;
const RenderBuffer = zg.RenderBuffer;

const Scrolltext = zg.Scrolltext;

const Console = zg.Console;

const Strip = @import("bladerunners/strip.zig").Strip;
const STRIDE = @import("bladerunners/strip.zig").STRIDE;

// --------------------------------------------------------------------------
// Constants
// --------------------------------------------------------------------------
const HEIGHT: u16 = zg.HEIGHT;
const WIDTH: u16 = zg.WIDTH;

// music — the screen's own tune, played by its own 68000 (docs/music/).
// David Whittaker, "Rampage" (1988).
const MUSIC = "rampage.sndh";

// scrolltext
pub const NB_FONTS: u8 = 11;
const fonts_b = @embedFile("../assets/screens/bladerunners/fonts_pal.raw");
const SCROLL_TEXT = "      WELCOME TO 'DUNGEON MASTER' -- CRACKED BY THE cdefghijkl -- THIS GAME IS CRACKED FOR  THE BLADE RUNNERS  - THE ULTIMATE CRACKER CREW...HELLO BOSS,TEX,CSS,TNT-CREW,MMC,BXC,TSUNOO,1001-CREW,AND OF COURSE YOU......DUNGEON MASTER WAS A VERY GOOD PROTECTED GAME THAT TOOK A LONG TIME TO CRACK. SO IF YOU ARE REQUESTED TO PUT IN THE DUNGEON MASTER DISK JUST IGNORE THAT MESSAGE AND CONTINUE (PRESSING THE RETURN KEY) YOUR GAME...THANKS TO MMC FOR THE ORIGINAL THAT WAS AFTERWARDS NEARLY UNREADABLE! TO CHANGE THE TUNE TOGGLE WITH F1/F2 SO YOU WILL LISTEN TO BOTH OF THE RAMPAGE MUSIC PIECES AGAIN COMPOSED BY WHITTIE-BABY!...";
const SCROLL_CHAR_WIDTH = 32; 
const SCROLL_CHAR_HEIGHT = 32;
const SCROLL_SPEED = 2;
const SCROLL_CHARS = " ! #$%&'()*+,-./0123456789:;<=>? ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]ˆ_`abcdefghijklmnopqrstuvwxyz";

// palettes
const font_pal = convertU8ArraytoColors(@embedFile("../assets/screens/bladerunners/fonts_pal.dat"));

// rasters
// As RGBA words (the ics.zig fix): a [256]Color is byte-aligned in the data
// segment, so the HBL handlers' one-word read of an entry was a misaligned load,
// a ~700-cycle trap on ZIGGY, 600 a frame over the three handlers.
fn rgbaTable(comptime pal: [256]Color) [256]u32 {
    var out: [256]u32 = undefined;
    for (pal, 0..) |c, i| out[i] = c.toRGBA();
    return out;
}
const font_rasters_rgba = rgbaTable(convertU8ArraytoColors(@embedFile("../assets/screens/bladerunners/raster_font_pal.dat")));
const back_rasters_rgba = rgbaTable(convertU8ArraytoColors(@embedFile("../assets/screens/bladerunners/raster_back_pal.dat")));


// --------------------------------------------------------------------------
// Variables
// --------------------------------------------------------------------------
var raster_index: u8 = 0;
var tick_counter: u8 = 0;

// --------------------------------------------------------------------------
// Rasters: ONE colour per line, border to border
// --------------------------------------------------------------------------
// On the ST the background raster is colour 0, one register changed per
// scanline, and the border is painted from that same register. Here the border
// is BACKGROUND (the global HBL, PHYSICAL lines 0..279) and the picture is the
// plane's entry 0 (its own HBL, LOGICAL lines 0..199 = physical 40..239), so
// both index the table with the same logical line and the same raster_index.
// The border used to read (line + 12) against the picture's (line - 40), a
// 52-line shift, one table period plus one line: the "three colours on one
// line" Matt saw on the board (2026-10-23). And the border is painted BEFORE
// frame() runs, so the raster's tick now happens here, at line 0 (the ST's
// VBL), not in update(): border and picture see the same index on every frame.
fn handler_hbl(zigos: *ZigOS, line: u16) void {
    if (line == 0) {
        tick_counter += 1;
        if (tick_counter == 2) {
            raster_index +%= 1;
            tick_counter = 0;
        }
    }
    if (line >= 40 and line < 240) {
        zigos.setBackgroundColor(Color.fromRGBA(back_rasters_rgba[(line - 40 + raster_index) % 255]));
    } else if (line == 0 or line == 240) {
        // the top and bottom bands stay transparent (the tube): one write each
        zigos.setBackgroundColor(Color{ .r = 0, .g = 0, .b = 0, .a = 0 });
    }
}

// The one plane: entry 0 is the background raster (was a second plane of
// nothing but colour 0, 1.09 Mc of FRESCO a frame), entry 1 the font raster.
fn handler_scroller(fb: *LogicalFB, zigos: *ZigOS, line: u16, col: u16) void {
    if (line < 200) {
        fb.palette[0] = back_rasters_rgba[(line + raster_index) % 255];
        fb.palette[1] = font_rasters_rgba[line];
    }
    _ = zigos;
    _ = col;
}

pub const Demo = struct {
    name: u8 = 0,
    scrolltext: Scrolltext(NB_FONTS) = undefined,
    offset_table: [320]u16 = undefined,
    scroller_offset: u16 = 0,
    // The letters write into a scratch target nobody shows: only their
    // positions are read, by the strip (strip.zig).
    scratch_buffer: [SCROLL_CHAR_WIDTH * SCROLL_CHAR_HEIGHT]u8 align(4) = undefined,
    scratch_render_buffer: RenderBuffer = undefined,
    strip: Strip = .{},
    blitter: zg.Blitter = .{},

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        Console.log("Demo init", .{});

        // Nothing happens until the user turns sound on — the request just waits.
        zg.requestSong(MUSIC);
        self.blitter.init();

        // ONE plane (plane 1, the scroller's): plane 0 stays off
        const fb: *LogicalFB = &zigos.lfbs[1];
        fb.is_enabled = true;
        fb.setPalette(font_pal);
        fb.setFrameBufferHBLHandler(0, handler_scroller);
        zigos.setHBLHandler(handler_hbl);

        // Init-time float: the sine wave table, built once.
        var i: usize = 0;
        var counter: f32 = 0;
        while (i < 320) : (i += 1) {
            const f_sin: f32 = @abs(@sin(counter)) * 14;
            self.offset_table[i] = @as(u16, @intFromFloat(f_sin));
            counter += 0.04;
        }

        self.scratch_render_buffer = .{ .buffer = &self.scratch_buffer, .width = SCROLL_CHAR_WIDTH, .height = SCROLL_CHAR_HEIGHT };
        const target: RenderTarget = .{ .render_buffer = &self.scratch_render_buffer };
        self.scrolltext = Scrolltext(NB_FONTS).init(target, fonts_b, SCROLL_CHARS, SCROLL_CHAR_WIDTH, SCROLL_CHAR_HEIGHT, SCROLL_TEXT, SCROLL_SPEED, 0, null, null, null);
        self.strip.fill(&self.scrolltext);
        self.scroller_offset = 0;

        Console.log("demo init done!", .{});
    }

    pub fn update(self: *Demo, zigos: *ZigOS, elapsed_time: f32) void {
        self.scrolltext.update();
        self.strip.advance(&self.scrolltext, SCROLL_SPEED);

        self.scroller_offset += 1;
        if (self.scroller_offset == self.offset_table.len) self.scroller_offset = 0;

        _ = zigos;
        _ = elapsed_time;
    }

    pub fn render(self: *Demo, zigos: *ZigOS, elapsed_time: f32) void {
        // The strip repeats every 32 rows, shifted up by the sine: CHISEL copies
        // its window from the cart-RAM ring, so no row needs a CPU copy (and the
        // segments tile the whole plane, so the plane is not cleared first).
        const fb = &zigos.lfbs[1];
        const sine_offset: u16 = self.offset_table[self.scroller_offset];
        const src: []const u8 = &self.strip.ring;
        const sx = self.strip.windowX();
        self.blitter.blitImage(fb, 0, 0, src, STRIDE, sx, sine_offset, WIDTH, SCROLL_CHAR_HEIGHT - sine_offset, null);
        var k: u16 = 1;
        while (k <= 6) : (k += 1) {
            const y: u16 = k * 32 - sine_offset;
            const h: u16 = @min(SCROLL_CHAR_HEIGHT, 200 - y);
            self.blitter.blitImage(fb, 0, @intCast(y), src, STRIDE, sx, 0, WIDTH, h, null);
        }
        _ = elapsed_time;
    }
};
