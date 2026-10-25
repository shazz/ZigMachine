// --------------------------------------------------------------------------
// PHENOMENA intro (Amiga; code Photon, music Firefox, graphics Terminator),
// ported from the CODEF remake at wab.com/?screen=560 (Dimmat, with fixes by
// Shiftcode, 2025; reference in prototypes/codef/560/).
//
// One MEDIUM overscan plane (geom.zig says why), one palette, painted in
// screen.js's order; what changes per scanline is a register (raster.zig).
// seq.zig is the remake's chain of phases, paint.zig what each phase draws
// once, dna.zig / dna_draw.zig the rotating scroller.
//
// MUSIC: 'rasta man.mod' ("rasta man-firefox"), the remake's own file, a
// 4-channel ProTracker module, started where screen.js starts it: when the
// lower bar is in, as the photon drops. Nothing plays before it.
//
// Escape / Back leave. A click in the remake sets `finished`, but go() no
// longer acts on it, so Fire does nothing here either.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const ZigOS = zg.ZigOS;
const G = @import("geom.zig");
const A = @import("assets.zig");
const seq = @import("seq.zig");
const dna = @import("dna.zig");
const dna_draw = @import("dna_draw.zig");
const paint = @import("paint.zig");
const raster = @import("raster.zig");

pub const PLANE: usize = 0;
pub const MUSIC = "rasta_man.mod";

const K_ESC: u32 = 0xE012;
const DIR_BACK: u8 = 6;

pub var ok: bool = false;
pub var wants_quit: bool = false;
var drawn: seq.Phase = .page1;
var fresh: bool = true; // nothing drawn yet
var photon_at: i32 = -1; // first canvas row of the photon on screen, -1 = none

pub const Demo = struct {
    pub fn init(self: *Demo, zigos: *ZigOS) void {
        _ = self;
        ok = false;
        wants_quit = false;
        fresh = true;
        drawn = .page1;
        photon_at = -1;
        zigos.setBackgroundColor(.{ .r = 0, .g = 0, .b = 0, .a = 255 });
        const fb = &zigos.lfbs[PLANE];
        fb.is_enabled = true;
        fb.setMediumOverscan(); // 800x280, the whole raster; content at (80, 20)
        paint.blitter.init();
        raster.install(fb);
        paint.clear(fb);
        seq.reset();
        dna.reset();
        dna_draw.reset();
        ok = true;
    }

    pub fn update(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = self;
        _ = zigos;
        _ = dt; // frame-based, like the remake's requestAnimationFrame chain
        if (!ok) return;
        seq.step();
        if (seq.music_due) {
            seq.music_due = false;
            zg.requestSong(MUSIC);
        }
    }

    pub fn render(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = self;
        _ = dt;
        if (!ok) return;
        const fb = &zigos.lfbs[PLANE];
        const v = seq.view;
        if (fresh or v.phase != drawn) enter(fb, v.phase);
        fresh = false;
        drawn = v.phase;
        frame(fb, v);
    }

    pub fn key(self: *Demo, cp: u32) void {
        _ = self;
        if (cp == K_ESC) wants_quit = true;
    }

    pub fn input(self: *Demo, dir: u8) void {
        _ = self;
        if (dir == DIR_BACK) wants_quit = true;
    }

    pub fn pollCart(self: *Demo) i32 {
        _ = self;
        return if (wants_quit) -1 else 0;
    }
};

/// What a phase draws once, on its first frame.
fn enter(fb: *zg.LogicalFB, p: seq.Phase) void {
    switch (p) {
        .page1, .page2 => {
            paint.clear(fb);
            if (p == .page1) paint.page(fb, &paint.PAGE1) else paint.page(fb, &paint.PAGE2);
        },
        .logo => {
            paint.clear(fb);
            paint.panel(fb);
            paint.logo(fb);
        },
        .bar_top => {
            raster.logoNormal(fb);
            paint.barLines(fb, G.BAR_TOP);
        },
        .bar_bottom => paint.barLines(fb, G.BAR_BOTTOM),
        .drop => raster.photon(fb, A.rgb3(255, 255, 255)),
        .fade => {},
        .main => dna_draw.reset(),
    }
}

/// What changes every frame.
fn frame(fb: *zg.LogicalFB, v: seq.View) void {
    switch (v.phase) {
        .page1 => raster.textBar(fb, v.rb2),
        .page2 => raster.textFlat(fb, A.rgb(A.GREY, @intCast(@min(v.level, 100)))),
        .logo => {
            raster.bars(fb, 0, 0);
            if (v.level <= 100) raster.logoGrey(fb, @intCast(v.level)) else raster.logoWhite(fb, @intCast(200 - v.level));
        },
        .bar_top => raster.bars(fb, @intCast(v.level), 0),
        .bar_bottom => raster.bars(fb, 100, @intCast(v.level)),
        .drop, .fade, .main => {
            raster.bars(fb, 100, 100);
            if (v.photon != photon_at) {
                if (photon_at >= 0) paint.photon(fb, photon_at, true);
                paint.photon(fb, v.photon, false);
                photon_at = v.photon;
            }
            if (v.phase == .fade) raster.photon(fb, A.rgb(A.REDFADE, @intCast(v.level)));
            if (v.phase == .main) {
                raster.photon(fb, A.rgb(A.HUE, v.hue % 360)); // hsl(360) is hsl(0)
                dna_draw.draw(fb, v.t, v.rect_w);
            }
        },
    }
}
