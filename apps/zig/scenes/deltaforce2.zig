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
const BAND_BYTES: usize = BAND_ROWS * WIDTH;
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
    // scroller_pos_y = 32. Sized to the declared height, it lives as long as Demo.
    scroller_buffer: [WIDTH * SCROLLER_ROWS]u8 = undefined,
    scroller_render_buffer: RenderBuffer = undefined,

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

        @memset(&self.scroller_buffer, 0);
        self.scroller_render_buffer = .{ .buffer = &self.scroller_buffer, .width = WIDTH, .height = SCROLLER_ROWS };
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

        // Every row of the background is the same 10-pixel ramp (WIDTH is a
        // multiple of BAR_PERIOD), so build the row once and copy it down
        // instead of taking a modulo per pixel.
        var row: [WIDTH]u8 = undefined;
        for (&row, 0..) |*px, x| px.* = rasterbars_b[(self.frame_counter + x) % BAR_PERIOD];

        var fb = &zigos.lfbs[0];
        for (0..HEIGHT) |y| @memcpy(fb.fb[y * WIDTH ..][0..WIDTH], &row);

        fb = &zigos.lfbs[1];
        self.scroller_target.clearFrameBuffer(0);
        self.scrolltext.render();

        // A second copy of the font band below the first, so a band read at any
        // scroll offset always has a whole band of pixels ahead of it.
        const band = self.scroller_buffer[0 .. SCROLL_CHAR_HEIGHT * WIDTH];
        @memcpy(self.scroller_buffer[BAND_BYTES..][0 .. SCROLL_CHAR_HEIGHT * WIDTH], band);

        // The plane is that band, repeated down the screen from the current
        // vertical offset: six whole bands and whatever is left of the seventh.
        const offset = self.scroller_pos_y * WIDTH;
        const source = self.scroller_buffer[offset..][0..BAND_BYTES];
        const whole_bands = (WIDTH * HEIGHT) / BAND_BYTES;
        for (0..whole_bands) |b| @memcpy(fb.fb[b * BAND_BYTES ..][0..BAND_BYTES], source);

        const tail = (WIDTH * HEIGHT) - whole_bands * BAND_BYTES;
        @memcpy(fb.fb[whole_bands * BAND_BYTES ..][0..tail], source[0..tail]);

        _ = elapsed_time;

    }
};
