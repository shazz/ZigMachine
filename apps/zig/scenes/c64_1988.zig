// --------------------------------------------------------------------------
// 1988 (Tristar & Red Sector Inc., C64, Only Sprites compo, 16 Jan 2021, out of competition).
// Code Shazz, graphics Elko, music Barney Gumble ("Ultimate Intro 12"). CSDb release 198974.
// Ported from the depacked original (prototypes/1988_re/ANALYSIS.md says how it works).
//
// Only sprites, so only sprites here too: one empty 400x280 overscan plane, and the eight
// hardware sprites drawn into it a row per raster line by c64_1988/vic.zig, a model of the
// VIC-II's sprite unit, replaying the register writes the original's IRQ chains make
// (c64_1988/logo.zig, wipe.zig, grid.zig, sequenced by show.zig) at their raster lines and
// cycles. The multiplexing, the vertical stretch of part 3 and the open borders are the
// C64's own rules, not effects drawn to look like them; the plane holds exactly the C64's
// picture (VICE x64sc, colodore palette: tools/c64/vicmodel.py and the harness compare).
//
// The C64's borders are the machine's: physical row r = raster line r + 11, column c = sprite
// X c - 16, so the C64's 320x200 window is the machine's. Where the C64 opens a border, the
// plane's HBL opens the machine's with the flicker trick on the same rows. The border colour
// is a real raster, as colour 0 is on an ST: per line, BACKGROUND (the closed borders, from
// the global HBL, with BEAM for part 2's mid-line switches) and the plane's colour 0 (the
// window and the opened borders, from the plane's HBL). The C64 runs at 50 Hz: a C64 frame
// every 6/5 machine frames.
//
// Music: Ultimate Intro 12 (PSID, init $1000, play $1003, 8580) needs the SID player
// (cRSID on BARD, branch feat/sid-bard, not on main yet): MUSIC_SID below is the one switch,
// off until it lands (docs/ROADMAP.md row "1988 music").
// --------------------------------------------------------------------------
const zg = @import("zigos");
const show_mod = @import("c64_1988/show.zig");
const vic = show_mod.vic;
const assets = @import("c64_1988/assets.zig");

const ZigOS = zg.ZigOS;
const LogicalFB = zg.LogicalFB;

pub const MUSIC_SID = false; // true once requestSong can play a .sid (ROADMAP "1988 music")
pub const SONG = "ultimate_intro_12.sid";
const K_ESC: u32 = 0xE012; // demo_main.zig's code for Escape

// colodore (VICE's colodore.vpl), C64 colour i at palette index i + 1; index 0 is the
// background, rewritten every line with the line's border colour.
pub const PALETTE = [16]u32{
    0x000000, 0xFFFFFF, 0x96282E, 0x5BD6CE, 0x9F2DAD, 0x41B936, 0x2724C4, 0xEFF347,
    0x9F4815, 0x5E3500, 0xDA5F66, 0x474747, 0x787878, 0x91FF84, 0x6864FF, 0xAEAEAE,
};

fn rgba(c: u8) u32 { // 0xRRGGBB -> the machine's A,B,G,R word
    const v = PALETTE[c & 15];
    return 0xFF00_0000 | ((v & 0xFF) << 16) | (v & 0xFF00) | (v >> 16);
}

var g_out: ?*const vic.Out = null; // HBL handlers take no user pointer

// The border colour, a raster: the C64 line's colour, and BEAM for a switch mid-line (part
// 2's wipe on the border lines). Only black is an exact ST colour among the 16, and black is
// the only colour switched to mid-line on the visible lines.
fn borderHbl(zigos: *ZigOS, line: u16) void {
    const out = g_out orelse return;
    if (line >= vic.ROWS) return;
    zigos.setBackgroundColor(zg.Color.fromRGBA(rgba(out.border[line])));
    if (out.split_x[line] != 0 and out.split_c[line] == 0) {
        zg.beam.begin();
        zg.beam.write(out.split_x[line], 0x000);
    }
}

// The plane's line: colour 0 is the line's border colour (where no sprite is, the C64 shows
// its border/background colour, and the two are one here), and the plane's borders open
// where the C64's are: the top/bottom bands when its vertical border is open, a visible
// row's sides when a side border is open on that line. Pure: own palette and flicker only.
fn planeHbl(fb: *LogicalFB, _: *ZigOS, line: u16, _: u16) void {
    const out = g_out orelse return;
    if (line >= vic.ROWS) return;
    fb.palette[0] = rgba(out.border[line]);
    const band = line < zg.VERTICAL_BORDERS_HEIGHT or line >= zg.VERTICAL_BORDERS_HEIGHT + zg.HEIGHT;
    if (if (band) out.vopen[line] else out.sides[line]) fb.flickerBorder();
}

pub const Demo = struct {
    show: show_mod.Show = undefined,
    out: vic.Out = undefined,
    frames: u32 = 0, // machine frames (60 Hz)
    wants_quit: bool = false,

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        const fb = &zigos.lfbs[0];
        fb.is_enabled = true;
        fb.setOverscanBuffer();
        fb.setPaletteEntry(0, zg.Color.fromRGBA(rgba(0)));
        for (0..16) |c| fb.setPaletteEntry(@intCast(c + 1), zg.Color.fromRGBA(rgba(@intCast(c))));
        self.out = .{ .pix = fb.fb[0..vic.Out.ROWS_COLS] };
        self.show = show_mod.Show.init(assets.all);
        self.frames = 0;
        self.wants_quit = false;
        g_out = &self.out;
        fb.setFrameBufferHBLHandlerPure(zg.OVERSCAN_MAGIC_X, planeHbl);
        zigos.setHBLHandler(borderHbl);
        if (MUSIC_SID) zg.requestSong(SONG);
    }

    pub fn key(self: *Demo, cp: u32) void {
        if (cp == K_ESC) self.wants_quit = true;
    }

    /// C64 frame n is due on machine frame ceil(6n/5): the 50 Hz picture on a 60 Hz machine.
    pub fn update(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = zigos;
        _ = dt;
        self.frames += 1;
        const due = self.frames * 5 / 6;
        while (self.show.frames < due) self.show.step(&self.out);
    }

    pub fn render(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = self;
        _ = zigos;
        _ = dt;
    }
};
