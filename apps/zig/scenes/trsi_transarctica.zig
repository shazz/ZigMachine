// --------------------------------------------------------------------------
// TRSI -- TRANSARCTICA cracktro, Atari Falcon030, 1993.
//   intro Moonfall · logo "Evolution" by J.O.E · music "Victory" by Double Trouble
//
// Ported from the ORIGINAL binary (TRSI_FAL.PRG, Pack-Ice depacked). It was
// reverse-engineered into a reference model that reproduces the program's
// three Hatari RAM snapshots and seven Hatari screenshots with 0 differing
// pixels; the Zig here is that model's integer logic, and
// apps/trsi_transarctica_headless.mjs checks the cart against it.
//
// There is no raster, HBL, Timer B or blitter in the original: the effect is a
// palette. The logo uses colours 0-31. Text pixels are 128 + a fixed "hump"
// map value; every VBL, entries 128-255 are loaded with a 128-long window that
// slides one entry per VBL along a 2108-entry colour list (colours.zig). That
// gives the per-row cycling, the centre-out reveal, the fades and the page
// swaps, which happen while the window is all black. The six pages take two
// passes of the list, 4210 VBLs (84.2 s), and then repeat for ever, as here.
//
// The intro (intro.zig) waits on MUSIC TICKS: a white flash fading over 64
// ticks, the logo fading in over 64, a 210-tick hold, then a 60-VBL slide up
// by moving the screen base (here the plane's base register), then the text.
//
// The display is 320x240: the top and bottom borders are opened so all 240
// lines show at the original's positions (screen.zig).
//
// Skipped: the "Intern speaker on (y/n)?" and CODEC-Amplify console prompts,
// and the Space exit's fade + Pexec of the game (Escape leaves, as everywhere).
//
// MUSIC: victory.mod as ripped from DATA $42B1E (107,102 bytes, M.K.), on the
// ProTracker player. TRSI's Falcon replay starts at BPM 123 ($7B), not 125;
// no SNDH of it exists (it is an Amiga-style MOD mixed to DMA).
// --------------------------------------------------------------------------
const zg = @import("zigos");
const ZigOS = zg.ZigOS;
const LogicalFB = zg.LogicalFB;
const Color = zg.Color;

const assets = @import("trsi_transarctica/assets.zig");
const intro = @import("trsi_transarctica/intro.zig");
const colours = @import("trsi_transarctica/colours.zig");
const text = @import("trsi_transarctica/text.zig");
const screen = @import("trsi_transarctica/screen.zig");

const MUSIC = "trsi_transarctica.mod";
const MUSIC_BPM = 123; // the replay's default ($2BEA2), CIA mode
const PLANE = 0;
/// The Falcon's RGB VBL is 50 Hz; the host's frame is whatever the display
/// runs at. The colour list advances one entry per 20 ms VBL.
const VBL_US: u32 = 20_000;
const MAX_VBLS_PER_FRAME: u32 = 3; // after a stall, catch up a little, not all of it

pub const Demo = struct {
    c: u32, // the program's VBL counter ($5CD80)
    vbl_us: u32, // microseconds towards the next VBL
    base_line: u32, // screen base, in lines past the buffer's screen line 0
    pal: [256]u32, // Falcon palette longs, as $FF9800 holds them
    list: colours.List,
    page: usize, // the page on screen, 0..5

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        self.c = 0;
        self.vbl_us = 0;
        self.base_line = 0;
        self.page = 0;
        self.list.reset();
        intro.palette(0, &self.pal);
        const fb = &zigos.lfbs[PLANE];
        fb.is_enabled = true;
        fb.setOverscanScrollPlane(screen.BUF_W, screen.BUF_H); // cleared to 0
        fb.setFrameBufferHBLHandler(zg.OVERSCAN_MAGIC_X, openBands);
    }

    pub fn update(self: *Demo, zigos: *ZigOS, dt: f32) void {
        const ms = if (dt > 0 and dt < 1000) dt else 0;
        self.vbl_us += @intFromFloat(ms * 1000);
        var n: u32 = 0;
        while (self.vbl_us >= VBL_US) : (self.vbl_us -= VBL_US) {
            if (n < MAX_VBLS_PER_FRAME) self.vbl(zigos.lfbs[PLANE].fb);
            n += 1;
        }
    }

    pub fn render(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = dt;
        const fb = &zigos.lfbs[PLANE];
        fb.setScroll(0, self.base_line);
        for (self.pal, 0..) |v, i| fb.palette[i] = screen.rgba(v);
        // The Falcon paints its border with colour 0: the closed side borders.
        zigos.setBackgroundColor(Color.fromRGBA(screen.rgba(self.pal[0])));
    }

    /// One program VBL: handler 1 during the intro, handler 2 after, plus the
    /// main thread's work that VBL makes due.
    fn vbl(self: *Demo, buf: [*]u8) void {
        self.c += 1;
        const c = self.c;
        if (c == 1) zg.requestModBpm(MUSIC, MUSIC_BPM); // $F2: jsr $2BEA2
        if (c < intro.at.text) {
            intro.palette(c, &self.pal);
            if (c == intro.at.logo) screen.drawLogo(buf);
            self.base_line = intro.slide(c);
            return;
        }
        if (c == intro.at.text) { // $16C: the flag is set by hand for page 0
            self.list.reset();
            self.page = 0;
            self.drawPage(buf);
        }
        if (self.list.advance()) { // a $FFFE: the main loop draws the next page
            self.page = (self.page + 1) % text.PAGES; // $00 wraps to the first
            self.drawPage(buf);
        }
        for (self.pal[0..128], 0..) |*e, i| e.* = assets.long(assets.logo_pal, i);
        self.list.window(self.pal[128..256]);
    }

    fn drawPage(self: *Demo, buf: [*]u8) void {
        text.draw(screen.line(buf, screen.TEXT_LINE), screen.BUF_W, self.page);
    }
};

/// Open the top and bottom borders: flicker the resolution in both bands.
/// The side borders stay closed.
fn openBands(fb: *LogicalFB, _: *ZigOS, line: u16, _: u16) void {
    if (line < zg.VERTICAL_BORDERS_HEIGHT or line >= zg.VERTICAL_BORDERS_HEIGHT + zg.HEIGHT) fb.flickerBorder();
}
