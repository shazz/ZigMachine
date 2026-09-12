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
const Resolution = zg.Resolution;
const Color = zg.Color;

const Scrolltext = zg.Scrolltext;
const Sprite = zg.Sprite;

const Console = zg.Console;

const credits = @import("dbug_credits.zig");
const draw = @import("dbug_draw.zig");
const Sync = @import("dbug_sync.zig").Sync;

// --------------------------------------------------------------------------
// Constants
// --------------------------------------------------------------------------
const HEIGHT: u16 = zg.HEIGHT;
const WIDTH: u16 = zg.WIDTH;

// scrolltext
const fonts_b = @embedFile("../assets/screens/dbug/fonts_32x24.raw");
const SCROLL_TEXT = "JUST WHEN YOU THOUGHT WE WERE OUT...WE ARE STILL HERE! THIS MEGA INTRO WAS DONE BY !CUBE OF AGGRESSION, AND IT IS PROBABLY THE BIGGEST REASON YOU ARE SEEING THIS RELEASE AT ALL :P        GREETZ TO ALL THAT DESERVE IT...         LET'S WRAP.............      ";
const SCROLL_CHAR_WIDTH = 32; 
const SCROLL_CHAR_HEIGHT = 24;
const SCROLL_SPEED = 1;
const SCROLL_CHARS = " ! #$%&'()*+,-./0123456789:;<=>? ABCDEFGHIJKLMNOPQRSTUVWXYZ";
pub const NB_FONTS: u8 = WIDTH / SCROLL_CHAR_WIDTH + 1;

// credit panel (see dbug_credits.zig for the geometry and the four texts)
const text_fonts_b = @embedFile("../assets/screens/dbug/fonts_16x14.raw");

// music — the screen's own tune, played by its own 68000 (docs/music/)
const MUSIC = "crystallized.sndh";

// where the logo sits when its spring is at rest
const LOGO_Y: i32 = 20;

// palettes
const font_pal = convertU8ArraytoColors(@embedFile("../assets/screens/dbug/fonts_32x24_pal.dat"));
const text_font_pal = convertU8ArraytoColors(@embedFile("../assets/screens/dbug/fonts_16x14_pal.dat"));
const logo_pal = convertU8ArraytoColors(@embedFile("../assets/screens/dbug/logo_pal.dat"));

// rasters
const rasters_b = convertU8ArraytoColors(@embedFile("../assets/screens/dbug/rasters.dat"));

// logo
const  logo_b = @embedFile("../assets/screens/dbug/logo.raw");

// --------------------------------------------------------------------------
// Variables
// --------------------------------------------------------------------------
var start_raster_line: u16 = 0;
var off_buffer = [_]u8{0} ** (400 * 280); 

// --------------------------------------------------------------------------
// Demo
// --------------------------------------------------------------------------
fn handler_scroller(fb: *LogicalFB, zigos: *ZigOS, line: u16, col: u16) void {
    _ = zigos;
    _ = col;

    // Overscan plane: this per-plane HBL fires on PHYSICAL lines 0..279. The zoomed
    // scroller fills the whole 400-wide buffer, so open ALL borders by flickering the
    // resolution register every line (the authentic trick; see docs/HW_API.md).
    fb.flickerBorder();

    // Raster bars behind the scroller (physical line numbering — unchanged).
    if (line > start_raster_line and line < start_raster_line + 192) {
        fb.setPaletteEntry(7, rasters_b[(line - start_raster_line)]);
    }
}

pub const Demo = struct {
  
    name: u8 = 0,
    frame_counter: u32 = 0,
    scrolltext: Scrolltext(NB_FONTS) = undefined,
    logo: Sprite = undefined,
    scroller_target: RenderTarget = undefined,
    overscan_target: RenderTarget = undefined,
    panel: zg.charpanel.Panel(credits.MAX_LIVE) = undefined,
    sync: Sync = .{},

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        Console.log("Demo init", .{});

        // The screen's own music: !Cube's "Crystallized", the SNDH the original
        // plays. The host fetches it by name and hands it to the cart, which
        // depacks the Pack-Ice image and runs its 68000 (see players/sndh_player).
        // Nothing happens until the user turns sound on — the request just waits.
        zg.requestSong(MUSIC);

        // first plane — overscan (400×280); borders opened by the flicker trick
        var fb: *LogicalFB = &zigos.lfbs[0];
        fb.is_enabled = true;
        fb.setOverscanBuffer();
        fb.setPalette(font_pal);
        fb.setPaletteEntry(7, Color{ .r = 0, .g = 0, .b = 0, .a = 0 });

        // HBL: open the borders + raster bars (must fire at the magic column)
        fb.setFrameBufferHBLHandler(zg.OVERSCAN_MAGIC_X, handler_scroller);

        // only a 50 pixels wide buffer is needed as it will be zoomed 8 times (320+80 / 8)
        var buffer = [_]u8{0} ** (50 * SCROLL_CHAR_HEIGHT); 
        var render_buffer: RenderBuffer = .{ .buffer = &buffer, .width = 50, .height = SCROLL_CHAR_HEIGHT };  
        self.scroller_target = .{ .render_buffer = &render_buffer };   

        self.scrolltext = Scrolltext(NB_FONTS).init(self.scroller_target, fonts_b, SCROLL_CHARS, SCROLL_CHAR_WIDTH, SCROLL_CHAR_HEIGHT, SCROLL_TEXT, SCROLL_SPEED, 0, null, null, null);
        self.sync = .{};

        // big buffer to the siz of the overscan
        var overscan_render_buffer: RenderBuffer = .{ .buffer = &off_buffer, .width = 400, .height = 280 };  
        self.overscan_target = .{ .render_buffer = &overscan_render_buffer };   

        // copy logo palette starting at 100
        fb.setPaletteEntry(100, Color{ .r = 0, .g = 0, .b = 0, .a = 0 });
        fb.setPaletteEntry(101, logo_pal[1]);
        fb.setPaletteEntry(102, logo_pal[2]);
        fb.setPaletteEntry(103, logo_pal[3]);
        self.logo.init(self.overscan_target, logo_b, 253, 38, zg.PHYSICAL_WIDTH / 2 - 126, LOGO_Y, null, null); // centre in the 400-wide overscan

        // credit panel — it writes itself into this plane one cell per frame and
        // never redraws a settled letter, so the plane is cleared ONCE, here.
        fb = &zigos.lfbs[1];
        fb.is_enabled = true;
        fb.setPalette(text_font_pal);
        fb.setPaletteEntry(0, Color{ .r = 0, .g = 0, .b = 0, .a = 0 });
        fb.clearFrameBuffer(0);
        self.panel.init(credits.config(text_fonts_b));

        Console.log("demo init done!", .{});


    }

    pub fn update(self: *Demo, zigos: *ZigOS, elapsed_time: f32) void {
        _ = elapsed_time;

        self.scrolltext.update();
        self.panel.update();

        // The scroller and the logo are driven by the TUNE, not by a sine: the
        // intro is still, the scroller falls on cue and then bumps once per
        // beat. zigos.song_ms is the playback position the host mirrors over
        // from the audio worklet; it stays 0 until the viewer enables sound,
        // which simply holds the intro. See dbug_sync.zig.
        self.sync.update(zigos.song_ms);
        start_raster_line = self.sync.y;
        self.logo.update(null, LOGO_Y + self.sync.logo_dy, null, null);
    }

    pub fn render(self: *Demo, zigos: *ZigOS, elapsed_time: f32) void {

        self.scroller_target.clearFrameBuffer(0);
        self.scrolltext.render();

        // draw the zoomed scrolltext on a overscan buffer
        self.overscan_target.clearFrameBuffer(0);
        draw.zoomScroller(self.overscan_target, self.scroller_target, start_raster_line, SCROLL_CHAR_HEIGHT);
        self.logo.render(100);

        // The credit panel paints only the cells that moved this frame, straight
        // into its own plane — everything already standing stays put.
        const text_fb = &zigos.lfbs[1];
        self.panel.render(text_fb.fb[0 .. @as(u32, WIDTH) * HEIGHT], WIDTH, credits.X, credits.Y);

        // Blit the finished 400×280 overscan buffer into the plane (borders included;
        // renderPlaneOverscan shows the border rows only where the trick opened them).
        const fb = &zigos.lfbs[0];
        @memcpy(fb.fb[0 .. 400 * 280], off_buffer[0 .. 400 * 280]);

        _ = elapsed_time;

    }
};
