// --------------------------------------------------------------------------
// ANIMA -- "the soul": a new ZigMachine multipart demo (cart 107, 2026-10-23).
//
// THE DRAMATURGY.  An honest ST screen first, then the classic gag -- "oh...
// the KESTREL can do more than that!" -- then what an ST could never do, at
// 60 fps on the board.  Every part on ONE overscan plane, 400x280, every
// border earned by flickerBorder() from the HBL (raster.zig).
//
//   OLDSCHOOL (old.zig)  the borders opening line by line; six copper bars on a
//       drum reflected in the sea (a REAL raster on entry 0, bars.zig); a
//       breathing chrome logo blitted row by row (logo.zig); stars; a sine
//       scroller in the bottom border; glenz vectors (glenz.zig)
//   THE GAG (gag.zig)  the timing slips: rasters scramble, the logo tears, the
//       flicker misses the magic column and the borders fill with noise; the
//       ST freezes; a terminal types its verdict
//   TUNNEL (tunnel.zig)  a full-overscan textured, twisting tunnel, 2x2 pixels
//   THE MELT (roto.zig)  a rotozoomed, melting tile with A PALETTE PER LINE
//   THE KNOT (knot.zig)  a lit trefoil knot on the FPU, CHISEL triangles, in
//       a synthwave sunset that is a real raster
//   THE END (end.zig)  the logo over a copper plasma, the glenz finale, the
//       credits; it burns to white and starts over
// timeline.zig sequences them on one tick; parts.zig dispatches.
//
// BOARD BUDGET (apps/frame_cost.mjs, the recalibrated model): every part under
// the 1.75 Mc knee, the busiest (the melt) at ~1.6.  FRESCO is 0.7 for the one
// plane; nothing clears the plane that a part can redraw in place.
//
// MUSIC (music.zig).  Mad Max's Cuddly Demos "Reset" for the ST screen, silence
// at the crash, Tao's "Breath 2000" for the newschool, all on BARD.
//
// ASSETS.  Generated at build time (gen_anima.zig): the logo and the scroller
// font from apps/zig/assets/fonts/font16.raw (the 16X16-F5 font Matt supplied
// for music_debug), the tunnel map and texture, the rotozoom tile.  No other
// bitmap.
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
        if (fresh) parts.enter(p, fb, bl, jumped);
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
