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
const Background = zg.Background;

const Console = zg.Console;

// --------------------------------------------------------------------------
// Constants
// --------------------------------------------------------------------------
const HEIGHT: u16 = zg.HEIGHT;
const WIDTH: u16 = zg.WIDTH;

// music — the screen's own tune, played by its own 68000 (docs/music/).
// David Whittaker, "Renegade" (1987) — the same tune DELTA FORCE plays;
// the two screens share it deliberately.
const MUSIC = "renegade.sndh";

// scrolltext
pub const NB_FONTS: u8 = 11;
const fonts_b = @embedFile("../assets/screens/df2/fonts.raw");
const SCROLL_TEXT = "               JINXSTER - CRACKED IN A WHOLE NIGHT BY CHAOS, INC. OF THE DELTAFORCE CRACKING GROUP! THIS VERSION RUNS IN ANY PATH! THIS INTRO WAS DESIGNED, CREATED, AND PROGRAMMED BY CHAOS, INC. GREETINGS GO TO : 42-CREW (HEY MARTIN, STILL TRYING TO CRACK DUNGEON MASTER?), TEX (WE ARE WAITING FOR YOUR B.I.G. DEMO!!), CSS (WHERE ARE YOU?!), PHIL/UK, DIV D, MR. ATARI, KILLER, B.O.S.S., DMA (NOTHING HEARD OF YOU GUYS! YOU OK?), TSUNOO, HCC.  INTERNAL GREETINGS TO : JOE COOL, QUESTLORD, NEW MODE, GREEN BERET CRACKER, AND ALL THE OTHER MEMBERS OF THE UNION!  YEP, YOU GOT IT, WE'RE AT THE END OF THE SCROLL............ C YA!!   ";
const SCROLL_CHAR_WIDTH = 32; 
const SCROLL_CHAR_HEIGHT = 30;
const SCROLL_SPEED = 4;
const SCROLL_CHARS = " ! #$%&'()*+,-./0123456789:;<=>? ABCDEFGHIJKLMNOPQRSTUVWXYZ";
const SCROLL_INTERSPACE = 3;

// palettes
const font_pal = convertU8ArraytoColors(@embedFile("../assets/screens/df2/fonts_pal.dat"));
const rasterbars_pal = convertU8ArraytoColors(@embedFile("../assets/screens/df2/rasterbars_pal.dat"));

// rasters
const scroll_rasters_b = convertU8ArraytoColors(@embedFile("../assets/screens/df2/scrollrasters.dat"));

// The background ramp: ten palette indices ACROSS (rasterbars.png is 10x1),
// repeated over every row and slid one pixel per frame. See the note above
// handler_scroller: this one is pixels by nature, not a scanline raster.
const rasterbars_b = @embedFile("../assets/screens/df2/rasterbars.raw");
const BAR_PERIOD: usize = rasterbars_b.len;
comptime {
    if (WIDTH % BAR_PERIOD != 0) @compileError("the background ramp assumes WIDTH is a multiple of BAR_PERIOD");
}

// One band = a line of the font plus the gap under it; the scroller's off-screen
// buffer holds two of them, so a read at any offset inside the first band still
// has a whole band's worth of pixels ahead of it.
const BAND_ROWS: u16 = SCROLL_CHAR_HEIGHT + SCROLL_INTERSPACE;
const SCROLLER_ROWS: u16 = BAND_ROWS * 2;

// --------------------------------------------------------------------------
// Variables
// --------------------------------------------------------------------------


// --------------------------------------------------------------------------
// Demo
// --------------------------------------------------------------------------
// The blue background is NOT a scanline raster and cannot be made into one:
// rasterbars.png is 10x1 (ten colours ACROSS), and the screen draws them as a
// 10-pixel VERTICAL ramp repeated over the row, sliding one pixel left per
// frame — the CODEF original's `bluerasterback.png` scrolled horizontally
// (x -= 5). A colour register changed per scanline paints a HORIZONTAL bar, so
// an HBL cannot produce this. The 2023 attempt that sat commented out here
// indexed a per-COLUMN callback (`rasters_b[col % 10]`) the machine has never
// had — `col` is the column the handler was REGISTERED at, constant for every
// line — and referenced an asset (rasters.dat) the scene never loads, so it
// could not even compile. It is deleted rather than revived.
// The scroller's rasters below, by contrast, ARE real: one palette write per
// scanline from the plane's HBL.

fn handler_scroller(fb: *LogicalFB, zigos: *ZigOS, line: u16, col: u16) void {
    const back_color: Color = Color{ .r = 0, .g = 0, .b = 0, .a = 0 };

    // Per-plane HBL (medium-res plane too fires on logical lines): sealed machine fires on
    // LOGICAL lines 0..199 (was physical 40..239), so drop the +40.
    if (line > 0 and line < 200 ) {
        fb.setPaletteEntry(1, scroll_rasters_b[line]);
    }
    if (line == 200) {
        fb.setPaletteEntry(1, back_color);
    }

    _ = zigos;
    _ = col;
}

// The ramp row for each of the BAR_PERIOD slide positions (WIDTH is a multiple
// of BAR_PERIOD): rasterbars_b[(frame + x) % BAR_PERIOD], built at compile time.
const ramp_rows: [BAR_PERIOD][WIDTH]u8 = blk: {
    @setEvalBranchQuota(100000);
    var t: [BAR_PERIOD][WIDTH]u8 = undefined;
    for (&t, 0..) |*r, f| for (r, 0..) |*px, x| {
        px.* = rasterbars_b[(f + x) % BAR_PERIOD];
    };
    break :blk t;
};

var scroller_owned: ?*[WIDTH * SCROLLER_ROWS]u8 = null;

/// The scroller's off-screen buffer, from zg.mem once per cart load.
fn scrollerBuffer() *[WIDTH * SCROLLER_ROWS]u8 {
    if (scroller_owned) |b| return b;
    // u32 elements so the buffer is word-aligned for the word clear in render().
    const words = zg.mem.mustAlloc(u32, WIDTH * SCROLLER_ROWS / 4);
    const b: *[WIDTH * SCROLLER_ROWS]u8 = @ptrCast(words.ptr);
    scroller_owned = b;
    return b;
}

pub const Demo = struct {
  
    name: u8 = 0,
    frame_counter: u32 = 0,
    scrolltext: Scrolltext(NB_FONTS) = undefined,
    scroller_target: RenderTarget = undefined,
    scroller_pos_y: u16 = SCROLL_CHAR_HEIGHT - 1,
    // The scroller's off-screen buffer. It used to be a stack local in init(),
    // so scroller_target held a pointer to a dead frame (the bug bladerunners.zig
    // was fixed for), and it was 2 rows SHORT of the height it declared: render
    // reads rows scroller_pos_y..scroller_pos_y+32, i.e. up to row 65 at
    // scroller_pos_y = 32. Sized to the declared height, it lives as long as the
    // cart: it comes from the RAM arena (scrollerBuffer), where as a field it was
    // 26 KB of zeros written into the cart binary.
    scroller_buffer: *[WIDTH * SCROLLER_ROWS]u8,
    scroller_render_buffer: RenderBuffer = undefined,
    blitter: zg.Blitter = .{},

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        Console.log("Demo init", .{});

        // Nothing happens until the user turns sound on — the request just waits.
        zg.requestSong(MUSIC);

        // The background plane: no HBL, its colours are the ramp drawn as pixels.
        var fb: *LogicalFB = &zigos.lfbs[0];
        fb.is_enabled = true;
        fb.setPalette(rasterbars_pal);

        fb = &zigos.lfbs[1];
        fb.is_enabled = true; 
        fb.setPalette(font_pal);

        // The scroller's ink colour, a real raster: one palette write per scanline.
        fb.setFrameBufferHBLHandler(0, handler_scroller);

        self.blitter.init();
        self.scroller_buffer = scrollerBuffer();
        @memset(self.scroller_buffer, 0);
        self.scroller_render_buffer = .{ .buffer = self.scroller_buffer, .width = WIDTH, .height = SCROLLER_ROWS };
        self.scroller_target = .{ .render_buffer = &self.scroller_render_buffer };
        self.scroller_pos_y = (SCROLL_CHAR_HEIGHT - 1);

        self.scrolltext = Scrolltext(NB_FONTS).init(self.scroller_target, fonts_b, SCROLL_CHARS, SCROLL_CHAR_WIDTH, SCROLL_CHAR_HEIGHT, SCROLL_TEXT, SCROLL_SPEED, 0, null, null, null);

        Console.log("demo init done!", .{});
    }

    pub fn update(self: *Demo, zigos: *ZigOS, elapsed_time: f32) void {

        self.scrolltext.update();

        self.frame_counter += 1;
        if (self.frame_counter == BAR_PERIOD) self.frame_counter = 0;

        self.scroller_pos_y -= 1;
        if (self.scroller_pos_y == 0) self.scroller_pos_y = BAND_ROWS - 1;
            
        _ = zigos;
        _ = elapsed_time;
    }

    pub fn render(self: *Demo, zigos: *ZigOS, elapsed_time: f32) void {

        // The background is the same ramp row on every line, slid one pixel per
        // frame: CHISEL repeats the frame's precomputed row down the plane.
        self.blitter.blitRow(&zigos.lfbs[0], 0, 0, &ramp_rows[self.frame_counter], HEIGHT, null);

        // Only the first band holds the font (rows 0..29); clear it by words.
        const band_words: []u32 = @as([*]u32, @ptrCast(@alignCast(self.scroller_buffer)))[0 .. SCROLL_CHAR_HEIGHT * WIDTH / 4];
        for (band_words) |*w| w.* = 0;
        self.scrolltext.render();

        // The plane is that band (font rows plus the blank gap) repeated down the
        // screen from the current vertical offset, wrapping inside the band: two
        // blits per band, seven bands, CHISEL reading the cart-RAM buffer.
        const fb = &zigos.lfbs[1];
        const split: u16 = BAND_ROWS - self.scroller_pos_y;
        var y: u16 = 0;
        while (y < HEIGHT) : (y += BAND_ROWS) {
            self.blitBand(fb, y, self.scroller_pos_y, split);
            self.blitBand(fb, y + split, 0, self.scroller_pos_y);
        }

        _ = elapsed_time;
    }

    fn blitBand(self: *Demo, fb: *LogicalFB, y: u16, sy: u16, rows: u16) void {
        if (y >= HEIGHT) return;
        self.blitter.blitImage(fb, 0, @intCast(y), self.scroller_buffer, WIDTH, 0, sy, WIDTH, @min(rows, HEIGHT - y), null);
    }
};
