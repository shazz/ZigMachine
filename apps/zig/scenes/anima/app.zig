// --------------------------------------------------------------------------
// ANIMA -- "the soul": a new ZigMachine one-screen demo (cart 107, 2026-10-23).
//
// THE SCREEN.  One overscan plane, 400x280, every border earned by the
// flicker trick (raster.zig).  Back to front:
//   - six copper bars turning round a drum, reflected in the sea under the
//     horizon: a REAL raster, entry 0 rewritten per physical line from the HBL,
//     so it runs through every open border (bars.zig);
//   - a 3D starfield where nothing else is drawn (stars.zig);
//   - the ANIMA logo, composed at compile time from a 16x16 font (EPX-smoothed
//     twice, bevelled, outlined, drop-shadowed: logo_gen.zig), BREATHING: each
//     of its rows is one CHISEL blit whose source row (a vertical stretch) and
//     x (a sine wobble) change every frame (logo.zig); its body is a chrome
//     copper ramp per line;
//   - glenz objects (cube, octahedron, icosahedron, a spiked star): rotated on
//     ZIGGY's FPU in f32 (a few hundred ops a frame), drawn as CHISEL triangles
//     ORed into the plane: overlapping faces mix (glenz.zig, objects.zig);
//   - a 32-pixel sine scroller in the bottom border, 8-pixel columns blitted
//     straight from the comptime font in cart RAM, rainbow copper body
//     (scroller.zig, font_gen.zig).
// The timeline (timeline.zig) earns the screen: DARK, OPEN, BREATHE, SCROLL,
// GLENZ.
//
// BOARD BUDGET (est. with apps/frame_cost.mjs): FRESCO 1.09 Mc for the one
// enabled plane; the rest is CHISEL time (~150 blits) and a few thousand
// stores.  Nothing clears the plane: each part erases only what it drew
// (stars by pixel, the glenz by its last box, the scroller by its band; the
// logo's rows are padded so each blit overwrites its own last row).
//
// MUSIC.  "Breath 2000" by Tao (SNDH archive: Tao/Breath_2000.sndh, flags
// ~ady, no STE DMA), the 68000 replay on BARD.  ANIMA is the breath: the tune
// is the screen's namesake.  SNDH archive tunes are distributed freely for
// the scene; credited here and in the scroller.
//
// ASSETS.  The only bitmap is apps/zig/assets/fonts/16X16-F5 (font16.raw,
// the bitmap font Matt supplied for music_debug's scroller, ZigMachine shelf);
// the logo and the 32-pixel font are built from it at compile time.
//
// KEYS.  Escape leaves.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const ZigOS = zg.ZigOS;
const P = @import("palette.zig");
const T = @import("timeline.zig");
const raster = @import("raster.zig");
const bars = @import("bars.zig");
const parts = @import("parts.zig");
const grade = @import("grade.zig");
const music = @import("music.zig");

pub const PLANE = 0;
pub const MUSIC = music.OLD; // the first tune (music.zig has both)

const TICK_MS: f32 = 1000.0 / 60.0;
const MAX_TICKS: u32 = 3;
const K_ESC: u32 = 0xE012;

// Module state, so the harness (testapi.zig) can read it.
pub var tick: u32 = 0;
pub var ok: bool = false;
pub var wants_quit: bool = false;
pub var os: ?*ZigOS = null; // for the terminal's printText (gag.zig)
var drawn_tick: ?u32 = null; // the tick the plane shows; null = redraw from scratch
var shown: T.Part = .old;

comptime {
    // the default planes plus one overscan buffer must fit the VRAM pool
    // (vramAlloc has no guard: an overrun lands in the physical framebuffer)
    if (4 * zg.NORMAL_FB_BYTES + zg.OVERSCAN_FB_BYTES > zg.VRAM_BYTES) @compileError("anima: VRAM");
}

pub const Demo = struct {
    acc: f32,
    blitter: zg.Blitter,

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        self.acc = 0;
        self.blitter = .{};
        self.blitter.init();
        tick = 0;
        drawn_tick = null;
        wants_quit = false;
        zigos.setBackgroundColor(zg.Color.fromRGBA(P.ste(0, 0, 0)));
        const fb = &zigos.lfbs[PLANE];
        for (1..zg.NB_PLANES) |p| zigos.lfbs[p].is_enabled = false;
        fb.is_enabled = true;
        P.install(fb.palette);
        raster.install(fb); // overscan buffer + the HBL (cleared to 0)
        plane = fb.fb;
        os = zigos;
        music.reset();
        music.follow(0);
        ok = true;
    }

    pub fn update(self: *Demo, _: *ZigOS, dt_ms: f32) void {
        if (!ok) return;
        if (dt_ms > 0) self.acc = @min(self.acc + dt_ms, TICK_MS * @as(f32, @floatFromInt(MAX_TICKS)));
        var n: u32 = 0;
        while (self.acc >= TICK_MS and n < MAX_TICKS) : (n += 1) {
            self.acc -= TICK_MS;
            tick +%= 1;
        }
    }

    pub fn render(self: *Demo, zigos: *ZigOS, _: f32) void {
        if (!ok) return;
        const fb = &zigos.lfbs[PLANE];
        const bl = &self.blitter;
        const t = tick % T.LOOP;
        pulse(zigos);
        music.follow(t);
        const p = T.part(t);
        // a first frame, a new part or a timeline jump: the part starts afresh
        const jumped = if (drawn_tick) |d| t < d or t > d + MAX_TICKS else true;
        const fresh = jumped or p != shown;
        if (fresh) parts.enter(p, fb, bl, t, jumped);
        parts.draw(p, fb, bl, t, fresh, drawn_tick != t);
        shown = p;
        drawn_tick = t;
    }

    pub fn key(_: *Demo, cp: u32) void {
        if (cp == K_ESC) wants_quit = true;
    }

    pub fn pollCart(_: *Demo) i32 {
        return if (wants_quit) -1 else 0;
    }
};

/// Jump the timeline (the harness and frame_cost measure each phase this way).
pub fn jump(t: u32) void {
    tick = t;
}

var plane: [*]u8 = undefined;
var last_vol: u8 = 0;
var kick: u32 = 0;

/// The music drives the bars: a channel volume jumping up (a drum, a new note)
/// lights them for a dozen frames (bars.beat 3, fading to 0).
fn pulse(zigos: *const ZigOS) void {
    const r = zigos.ym_regs;
    const v = @max(r[8] & 15, @max(r[9] & 15, r[10] & 15));
    if (v >= last_vol + 3) kick = 12 else if (kick > 0) kick -= 1;
    last_vol = v;
    bars.beat = kick / 4;
    grade.beat = @intCast(kick / 4);
}

/// Plane 0's pixels (the harness reads them).
pub fn planePtr() [*]u8 {
    return plane;
}

pub fn phase() T.Phase {
    return T.phase(tick % T.LOOP);
}
