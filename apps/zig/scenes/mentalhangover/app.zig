// --------------------------------------------------------------------------
// MENTAL HANGOVER -- the circular outline text over the mountain, ported from
// github.com/olivierh59500/go-mentalhangover (the Amiga original's greeting
// screen, re-created in Go/Ebitengine).
//
// THE SCREEN.  A 352x272 canvas in the centre of a 400x280 overscan plane at
// (24,4): 49 two-scanline copper bands on rows 102..199, eight glyphs projected
// around a circle (radius driven by the source's two 256-byte waves), a shadow
// pass, then the mountain mask.  The Go blits the raster as a picture; here its
// 49 words repaint palette entry 0 per PHYSICAL line in the plane's HBL, so the
// bands run into the open side borders.  That is the screen's whole colour
// budget: 0 raster/black, 1 text blue, 2 text shadow, 3 mountain black.
//
// SCALE.  The Go canvas is 352x272, not 2x (its 704x544 screenshots are exactly
// double).  Nothing is halved: the canvas maps 1:1.
//
// ST COLOUR.  The source's copper words are RGB12.  Each channel is snapped to
// the nearest of the ST's eight 3-bit levels and displayed at n*255/7; the
// text is RGB12 (3,10,13) -> ST levels (1,5,6) and the shadow (0,6,11)
// -> levels (0,3,5), each displayed at n*255/7.
//
// CLOCK.  One clock step per 50 Hz tick, 3341 steps: 33 fade-in, 3275 active
// steps (the first 3274 match the source's own CPU fixture; the 3275th reaches
// the terminator and hides the text), then 33 fade-out.  During the fade-out
// the production keeps the raster and the mountain and fades only the raster;
// at the last step it returns and the screen is black.  The cart holds that
// black screen (the Go hands over to its next unit).
//
// MUSIC.  The production ships ProTracker module "madness took me" as
// assets/raw/madness.mod; the repo's MOD path is used for it.  No SNDH of this
// tune exists in the archive (sndh_index.py found no madness / mental hangover /
// uncle tom match), so this is the only faithful source.
//
// KEYS.  Escape leaves, as in cmd/mentalhangover/main.go.  The Go's F toggles
// Ebitengine fullscreen, which is host chrome, not demo input; it is left to
// the host and deliberately does not quit.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const ZigOS = zg.ZigOS;
const Color = zg.Color;

const A = @import("assets.zig");
const clockmod = @import("clock.zig");
const renderer = @import("render.zig");

pub const PLANE = 0;
pub const MUSIC = "mentalhangover.mod";

/// One 50 Hz frame, in host MICROseconds: the accumulator is an integer (the
/// host's f32 dt is converted once a frame, never accumulated in float).
const TICK_US: u32 = 20_000;
const MAX_TICKS: u32 = 2;
const MAX_DT_US: u32 = 200_000;

const K_ESC: u32 = 0xE012;

// --- module-level state, so the harness can read every drawn word ----------
pub var clock: clockmod.Clock = undefined;
pub var ok: bool = false;
pub var wants_quit: bool = false;
/// The black end screen is on the plane: nothing more to draw.
var settled: bool = false;

pub const Demo = struct {
    acc_us: u32,

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        self.acc_us = 0;
        ok = false;
        settled = false;
        wants_quit = false;
        clock = clockmod.Clock.init();
        renderer.raster_level = 0;

        zigos.setBackgroundColor(Color.fromRGBA(A.BLACK));
        const fb = &zigos.lfbs[PLANE];
        fb.is_enabled = true;
        fb.openBorders(.all); // an overscan plane, every border earned by flicker
        renderer.install(fb); // ... and the HBL paints entry 0 per physical line

        fb.setPaletteEntry(renderer.IDX_BG, Color.fromRGBA(A.BLACK));
        fb.setPaletteEntry(renderer.IDX_TEXT, Color.fromRGBA(A.TEXT_RGBA));
        fb.setPaletteEntry(renderer.IDX_SHADOW, Color.fromRGBA(A.SHADOW_RGBA));
        fb.setPaletteEntry(renderer.IDX_MOUNTAIN, Color.fromRGBA(A.MOUNTAIN_RGBA));
        fb.clearFrameBuffer(0);
        renderer.reset(); // the plane is all black now: compose every row next frame

        zg.requestSong(MUSIC);
        ok = true;
    }

    fn tick50() void {
        _ = clock.step();
    }

    pub fn update(self: *Demo, _: *ZigOS, dt_ms: f32) void {
        if (!ok) return;
        // dt > 0 is false for NaN; the cap stops a stalled tab replaying minutes.
        if (dt_ms > 0) {
            const dt_us: u32 = if (dt_ms >= 200.0) MAX_DT_US else @intFromFloat(dt_ms * 1000.0 + 0.5);
            self.acc_us = @min(self.acc_us + dt_us, TICK_US * MAX_TICKS);
        }
        var n: u32 = 0;
        while (self.acc_us >= TICK_US and n < MAX_TICKS) {
            self.acc_us -= TICK_US;
            n += 1;
            tick50();
        }
    }

    pub fn render(self: *Demo, zigos: *ZigOS, _: f32) void {
        _ = self;
        if (!ok) return;
        const fb = &zigos.lfbs[PLANE];
        if (clock.done) {
            // The Go's Draw returns before any layer once done: black, no
            // raster, no mountain.  level 0 makes every copper word black.
            renderer.raster_level = 0;
            if (!settled) renderer.drawFrame(fb, &clock, false, false);
            settled = true;
            return;
        }
        renderer.raster_level = clock.level;
        renderer.drawFrame(fb, &clock, clock.active, true);
    }

    pub fn key(self: *Demo, cp: u32) void {
        _ = self;
        switch (cp) {
            K_ESC => wants_quit = true,
            else => {},
        }
    }

    pub fn pollCart(self: *Demo) i32 {
        _ = self;
        return if (wants_quit) -1 else 0;
    }
};
