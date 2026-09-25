// --------------------------------------------------------------------------
// The intro (main thread TEXT $D8..$168, VBL handler 1 at $4A2), as a
// schedule of the program VBL counter c ($5CD80, 1 on the first VBL).
//
// The waits at $4DA are MUSIC TICKS, not VBLs: they wait for word $B0, which
// the MOD replay's Timer A bumps once per DMA buffer of 1017 frames at
// 49170 Hz. Hatari measured 3864 ticks per 4000 VBLs, so a tick is
// 4000/3864 = 500/483 VBL; time is kept here in 1/483 VBL units so the whole
// schedule is exact integer arithmetic. The tick grid's phase (TICK0 = 5 VBL)
// and a 4-VBL start-up SLACK after the replay starts are FITTED, not read
// from the code: the code alone puts the text phase at c = 573, the Hatari
// snapshots prove 577. That 4-VBL latency (DMA start / early Timer A ticks)
// is the one approximation in the port.
// --------------------------------------------------------------------------
const assets = @import("assets.zig");

const D: u32 = 483; // time units per VBL
const TICK: u32 = 500; // time units per music tick
const TICK0: u32 = 5 * D; // phase of the tick grid
const SLACK: u32 = 4; // VBLs, fitted (see above)

pub const FLASH_STEPS = 64; // $59A
pub const FADE_STEPS = 64; // $3DE
pub const SLIDE_LINES = 60; // $3C6

/// The first counter value c at which each step is on screen.
pub const Schedule = struct {
    flash: [FLASH_STEPS]u32, // step s: all 256 entries = 252 - 4s grey
    logo: u32, // $3AC copies the logo to screen line 65
    fade: [FADE_STEPS]u32, // step k: each channel = min(4k, target)
    slide: [SLIDE_LINES]u32, // step s: screen base = 320 * s bytes further
    text: u32, // handler 2's first VBL: text frame n = 0
};

pub const at: Schedule = build();

fn vbl(t: *u32) void {
    t.* = (t.* / D + 1) * D;
}
fn tick(t: *u32) void {
    t.* = TICK0 + ((t.* - TICK0) / TICK + 1) * TICK;
}
/// A step done at time t is seen by the first VBL after it.
fn shown(t: u32) u32 {
    return t / D + 1;
}

fn build() Schedule {
    @setEvalBranchQuota(20000);
    var s: Schedule = undefined;
    var t: u32 = 0;
    vbl(&t); // $E4, then $F2 starts the MOD
    t += SLACK * D;
    for (0..5) |_| vbl(&t); // $F8..$114 (two of them set the CODEC gain)
    if (t < TICK0) @compileError("the first tick wait precedes the tick grid");
    tick(&t); // $118
    tick(&t); // $11C
    for (&s.flash) |*f| {
        tick(&t);
        f.* = shown(t);
    }
    s.logo = shown(t); // $134, the palette is black by now
    for (0..50) |_| tick(&t); // $13A
    for (&s.fade) |*f| {
        tick(&t);
        f.* = shown(t);
    }
    for (0..210) |_| tick(&t); // $14C
    for (&s.slide) |*f| {
        vbl(&t);
        f.* = shown(t);
    }
    for (0..101) |_| tick(&t); // $158, $15C
    vbl(&t); // $168, handler 2 installed
    s.text = t / D;
    return s;
}

comptime {
    // What model.py's float schedule gives (and the SPEC's timeline table).
    if (at.flash[0] != 13 or at.flash[63] != 78 or at.logo != 78) @compileError("flash off the model");
    if (at.fade[0] != 131 or at.fade[63] != 196) @compileError("fade-in off the model");
    if (at.slide[0] != 414 or at.slide[59] != 473) @compileError("slide off the model");
    if (at.text != 577) @compileError("the text phase must start at c = 577");
}

fn done(steps: []const u32, c: u32) u32 {
    var n: u32 = 0;
    for (steps) |s| n += @intFromBool(s <= c);
    return n;
}

pub fn slide(c: u32) u32 {
    return done(&at.slide, c);
}

/// Handler 1's palette buffer ($1C22) as VBL c copies it to $FF9800.
pub fn palette(c: u32, out: *[256]u32) void {
    const k = done(&at.fade, c);
    if (k > 0) {
        for (out, 0..) |*e, i| e.* = fadeIn(assets.long(assets.logo_pal, i), k);
        return;
    }
    const s = done(&at.flash, c);
    if (s > 0) {
        const v: u32 = 0xFC - 4 * (s - 1);
        @memset(out, v << 24 | v << 16 | v);
        return;
    }
    for (out, 0..) |*e, i| e.* = assets.long(assets.init_pal, i);
}

/// $3DE after k steps: every R,G,B byte climbs by 4 from 0, clamped at its target.
fn fadeIn(target: u32, k: u32) u32 {
    var out: u32 = 0;
    inline for (.{ 24, 16, 0 }) |sh| out |= @min(target >> sh & 0xFF, 4 * k) << sh;
    return out;
}
