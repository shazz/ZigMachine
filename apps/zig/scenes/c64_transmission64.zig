// --------------------------------------------------------------------------
// Transmission64 2021 invitation (Padua, C64, 19 February 2021). Code Anonym, Dano, Doomed,
// Hoogo; graphics Sander; music Toggle ("Transmission 64"). CSDb release 200255, demozoo
// 290038. Ported with Padua's go-ahead (VCF Montreal), from the depacked original
// (prototypes/transmission64_re/ANALYSIS.md says how it works).
//
// The C64 is modelled, not imitated: c64_transmission64/vic.zig draws what the VIC-II shows
// from a 64 KB copy of the C64's memory, a frame's register writes and the CPU's stores to
// screen and colour RAM, each at the raster position it lands on (the parts' screen updates
// take most of a frame and race the beam: a cell shows its new value only if it was stored
// before its row's bad line). Each part's IRQ chain is ported as the writes and stores it
// makes, timed by a 6510 bus-cycle clock (clock.zig) checked against VICE's own traces.
//
// The C64's borders are the machine's: physical row r = raster line r + 11, column c = X c - 16,
// so the C64's 320x200 window is the machine's. No part opens a border (unlike 1988), so there
// is no flicker here and the plane's overscan margins never show: the border colour is a real
// raster, per line BACKGROUND (global HBL) and the plane's colour 0 (its HBL). The bars of the
// two wipes are those border colours changing between lines. The C64 runs at 50 Hz: a C64
// frame every 6/5 machine frames.
//
// Music: Transmission 64 by Toggle (PSID, init $0C00, play $0C03, 8580, PAL), the invitation's
// own tune (HVSC /MUSICIANS/T/Toggle/Transmission_64.sid, byte-identical), played from the
// cart's memory by the .sid player (cRSID: BARD native, page wasm).
// --------------------------------------------------------------------------
const zg = @import("zigos");
const show_mod = @import("c64_transmission64/show.zig");
const vic = show_mod.vic;
const assets = @import("c64_transmission64/assets.zig");

const ZigOS = zg.ZigOS;
const LogicalFB = zg.LogicalFB;

pub const MUSIC_SID = true;
pub const SONG = @embedFile("../assets/screens/c64_transmission64/transmission_64.sid");
const K_ESC: u32 = 0xE012; // demo_main.zig's code for Escape

// colodore (VICE's colodore.vpl), C64 colour i at palette index i + 1; index 0 is the
// border, rewritten every line with the line's border colour.
pub const PALETTE = [16]u32{
    0x000000, 0xFFFFFF, 0x96282E, 0x5BD6CE, 0x9F2DAD, 0x41B936, 0x2724C4, 0xEFF347,
    0x9F4815, 0x5E3500, 0xDA5F66, 0x474747, 0x787878, 0x91FF84, 0x6864FF, 0xAEAEAE,
};

fn rgba(c: u8) u32 { // 0xRRGGBB -> the machine's A,B,G,R word
    const v = PALETTE[c & 15];
    return 0xFF00_0000 | ((v & 0xFF) << 16) | (v & 0xFF00) | (v >> 16);
}

var g_out: ?*const vic.Out = null; // HBL handlers take no user pointer

// The border colour, a raster: the C64 line's colour, and BEAM for a switch to black mid-line
// (black is the only exact ST colour among the 16; no other mid-line switch is visible here).
fn borderHbl(zigos: *ZigOS, line: u16) void {
    const out = g_out orelse return;
    if (line >= vic.ROWS) return;
    zigos.setBackgroundColor(zg.Color.fromRGBA(rgba(out.border[line])));
    if (out.split_x[line] != 0 and out.split_c[line] == 0) {
        zg.beam.begin();
        zg.beam.write(out.split_x[line], 0x000);
    }
}

// The plane's colour 0 is the line's border colour too: where the C64's window is closed
// (screen off, the wipes) the plane holds 0. Pure: own palette only.
fn planeHbl(fb: *LogicalFB, _: *ZigOS, line: u16, _: u16) void {
    const out = g_out orelse return;
    if (line >= vic.ROWS) return;
    fb.palette[0] = rgba(out.border[line]);
}

pub const Demo = struct {
    show: *show_mod.Show = undefined, // 140 KB (the C64's RAM, the stores): on zg.mem, not in the data
    out: vic.Out = undefined,
    frames: u32 = 0, // machine frames (60 Hz)
    wants_quit: bool = false,

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        const fb = &zigos.lfbs[0];
        fb.is_enabled = true;
        fb.setOverscanBuffer();
        fb.setPaletteEntry(0, zg.Color.fromRGBA(rgba(0)));
        for (0..16) |c| fb.setPaletteEntry(@intCast(c + 1), zg.Color.fromRGBA(rgba(@intCast(c))));
        @memset(fb.fb[0..vic.Out.ROWS_COLS], 0);
        self.out = .{ .pix = fb.fb[0..vic.Out.ROWS_COLS] };
        self.show = &zg.mem.mustAlloc(show_mod.Show, 1)[0]; // init runs once per cart load
        self.show.init(assets.all);
        self.frames = 0;
        self.wants_quit = false;
        g_out = &self.out;
        fb.setFrameBufferHBLHandlerPure(zg.OVERSCAN_MAGIC_X, planeHbl);
        zigos.setHBLHandler(borderHbl);
        if (MUSIC_SID) _ = zg.requestSongBytes(SONG, .sid, 0);
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
