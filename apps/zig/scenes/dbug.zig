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

// credit panel: dbug_credits.zig (geometry, texts), dbug_layers.zig (its font)

// music — the screen's own tune, played by its own 68000 (docs/music/)
const MUSIC = "crystallized.sndh";

// where the logo sits when its spring is at rest
const LOGO_Y: i32 = 20;

// palettes
const font_pal = convertU8ArraytoColors(@embedFile("../assets/screens/dbug/fonts_32x24_pal.dat"));
const text_font_pal = convertU8ArraytoColors(@embedFile("../assets/screens/dbug/fonts_16x14_pal.dat"));
const logo_pal = convertU8ArraytoColors(@embedFile("../assets/screens/dbug/logo_pal.dat"));

// The rasters, the logo and the credit panel: dbug_layers.zig.
const layers = @import("dbug_layers.zig");

// --------------------------------------------------------------------------
// Variables
// --------------------------------------------------------------------------
// The 400x280 overscan page is the plane's own framebuffer (it used to be drawn
// in a RAM copy and memcpy'd to the plane: every store of a ZIGGY frame is a
// blocking DDR write). Rows of it that are not all 0:
var dirty: draw.Dirty = .{};
var chisel: zg.Blitter = .{}; // the zoomed lines' copies; init() points it at the video region

// The scroller is drawn 50 pixels wide and zoomed 8 times into the overscan
// ((320 + 80) / 8). Small, so a static; cleared in init.
var scroller_pixels: [50 * SCROLL_CHAR_HEIGHT]u8 = undefined;

// The RenderTarget holds a POINTER to this, and lives for the whole cart, so the
// buffer must too: as an init() local it was a dangling stack pointer.
var scroller_render_buffer: RenderBuffer = undefined;

// --------------------------------------------------------------------------
// Demo
// --------------------------------------------------------------------------
pub const Demo = struct {

    name: u8 = 0,
    frame_counter: u32 = 0,
    scrolltext: Scrolltext(NB_FONTS) = undefined,
    scroller_target: RenderTarget = undefined,
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
        layers.reset();
        fb.setFrameBufferHBLHandler(zg.OVERSCAN_MAGIC_X, layers.hbl);

        chisel.init();
        @memset(&scroller_pixels, 0);
        scroller_render_buffer = .{ .buffer = &scroller_pixels, .width = 50, .height = SCROLL_CHAR_HEIGHT };
        self.scroller_target = .{ .render_buffer = &scroller_render_buffer };

        self.scrolltext = Scrolltext(NB_FONTS).init(self.scroller_target, fonts_b, SCROLL_CHARS, SCROLL_CHAR_WIDTH, SCROLL_CHAR_HEIGHT, SCROLL_TEXT, SCROLL_SPEED, 0, null, null, null);
        self.sync = .{};

        // copy logo palette starting at 100, the panel's at 201
        fb.setPaletteEntry(100, Color{ .r = 0, .g = 0, .b = 0, .a = 0 });
        fb.setPaletteEntry(101, logo_pal[1]);
        fb.setPaletteEntry(102, logo_pal[2]);
        fb.setPaletteEntry(103, logo_pal[3]);
        layers.panelPalette(fb, text_font_pal);

        // credit panel — it writes itself into plane 1's memory one cell per frame
        // and never redraws a settled letter, so that is cleared ONCE, here. Plane 1
        // stays DISABLED: the panel is blitted onto plane 0 (dbug_layers.zig).
        fb = &zigos.lfbs[1];
        fb.is_enabled = false;
        fb.clearFrameBuffer(0);
        self.panel.init(credits.config(&layers.panel_font));

        Console.log("demo init done!", .{});


    }

    pub fn update(self: *Demo, zigos: *ZigOS, elapsed_time: f32) void {
        _ = elapsed_time;

        self.scrolltext.update();
        self.panel.update();

        // The scroller and the logo are driven by the TUNE, not by a sine: the
        // intro is still, the scroller falls on cue and then bumps once per
        // beat. zigos.song_ms is the playback position the host mirrors over
        // from the audio worklet (on the board, from BARD: fpga/cycles/aud_state.h);
        // it stays 0 until the viewer enables sound, which simply holds the
        // intro. See dbug_sync.zig.
        self.sync.update(zigos.song_ms);
        layers.start_raster_line = self.sync.y;
    }

    pub fn render(self: *Demo, zigos: *ZigOS, elapsed_time: f32) void {
        _ = elapsed_time;
        @memset(&scroller_pixels, 0);
        self.scrolltext.render();

        // draw the zoomed scrolltext straight into the overscan plane: the zoom
        // repaints its whole band, so only the rows the last frame touched outside
        // it are cleared (by CHISEL: a memset is ~60 cycles a word on the board)
        const fb = &zigos.lfbs[0];
        const top = layers.start_raster_line;
        const band = draw.Dirty.rows(top, @as(i32, top) + SCROLL_CHAR_HEIGHT * draw.ZOOM);
        for (draw.staleRuns(dirty, band)) |r| {
            if (r.hi > r.lo) chisel.fill(fb, 0, @intCast(r.lo), draw.OVERSCAN_W, r.hi - r.lo, 0);
        }
        draw.zoomScrollerGpu(fb, &chisel, self.scroller_target, top, SCROLL_CHAR_HEIGHT);
        const ly = LOGO_Y + self.sync.logo_dy;
        layers.drawLogo(&chisel, fb, ly);

        // The credit panel paints only the cells that moved this frame into plane
        // 1's memory; all of it then goes on top of plane 0, whose panel rows were
        // all just repainted or cleared (they are always dirty).
        const text_fb = &zigos.lfbs[1];
        self.panel.render(text_fb.fb[0 .. @as(u32, WIDTH) * HEIGHT], WIDTH, credits.X, credits.Y);
        layers.composePanel(&chisel, fb, text_fb);

        dirty = band.merge(layers.logoRows(ly)).merge(layers.panelRows());
    }
};
