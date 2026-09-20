// --------------------------------------------------------------------------
// THE SILENTS — "HYBRID GLENZ" (1993).
// Code and design by SPIROU and CUDDLEY, graphics by CHEVRON, music by BLAIZER.
// The scrolltext is theirs, word for word.
//
// Ported from the CODEF HTML5 remake (wab.com screen 417, MIT), kept at
// prototypes/codef/417/. Assets: tools/private_tools/tsl_hybridglenz_assets.py.
// There is no depacker intro to skip: init() loads, then part1() IS the demo's
// own opening (screen.js:224).
//
// GEOMETRY. The remake's canvas is 720x568, an AMIGA screen doubled — and the
// doubling grid is offset a row: columns pair (0,1),(2,3)... but rows pair
// (1,2),(3,4)..., measured on all five PNGs. So a 1x row r is 2x rows 2r+1 and
// 2r+2, which is exactly why screen.js puts the panel at the odd y=171 and
// interlaces the two glenz objects at 171+u / 173+u. That leaves 2x rows 1..566
// = 283 usable 1x rows, NOT 284. Content ends at row 273 (the bottom of the
// scroller bar), so the 3 rows this plane cannot hold (283 -> 280) are cropped
// off the BOTTOM, where they are plain '#334444'. Nothing is lost and nothing
// is squashed. The 360 columns are centred in the 400-wide overscan plane
// (X_OFF = 20); the bar and the scroller then run the full raster, borders
// included, because on the hardware they would.
//
// ONE PLANE. Everything the remake layers on one canvas layers on one plane,
// which is also the only way a port of this size holds 60 fps. Its palette is
// budgeted in assets.zig; the three alpha fades are palette moves.
//
// THE GLENZ is the blitter's, MT_OR_BC, one pass, with a halftone of alternate
// rows standing in for the remake's 2-row interlace composite. See glenz.zig.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const hw = @import("hardware");
const ZigOS = zg.ZigOS;
const Color = zg.Color;
const c3 = zg.zig3d;
const zx0 = @import("depackers").zx0;
const packed_assets = @import("packed_assets");

const A = @import("tsl_hybridglenz/assets.zig");
const stage = @import("tsl_hybridglenz/stage.zig");
const glenz = @import("tsl_hybridglenz/glenz.zig");
const obj = @import("tsl_hybridglenz/obj.zig");
const timeline = @import("tsl_hybridglenz/timeline.zig");
const Scroller = @import("tsl_hybridglenz/scroller.zig").Scroller;

// The screen's own tune, an Amiga ProTracker module (assets/hybridglenz.mod).
// An SNDH was not looked for: this is Amiga code and Blaizer's MOD is what it
// played. The MOD title tag reads "setup2" — it is a ProWizard rip.
const MUSIC = "hybridglenz.mod";

const PLANE = 0;

// go() (screen.js:281-291): the group turns before the draw, every frame.
const STEP1 = c3.Vec3{ .x = 0.01, .y = 0.022, .z = 0.028 };
const STEP2 = c3.Vec3{ .x = 0.012, .y = 0.02, .z = 0.028 };

var palette_scratch: [256]Color = undefined;

pub const Demo = struct {
    ok: bool,
    images: A.Images,
    blitter: zg.Blitter,
    lens: c3.Lens,
    objects: [2]glenz.Glenz,
    scroller: Scroller,
    clock: f32, // seconds since init: the whole timeline's t
    morph: f32, // seconds since tween3d() armed the 21 s chain
    fade_sig: f32, // last uploaded fade state (see timeline.fadeSignature)

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        self.ok = false;
        self.clock = 0;
        self.morph = 0;
        self.fade_sig = -1; // nothing uploaded yet: force the first palette
        self.scroller.init();
        self.blitter.init();
        self.lens = c3.Lens.init(glenz.CANVAS, glenz.CANVAS, glenz.FOV, glenz.NEAR, glenz.FAR);
        // Object 1 owns the ODD plane rows (its canvas row 0 lands on 85),
        // object 2 the even ones (row 0 on 86) — the interlace, in hardware.
        self.objects[0].init(&obj.MORPH1, STEP1, stage.PANEL_X, stage.PANEL_Y, glenz.ODD_ROWS);
        self.objects[1].init(&obj.MORPH2, STEP2, stage.PANEL_X, stage.PANEL_Y + 1, glenz.EVEN_ROWS);

        const buf = freeRam(A.TOTAL) orelse return fail("no free RAM for the assets");
        if (zx0.depack(packed_assets.tsl_hybridglenz, buf) == null) return fail("depack failed");
        self.images = A.Images.split(buf);

        const fb = &zigos.lfbs[PLANE];
        fb.is_enabled = true;
        palette_scratch = A.palette();
        fb.setPalette(palette_scratch);
        fb.openBorders(.all); // the Amiga screen is 283 rows: it needs them
        fb.clearFrameBuffer(A.BG);
        zg.requestSong(MUSIC);
        self.ok = true;
    }

    pub fn update(self: *Demo, zigos: *ZigOS, dt: f32) void {
        if (!self.ok) return;
        self.clock += dt / 1000.0; // the host's dt is milliseconds
        const s = timeline.State.at(self.clock);
        // The palette only moves while a fade does; re-uploading 256 entries
        // every frame of go() would be pure waste.
        const sig = timeline.fadeSignature(s);
        if (sig != self.fade_sig) {
            self.fade_sig = sig;
            timeline.applyFades(s, &palette_scratch);
            zigos.lfbs[PLANE].setPalette(palette_scratch);
        }
        if (!s.running) return;

        // tween3d() re-arms from onComplete, so the chain restarts on the frame
        // AFTER the last morph lands — 21 s plus one frame, not exactly 21.
        self.morph += dt / 1000.0;
        if (self.morph >= obj.CYCLE) self.morph = 0;
        for (&self.objects) |*o| o.update(self.morph);
        self.scroller.update();
    }

    pub fn render(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = dt;
        if (!self.ok) return;
        const fb = &zigos.lfbs[PLANE];
        const bl = &self.blitter;
        const s = timeline.State.at(self.clock);
        stage.background(fb, bl);
        if (s.running) self.drawMain(fb, bl) else self.drawIntro(fb, bl, s);
    }

    /// part1(), in its own drawing order.
    fn drawIntro(self: *Demo, fb: *zg.LogicalFB, bl: *zg.Blitter, s: timeline.State) void {
        if (s.panel_on) stage.panel(fb, bl);
        // Only while it is opaque: once the alpha tween starts the square sits
        // exactly on the panel, and the blend it makes IS palette entry 0.
        if (s.sq_solid) stage.square(fb, bl, s.sq_x, s.sq_rot, s.sq_size);
        const rects = [3]A.Rect{ A.TXT1, A.TXT2, A.TXT3 };
        for (s.txt, self.images.txt, rects) |alpha, pixels, r| {
            if (alpha > 0) stage.text(fb, bl, pixels, r);
        }
        if (s.logo_on) stage.logo(fb, bl, self.images.logo);
        stage.bar(fb, bl, @intFromFloat(@round(s.bar_y)));
    }

    /// go(), likewise: panel, both glenz objects, logo, bar, scrolltext.
    fn drawMain(self: *Demo, fb: *zg.LogicalFB, bl: *zg.Blitter) void {
        stage.panel(fb, bl);
        for (&self.objects) |*o| o.draw(fb, bl, &self.lens);
        stage.logo(fb, bl, self.images.logo);
        const bar_y: i16 = @intFromFloat(timeline.BAR_TO / 2);
        stage.bar(fb, bl, bar_y);
        self.scroller.draw(fb, bl, self.images.font, bar_y + stage.TEXT_DY, stage.PLANE_W);
    }
};

fn fail(why: []const u8) void {
    zg.Console.log("tsl_hybridglenz: {s}", .{why});
}

/// `len` bytes of the cart's RAM window above its statics and stack.
fn freeRam(len: usize) ?[]u8 {
    if (hw.hwRamFree() < len) return null;
    const base: usize = hw.hwRamBase() + hw.hwRamUsed();
    return @as([*]u8, @ptrFromInt(base))[0..len];
}
