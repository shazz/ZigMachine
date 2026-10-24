// --------------------------------------------------------------------------
// NOEXTRA's cart: the intro, then the main screen, on ONE overscan plane whose
// HBL flickers every border open and replays the band's rasters (rasters.zig).
//
// The plane is a 400x340 buffer panned vertically (setOverscanScrollPlane),
// because that is what the original's "vertical hardware scroll" is: its
// screen is a 350-line, 160-byte-stride buffer and the VBL moves the display
// start (by the sync-line trick, $B12E) to line `bob`, so content rises by bob
// lines. Here the window's pan IS bob: the logos, bars and band are drawn once
// and never again; per frame only the scroller's 20 columns are written.
//
// Buffer row = ST line + PAD (rasters.zig). The intro's D.H.S screen was a
// plain 320x200 one (ST line 0 = normal line 29 of the capture): its logo is
// drawn once at row 29 + PAD + 59 and the pan runs 59 - y, so it shows at y.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const A = @import("assets.zig");
const T = @import("timeline.zig");
const R = @import("rasters.zig");
const scroller = @import("scroller.zig");

const ZigOS = zg.ZigOS;
const LogicalFB = zg.LogicalFB;

/// Mega 4 Disk Mag by Powa Pixel: the SNDH RASTERS.PRG carries at +0x10872 (its 20,592
/// bytes of code identical to the archive's Powapixel/Mega_4_Disk_Mag.sndh), init d0 = 1.
const MUSIC = "mega4_disk_mag.sndh";
const BUF_H = 340; // 59 (deepest bob) + 280 rows of window, rounded
const BOB_MAX = T.BOB_MAX;
const NORMAL_TOP = 29; // the intro's 320x200 screen, in capture rows
const DHS_ROW = NORMAL_TOP + R.PAD + BOB_MAX;
const DHS_X = 64; // $D5A8: lea $20(a6) -> 32 bytes = 64 px in
const LOW_VIEW = 200;
const BLACK_PAL = [_]u32{A.rgba(0)} ** 256;

// A pan past BUF_H - 280 reads outside the buffer without trapping, and the
// blitter clips a 400-stride destination at row 280: pin what the layout needs.
comptime {
    const H = zg.PHYSICAL_HEIGHT;
    if (BUF_H < H + BOB_MAX or DHS_ROW + A.DHS_H > H) @compileError("noextra: buffer too short");
    if (R.PAD + 227 + A.BOTTOM_H > BUF_H or R.PAD + 227 - LOW_VIEW + A.BOTTOM_H > H) @compileError("noextra: ZORRO 2 out of reach");
}

// NOTE: demo_main.zig holds the cart as `var cart: Cart = undefined`, so field
// defaults are NEVER applied: init() sets every field.
pub const Demo = struct {
    blitter: zg.Blitter,
    f: u32, // frames since init, one per original VBL
    bob: T.Bob,
    shown_bob: u16, // the bob the VBL computed LAST frame: what this frame displays
    shown: T.Stage, // what the plane holds

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        zg.Console.log("NOEXTRA init", .{});
        self.blitter = .{};
        self.blitter.init();
        self.f = 0;
        self.bob = .{};
        self.shown_bob = 0;
        self.shown = .cut; // nothing drawn yet
        R.stop();
        zigos.setBackgroundColor(.{ .r = 0, .g = 0, .b = 0, .a = 255 });
        const fb = &zigos.lfbs[0];
        fb.is_enabled = true;
        fb.setOverscanScrollPlane(R.PW, BUF_H);
        fb.setFrameBufferHBLHandlerPure(zg.OVERSCAN_MAGIC_X, R.hbl);
        setPalette(fb, &dhsPalette()); // $D51C: no wait, the colours are in at once
        zg.requestSongTune(MUSIC, 1);
    }

    pub fn update(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = self;
        _ = zigos;
        _ = dt;
    }

    pub fn render(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = dt;
        const fb = &zigos.lfbs[0];
        const st = T.stage(self.f);
        switch (st) {
            .hold => self.intro(fb, A.bob[0]),
            .bounce => self.intro(fb, T.introY(self.f - T.HOLD_FRAMES)),
            .still => {},
            .cut => setPalette(fb, &BLACK_PAL), // $D4B6: black, no wait
            .main => self.main(fb, self.f - T.MAIN_START),
        }
        self.f +%= 1;
    }

    fn intro(self: *Demo, fb: *LogicalFB, y: u16) void {
        if (self.shown != .hold) {
            self.blitter.blitImage(fb, R.SX + DHS_X, DHS_ROW, A.dhs, A.DHS_W, 0, 0, A.DHS_W, A.DHS_H, null);
            self.shown = .hold;
        }
        fb.setScroll(0, BOB_MAX - y);
    }

    // What the ST displays in main frame k (measured: two Hatari captures fit
    // with zero ink pixels and every band line): the band's colours from frame
    // k's sine pointers, but the bob and the scroller of frame k - 1. The VBL arms
    // Timer B and the sync-scroll table from the bob it stored the frame before,
    // and the scroller draws into the buffer the NEXT VBL shows.
    fn main(self: *Demo, fb: *LogicalFB, k: u32) void {
        if (self.shown != .main) self.layout(fb);
        fb.setScroll(0, self.shown_bob);
        R.frame(k, self.shown_bob);
        if (k > 0) scroller.draw(fb, k - 1);
        self.shown_bob = self.bob.step();
    }

    /// The static screen, drawn once: $AB06..$AB9A copy the logos into the buffers.
    fn layout(self: *Demo, fb: *LogicalFB) void {
        fb.clearFrameBuffer(0);
        self.blitter.blitImage(fb, R.SX, R.PAD + 9, A.toplogo, A.LOGO_W, 0, 0, A.LOGO_W, A.TOP_H, null);
        // The machine's blitter clips a 400-stride destination at row 280, and ZORRO 2
        // runs to buffer row 333: draw it through a view of the buffer 200 rows down.
        var low = fb.*;
        low.fb = fb.fb + LOW_VIEW * @as(usize, fb.stride);
        self.blitter.blitImage(&low, R.SX, R.PAD + 227 - LOW_VIEW, A.bottomlogo, A.LOGO_W, 0, 0, A.LOGO_W, A.BOTTOM_H, null);
        R.drawStatic(&self.blitter, fb);
        setPalette(fb, &A.mainPalette());
        self.shown = .main;
    }
};

fn dhsPalette() [256]u32 {
    var p = [_]u32{A.rgba(0)} ** 256;
    for (1..16) |i| p[i] = A.rgba(A.pal_dhs[i]);
    return p;
}

fn setPalette(fb: *LogicalFB, p: *const [256]u32) void {
    R.setRange(fb, 0, p);
}
