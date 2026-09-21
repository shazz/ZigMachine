// --------------------------------------------------------------------------
// ELITE — the crack intro for "Challenge Foot Senior", 2019.
// Code, graphics and music by !CUBE; replay routine maxYMiser by gwEm (Gareth
// Morris); the game cracked by Brume. The scrolltext is theirs, byte for byte.
//
// Ported from the ORIGINAL ST BINARY (ELT_CFSR.PRG, fujiology.org/ST/E/ELITE/),
// not from a remake. The .PRG opens with a 40-byte XOR-decrypted "Eagle/Hotline"
// packer banner and a backwards Pack-Ice-family LZ depacker at TEXT+$dc; the
// image it unpacks still carries its SYMBOL TABLE, so everything here is
// addressed by the author's own labels (LOGO_BITMAP, YSIN, RASTERS, FONT,
// SCROLL_TEXT, COPY_XOR_BUFFER...). The packer banner is a depacker intro and is
// skipped, as the house rule says; ZigMachine depacks for real.
//
// WHAT IS ON SCREEN (one 320x200 low-res screen, borders open for the rasters):
//   lines  0..36   the ELITE logo, 320x37 in 4 planes, blitted once and static
//   lines 39..43   a five-line colour-0 bar, BEAM_RASTERS1, full width
//   lines 44..199  the scroller band: ONE 320x16 pattern repeated ten times
//                  every 16 lines, wobbling per column through a 4096-entry
//                  table, with colours 1 and 8 rewritten per scanline
//   lines 201..205 the closing bar, BEAM_RASTERS2 — past the screen, so it shows
//                  in the BOTTOM BORDER, which is why the borders open here
//
// The scroller is an XOR-fill, not a bitmap: the font stores six row numbers per
// pixel column, a running XOR down a 32-row buffer turns them into filled spans,
// and a fold at 16 makes the per-column vertical wobble wrap (elite_cfsr/band.zig).
// COPY_XOR_BUFFER's move.l straddles two bitplanes, so every other 16 pixels is
// a different palette entry — and the raster writes both of them the same value.
//
// MUSIC: this tune is a maxYMiser MODULE, not an SNDH, and nothing in
// prototypes/sndh_lf/ matches it (no MYM0INST anywhere in the 5897 tunes, and
// none of !Cube's 30 SNDHs is this one). The replay + module needs NO
// relocations — all 216 of the image's fixups land before it — so it was ripped
// whole and wrapped in a real SNDH header around its own bra.w init/exit/play
// at DATA $8c54. docs/music/elite_cfsr.sndh is the demo's own 68000 replay code
// driving the sealed YM: apps/sndh_headless.mjs measures peak 0.4228.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const ZigOS = zg.ZigOS;
const Color = zg.Color;

const A = @import("elite_cfsr/assets.zig");
const rasters = @import("elite_cfsr/rasters.zig");
const band = @import("elite_cfsr/band.zig");
const Scroller = @import("elite_cfsr/scroller.zig").Scroller;

const MUSIC = "elite_cfsr.sndh";
const PLANE = 0;

pub const Demo = struct {
    ok: bool,
    frame: u32, // the original's FRAME, and the only thing the wobble reads
    scroller: Scroller,

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        self.ok = false;
        self.frame = 0;
        self.scroller.init();

        const fb = &zigos.lfbs[PLANE];
        fb.is_enabled = true;
        fb.setPalette(A.palette);
        // The border IS colour 0 on an ST, so the bars run edge to edge and down
        // into the bottom border: one overscan plane, every border open, and the
        // copper drives entries 0, 1 and 8 from the same handler as the flicker.
        fb.setOverscanBuffer();
        zg.copper.install(fb, &rasters.SLOTS, &rasters.tables, .{ .flicker = true });
        rasters.build(fb);
        zigos.setBackgroundColor(Color{ .r = 0, .g = 0, .b = 0, .a = 255 });

        fb.clearFrameBuffer(0);
        drawLogo(fb);
        zg.requestSong(MUSIC);
        self.ok = true;
    }

    /// The original's VBL: bump FRAME, then feed two more columns of the
    /// scrolltext into the edge ring.
    pub fn update(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = zigos;
        _ = dt;
        if (!self.ok) return;
        self.frame +%= 1;
        self.scroller.step();
    }

    /// MAIN, in its own order: clear, plot, fill, wrap, copy.
    pub fn render(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = dt;
        if (!self.ok) return;
        band.build(self.scroller.window(), self.frame);
        const dst = zg.blit.Dst.plane(&zigos.lfbs[PLANE]);
        band.draw(dst.buf, dst.stride, zg.HEIGHT);
    }
};

/// MAIN memcopies LOGO_BITMAP to the top of both screen buffers once, and never
/// touches it again.
fn drawLogo(fb: *zg.LogicalFB) void {
    for (0..A.LOGO_H) |y| {
        const at = (A.CONTENT_Y + y) * zg.PHYSICAL_WIDTH + A.CONTENT_X;
        @memcpy(fb.fb[at..][0..A.LOGO_W], A.logo[y * A.LOGO_W ..][0..A.LOGO_W]);
    }
}
