// --------------------------------------------------------------------------
// Music debug screen — a little demo in itself.
//
// Real hardware rasters (per-scanline palette[0] + border background) + a
// sine-distorted TRSI logo + a player-adaptive YM/MOD/sample oscilloscope +
// an 8x8-font menu + a 16x16-font bottom scrolltext. Four planes:
//   plane 0 = 3D starfield (behind)
//   plane 1 = scope (transparent bg)
//   plane 2 = menu + fullscreen scrolltext, raster-filled from the HBL
//   plane 3 = TRSI logo with its trail (transparent bg, on top)
//
// Board speed (KESTREL, ZIGGY's f32 FPU): the waves use music_debug/fsin.zig,
// one sine a column, and each plane clears only what it drew (clear.zig).
//
// Keys 1..6 play MOD / YM / sample / SNDH / XM / a local XM. The host only forwards a digit to
// setShadeMode (docs/sealed-loader.js in the browser, fpga/glass/firmware/glass_input.c on
// the board, the same rule in both) and this cart asks for the song itself with
// zg.requestSong: the browser fetches it from docs/music/, the board plays it on BARD from
// the table fpga/tools/song_pack.py builds out of the names below. The audio state (mode,
// YM regs, per-channel scopes) is mirrored into zigos for the scope.
// --------------------------------------------------------------------------
const zg = @import("zigos"); // the open ZigOS library (named module)
const ZigOS = zg.ZigOS;
const LogicalFB = zg.LogicalFB;
const Color = zg.Color;
const Console = zg.Console;
const Starfield3D = zg.Starfield3D;
const NB_STARS = 200;

const WIDTH: u16 = zg.WIDTH;
const HEIGHT: u16 = zg.HEIGHT;
// border geometry, for drawing the scrolltext into the borders ("fullscreen")
const HBORD: i32 = zg.HORIZONTAL_BORDERS_WIDTH; // 40
const VBORD: i32 = zg.VERTICAL_BORDERS_HEIGHT; // 40

const palette = @import("music_debug/palette.zig");
const COPPER = palette.COPPER;
const text = @import("music_debug/text.zig");
const logo = @import("music_debug/logo.zig");
const scope = @import("music_debug/scope.zig");
const clear = @import("music_debug/clear.zig");

// plane 1 (text) palette entries
const CLEAR: u8 = 0;
const WHITE: u8 = 1;
const YELLOW: u8 = 2;
const GREEN: u8 = 3;
const CYAN: u8 = 4;
const DIM: u8 = 5;
const SCROLL: u8 = 10; // scrolltext colour, raster-cycled per scanline
const BGCOL = Color{ .r = 0, .g = 0, .b = 0, .a = 255 };

const RASTER_SPEED: f32 = 0.6; // scrolltext raster cycle speed (lower = slower)
const SCROLL_SPEED: f32 = 2.0;
const SCROLL_WAVE_AMP: f32 = 6.0; // vertical wobble of the scrolltext
const MENU_WAVE_AMP: f32 = 2.5;
const MENU_X: i32 = 44 + HBORD; // = 84
const MENU_Y: i32 = 92 + VBORD; // first menu line; PRESS 1 TO 6 sits at +88
const SCROLL_Y: i32 = (HEIGHT - 28) + VBORD; // physical baseline
// dphase literals, not k * 0.4: in f32, 0.4 * 3 is not the 1.2 the waves were tuned on.
const MenuLine = struct { text: []const u8, dy: i32, dphase: f32 };
const MENU = [_]MenuLine{
    .{ .text = "1  MOD     LOLLAPALOOZA", .dy = 0, .dphase = 0 },
    .{ .text = "2  YM2149  CONCERTO", .dy = 14, .dphase = 0.4 },
    .{ .text = "3  SAMPLE  DIGI 12517HZ", .dy = 28, .dphase = 0.8 },
    .{ .text = "4  SNDH    CRYSTALLIZED", .dy = 42, .dphase = 1.2 },
    .{ .text = "5  XM      TEST SONG", .dy = 56, .dphase = 1.6 },
    .{ .text = "6  XM      LOCAL.XM", .dy = 70, .dphase = 2.0 },
    .{ .text = "PRESS 1 TO 6", .dy = 88, .dphase = 2.4 },
};
// The text plane's rows that ever hold a pixel: the menu (2 px of wobble) down to the
// scroller (6 px of wobble); only these are cleared each frame.
const TEXT_FIRST_ROW: u16 = MENU_Y - 2;
const TEXT_LAST_ROW: u16 = SCROLL_Y + 15 + 6;

const MESSAGE =
    "WELCOME TO THE ZIGMACHINE MUSIC DEBUG SCREEN ....   " ++
    "ZIG + WASM POWERED OLDSKOOL SOUND !   " ++
    "REAL HARDWARE RASTERS, PAULA SAMPLE CHANNELS AND A YM2149 EMULATION ....   " ++
    "PRESS 1 FOR MOD, 2 FOR YM CHIPTUNE, 3 FOR A 12517 HZ DIGI SAMPLE STREAM, 4 FOR AN SNDH PLAYED BY ITS OWN 68000, " ++
    "5 FOR A FASTTRACKER 2 XM, EIGHT VOICES ON FOUR PAULA CHANNELS, 6 FOR YOUR OWN LOCAL.XM ....   " ++
    "THE SCOPE FOLLOWS THE ACTIVE PLAYER ....   " ++
    "GREETINGS TO ALL TRSI MEMBERS AND ALL THE SCENERS OUT THERE ....   " ++
    "AND NOW... LET IT WRAP !                   ";

var raster_offset: u16 = 0;
var raster_phase: f32 = 0.0;

// Per-scanline HBL handler on the text plane: cycles the scrolltext colour
// through the copper gradient so the letters are raster-filled. Merged with
// the overscan trick: the scroller spills past 320px into the borders, so
// they must stay open every line too — both are per-scanline palette/latch
// writes with no pixel-column sensitivity, so they share this one HBL slot,
// registered at OVERSCAN_MAGIC_X (see docs/HW_API.md "Opening the borders").
fn scrollRasterHandler(fb: *LogicalFB, zigos: *ZigOS, line: u16, col: u16) void {
    _ = zigos;
    _ = col;
    fb.setPaletteEntry(SCROLL, COPPER[(line + raster_offset) % 256]);
    fb.flickerBorder();
}

pub const Demo = struct {
    scroll_x: f32 = @floatFromInt(WIDTH),
    phase: f32 = 0.0,
    logo_phase: f32 = 0.0, // slow, drives the logo distortion
    flow_frame: u32 = 0, // scope electron-flow timer
    scope: scope.Scope = .{},
    scope_drawn: bool = false, // the scope plane holds a curve
    stars: clear.StarEraser(NB_STARS) = .{},
    starfield: Starfield3D(NB_STARS) = undefined,

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        Console.log("music debug init", .{});
        self.scroll_x = @floatFromInt(WIDTH);
        self.phase = 0.0;
        raster_offset = 0;
        raster_phase = 0.0;
        zigos.setBackgroundColor(BGCOL); // black borders

        // plane 0: 3D starfield (back). init() sets its own brightness palette.
        var p0: *LogicalFB = &zigos.lfbs[0];
        p0.is_enabled = true;
        self.starfield = Starfield3D(NB_STARS).init(p0.getRenderTarget(), WIDTH, HEIGHT, 2, false);
        p0.setPaletteEntry(0, BGCOL); // black background
        p0.clearFrameBuffer(0);

        // plane 1: scope (transparent bg so the starfield shows through)
        var p1: *LogicalFB = &zigos.lfbs[1];
        p1.is_enabled = true;
        scope.setPalette(p1);
        p1.clearFrameBuffer(0);

        // plane 2: menu + FULLSCREEN scroll text (its border columns hold the
        // scroller that spills past the 320px screen — real Option-B overscan,
        // no physical-framebuffer poke). Coordinates on this plane are PHYSICAL.
        var p2: *LogicalFB = &zigos.lfbs[2];
        p2.is_enabled = true;
        p2.setOverscanBuffer();
        p2.setPaletteEntry(CLEAR, Color{ .r = 0, .g = 0, .b = 0, .a = 0 });
        p2.setPaletteEntry(WHITE, Color{ .r = 245, .g = 245, .b = 250, .a = 255 });
        p2.setPaletteEntry(YELLOW, Color{ .r = 255, .g = 220, .b = 90, .a = 255 });
        p2.setPaletteEntry(GREEN, Color{ .r = 130, .g = 240, .b = 150, .a = 255 });
        p2.setPaletteEntry(CYAN, Color{ .r = 130, .g = 210, .b = 250, .a = 255 });
        p2.setPaletteEntry(DIM, Color{ .r = 190, .g = 190, .b = 210, .a = 255 });
        p2.setPaletteEntry(SCROLL, COPPER[0]);
        p2.setFrameBufferHBLHandler(zg.OVERSCAN_MAGIC_X, scrollRasterHandler); // raster-fill + overscan flicker
        p2.clearFrameBuffer(CLEAR);

        // plane 3: TRSI logo (its own palette, index 0 transparent), on top
        var p3: *LogicalFB = &zigos.lfbs[3];
        p3.is_enabled = true;
        palette.logoPalette(p3);
        p3.clearFrameBuffer(0);
    }

    pub fn update(self: *Demo, zigos: *ZigOS, time_elapsed: f32) void {
        _ = zigos;
        _ = time_elapsed;
        self.scroll_x -= SCROLL_SPEED;
        const total: f32 = @floatFromInt(MESSAGE.len * 16);
        if (self.scroll_x < -total) self.scroll_x = @floatFromInt(WIDTH);
        self.phase += 0.15;
        self.logo_phase += 0.045; // slower logo movement
        self.flow_frame +%= 1;
        raster_phase += RASTER_SPEED;
        if (raster_phase >= 4096.0) raster_phase -= 4096.0;
        raster_offset = @intFromFloat(raster_phase);
        self.starfield.update();
    }

    // Keys 1..6 pick MOD / YM / sample / SNDH / XM / local XM — request BY NAME (host plays
    // it, no per-scene playlist in the glass). Files live under docs/music/.
    //
    // The SNDH is the odd one out and the point of having it here: the other
    // three are DATA the players interpret, while an SNDH is a PROGRAM — the
    // cart depacks it (Pack-Ice) and runs its 68000 code on Musashi, and the
    // scope below is then watching a real replay routine drive the chip.
    //
    // Key 5's XM is the player's own generated test song (apps/xm_song.mjs). Key 6
    // asks for docs/music/local.xm: a song the owner keeps on their own machine
    // only (gitignored), for a tune whose licence does not allow bundling it. A
    // checkout without one plays nothing on 6, and the board's song table leaves
    // it out (fpga/tools/song_pack.py LOCAL_SONGS). See docs/MUSIC.md.
    const TUNES = [_][]const u8{
        "lollapalooza.mod", "concerto.ymraw", "smp1.raw", "crystallized.sndh", "zm_test.xm", "local.xm",
    };
    pub fn setShadeMode(self: *Demo, mode: u32) void {
        _ = self;
        if (mode < TUNES.len) zg.requestSong(TUNES[mode]);
    }

    pub fn render(self: *Demo, zigos: *ZigOS, time_elapsed: f32) void {
        _ = time_elapsed;

        // plane 0: starfield
        const p0: *LogicalFB = &zigos.lfbs[0];
        self.stars.erase(p0);
        self.starfield.render();
        self.stars.record(p0, &self.starfield.starfield_table, self.starfield.width, self.starfield.height);

        // plane 1: scope
        const p1: *LogicalFB = &zigos.lfbs[1];
        if (self.scope_drawn) p1.clearFrameBuffer(0);
        self.scope.draw(zigos, p1, self.flow_frame, self.phase);
        self.scope_drawn = zigos.audio_mode >= 1 and zigos.audio_mode <= 4;

        // plane 2 is FULLSCREEN, so coordinates are physical: the visible screen
        // sits at +HBORD,+VBORD (40,40), so menu text keeps its on-screen place.
        const p2: *LogicalFB = &zigos.lfbs[2];
        clear.rows(p2, TEXT_FIRST_ROW, TEXT_LAST_ROW, CLEAR);
        for (MENU) |line| {
            text.drawText8(p2, line.text, MENU_X, MENU_Y + line.dy, WHITE, MENU_WAVE_AMP, self.phase + line.dphase);
        }
        // the scroller across the full physical width: visible-space x -> physical
        const base_x: i32 = @as(i32, @intFromFloat(self.scroll_x)) + HBORD;
        text.drawScroller(p2, MESSAGE, base_x, SCROLL_Y, SCROLL, SCROLL_WAVE_AMP, self.phase);

        // plane 3: logo with a 3-frame darkening trail (oldest/darkest first)
        const p3: *LogicalFB = &zigos.lfbs[3];
        clear.rows(p3, 0, logo.LAST_ROW, 0);
        logo.draw(p3, self.logo_phase - 2.4, 96);
        logo.draw(p3, self.logo_phase - 1.6, 64);
        logo.draw(p3, self.logo_phase - 0.8, 32);
        logo.draw(p3, self.logo_phase, 0);
    }
};
