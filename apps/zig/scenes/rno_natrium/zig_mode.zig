// --------------------------------------------------------------------------
// NATRIUM ZIG mode: the KESTREL showcase of the intro, toggled with Z.
//
// The original stays the default and is never touched: the sequencer keeps
// ticking the 68000 program on its ST screens in both modes (timeline.zig),
// and this module only READS it. ZIG mode disables plane 0 and shows plane 1,
// a 400x280 overscan plane with every border opened (openBorders(.all): a
// flicker on every line). Z again re-enables plane 0, which re-expands the
// shown ST screen: the original's very frame.
//
// What plane 1 shows, by the sequencer's state:
//   p2 tunnel   zig_tunnel  CHISEL MAP, full window, every frame
//   p2 wobble   zig_wobble  ZIGGY + ZM-X tex2d, full window, every frame
//   p3/p6 env   zig_env     ZM-X mulsh setup, ONE CHISEL AFFINE, every frame
//   p7 roto     zig_roto    ZM-X mulsh, ONE CHISEL AFFINE, full window
//   p1 dots     zig_dots    the curtains/logos blit + ONE CHISEL MAP (OR), full window
//   p5 twister  zig_twist   ZIGGY, the strip's columns, full window
//   the rest    the original's shown screen expanded at (40, 40), black
//               borders (credits, the zooms, the box parts' set-up): as is
// The effect parts use 7 (box) or 13 (env) true colours, entries 16..28, the
// mean of the pens the original dithered between (zig_math.zig).
// Time: the part's VBL count f plus the fraction of the next VBL the host has
// already run (Q10), so the board's 60 Hz frames each get their own picture
// from a 50 Hz timeline.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const st = @import("st.zig");
const A = @import("assets.zig");
const T = @import("timeline.zig");
const M = @import("zig_math.zig");
const R = @import("zig_res.zig");
const tunnel = @import("zig_tunnel.zig");
const wobble = @import("zig_wobble.zig");
const env = @import("zig_env.zig");
const roto = @import("zig_roto.zig");
const dots = @import("zig_dots.zig");
const twist = @import("zig_twist.zig");

pub const ORIGINAL_PLANE = 0;
pub const PLANE = 1;
const VBL_US: u32 = 20_000;

pub const Part = enum(u8) { classic, tunnel, wobble, env, roto, dots, twister };

pub var on: bool = false;
var tried = false; // built at most once: a second try would take VRAM again
var usable = false;
var fresh = false; // just switched on: the part's set-up runs again
pub var part: Part = .classic;
/// The time the last frame drew (Q10 VBLs) (zig_api).
pub var time: u32 = 0;
/// The machine handle of the last toggle, for the harness's reads (zig_api).
pub var os: ?*zg.ZigOS = null;

/// Z: on or off. Stays off when cart RAM or VRAM cannot hold the mode.
pub fn toggle(zigos: *zg.ZigOS) void {
    os = zigos;
    if (!on) {
        if (!tried) {
            tried = true;
            usable = build(zigos);
        }
        if (!usable) return;
    }
    on = !on;
    fresh = on;
    zigos.lfbs[ORIGINAL_PLANE].is_enabled = !on;
    zigos.lfbs[PLANE].is_enabled = on;
}

/// Cart RAM: bg 112 KB, the textures 48 KB, the tunnel map 422 KB, spans 56 KB,
/// a scratch ST screen, the dot map 219 KB, the chrome strip 32 KB; VRAM: the
/// 400x280 plane.
fn build(zigos: *zg.ZigOS) bool {
    const m = zg.mem.mark();
    if (!(R.alloc() and tunnel.build() and roto.build() and env.build() and dots.build() and twist.build())) {
        zg.mem.release(m);
        return false;
    }
    const fb = &zigos.lfbs[PLANE];
    fb.openBorders(.all);
    for (0..256) |i| fb.palette[i] = 0xFF00_0000;
    return true;
}

pub fn partOf(state: T.State) Part {
    return switch (state) {
        .p2_tunnel, .p2_wobble_start => .tunnel, // the stall after it: the tunnel runs on
        .p2_wobble_compute, .p2_wobble => .wobble,
        .env_start, .env_loop => .env,
        .p7_roto_start, .p7_roto_compute, .p7_roto => .roto,
        .p1_wipe, .p1_rno, .p1_natrium, .p1_erase, .p1_clear => .dots,
        .p5_first, .p5_loop => .twister,
        else => .classic,
    };
}

/// One ZIG frame. `vbl_us`: the host time already run into the next VBL;
/// `dirty`: the ST screen changed since the last frame.
pub fn render(zigos: *zg.ZigOS, q: *const T.Seq, vbl_us: u32, dirty: bool) void {
    const fb = &zigos.lfbs[PLANE];
    R.ops = 0;
    const p = partOf(q.state);
    const enter = fresh or p != part;
    fresh = false;
    part = p;
    palette(fb, &q.pal, p);
    time = @as(u32, q.f) * 1024 + @min(vbl_us, VBL_US - 1) * 1024 / VBL_US;
    switch (p) {
        .classic => {
            if (enter) {
                R.bl.fill(fb, 0, 0, R.W, R.H, 0);
                R.ops += 1;
            }
            if (enter or dirty) st.toChunky(q.shownBuf(), fb.fb[R.OY * R.W + R.OX .. R.W * R.H], R.W);
        },
        .tunnel, .wobble, .roto => {
            if (enter) R.expandBg(q.shownBuf()); // the girl panel's source
            switch (p) {
                .tunnel => tunnel.draw(fb, time),
                .wobble => wobble.draw(fb, time),
                else => roto.draw(fb, time),
            }
        },
        .dots => {
            if (enter) dots.sync(q.shownBuf(), true);
            dots.draw(fb, q.shownBuf(), time, dirty);
        },
        .twister => {
            if (enter) twist.enter(fb);
            twist.draw(fb, time, q.counter);
        },
        .env => {
            if (enter) {
                R.pictureBg(if (q.env.data.ptr == A.prism.ptr) A.girl_red else A.girl_grey);
                env.reset();
                R.restore(fb, 0, 0, R.W, R.H);
            }
            env.draw(fb, q.env, time -| 3 * 1024);
        },
    }
}

/// Entries 0..15 the ST palette, 16.. the part's true-colour shades; a
/// register is written only when its colour changes.
fn palette(fb: *zg.LogicalFB, pal: *const [16]u16, p: Part) void {
    for (pal, 0..) |c, i| set(fb, i, st.stColor(c));
    switch (p) {
        .tunnel, .wobble, .roto => for (0..7) |l| set(fb, R.SHADE0 + l, M.boxShade(pal, l)),
        .env => for (0..13) |l| set(fb, R.SHADE0 + l, M.envLevel(pal, l)),
        .classic, .dots, .twister => {},
    }
}

inline fn set(fb: *zg.LogicalFB, i: usize, c: u32) void {
    if (fb.palette[i] != c) fb.palette[i] = c;
}
