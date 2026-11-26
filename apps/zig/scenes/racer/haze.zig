// --------------------------------------------------------------------------
// RACER: the horizon haze (M6, PORT_PLAN's "KESTREL polish"). Far faces are drawn in colours pulled
// toward the track's haze colour, by depth, as PALETTE work: no per-pixel maths, no dithering.
//
//   - the depth key (project.depthKey: 1/8 unit buckets, far 0 to near 1023) picks a BAND, 0 (none)
//     to BANDS (the strongest), from a 1,024-entry table rebuilt when the draw distance R changes:
//     the haze starts at `start`/256 of R's distance (R x 8 units) and reaches `strength`/255 at it;
//   - a face's colour index goes through that band's 256-entry LUT (one load a polygon: project.build);
//   - a band's LUT points into the POOL: the palette entries no ramp uses (the ramps past the track's
//     and the cars' 19, so 16 + 8 x max(ramps, 19) .. 255). Each track colour gets the exact blend in
//     band 1; later bands reuse an earlier hazed entry within MERGE (the far colours converge on the
//     haze), else take a new one while the pool lasts, else the nearest. A car colour never takes an
//     entry: it maps to the nearest of the pool and itself.
//   - the far ground (palette 4) and the backdrop (12-14) are blended at full strength, so the last
//     band meets the ground beyond R with no seam.
// A track whose distinct face colours do not fit the pool has no haze (refused by kit.py; the cart logs
// it). Off (no mood haze, the option, key q) nothing here runs: the palette, the LUTs and every pixel are
// M5's. The shadow (shadow.zig) leaves pool entries alone (they are not ramps), and a shadow whose key
// is in a band is not drawn: the haze washes it out. No ZigOS import: haze_test.zig runs it natively.
// --------------------------------------------------------------------------
const std = @import("std");
const shadow = @import("shadow.zig");
const trk = @import("trk.zig");

pub const BANDS = 4;
pub const KEYS = 1024; // frame.BUCKETS
pub const MERGE: u32 = 3 * 8 * 8; // a later band reuses an earlier hazed entry this close (squared RGB distance)
const CAR_FIRST = 16 + 12 * 8; // carmodel.RAMP_BODY .. the last livery ramp (18): the cars' colours
const CAR_END = 16 + 19 * 8;

pub var on: bool = true; // the option / key q
pub var break_absent: bool = false; // racer_haze.mjs --break absent (key N): the LUTs built, never applied
pub var break_near: bool = false; // ... --break near (key P): every band one nearer (near faces hazed)

pub var active: bool = false; // on, and the track on show has a haze that fits
pub var pool_lo: u32 = 256;
pub var used: u32 = 0; // pool entries taken
var lut: [(BANDS + 1) * 256]u8 = identity();
var band_of: [KEYS]u8 = @splat(0);
var r_set: u32 = 0;
var start: u32 = 0;
var pool: [256]u32 = undefined; // the hazed colours, at pool_lo + i
var far: [4]u32 = undefined; // palette 4, 12, 13, 14 hazed
const FAR_AT = [4]u8{ 4, 12, 13, 14 };

pub const Outcome = enum { off, none, no_room, on };

fn identity() [(BANDS + 1) * 256]u8 {
    @setEvalBranchQuota(4000);
    var t: [(BANDS + 1) * 256]u8 = undefined;
    for (&t, 0..) |*e, i| e.* = @truncate(i);
    return t;
}

fn ch(c: u32, s: u5) u32 {
    return (c >> s) & 0xFF;
}

/// a + (b - a) x f / 255 on each channel of two palette words (0xAABBGGRR), opaque.
pub fn mix(a: u32, b: u32, f: u32) u32 {
    var o: u32 = 0xFF00_0000;
    inline for (.{ 0, 8, 16 }) |s| {
        const x = ch(a, s);
        const y = ch(b, s);
        const v = if (y >= x) x + (y - x) * f / 255 else x - (x - y) * f / 255;
        o |= v << s;
    }
    return o;
}

pub fn dist(a: u32, b: u32) u32 {
    var d: u32 = 0;
    inline for (.{ 0, 8, 16 }) |s| {
        const x: i32 = @intCast(ch(a, s));
        const y: i32 = @intCast(ch(b, s));
        d += @intCast((x - y) * (x - y));
    }
    return d;
}

/// The palette entries the track's faces use in shading `shade` (project.colourOf: 0 the stored colour, 1 / 2 the alternates
/// in `alt` where a face has them), below the pool and outside the car ramps.
fn trackColours(t: *const trk.Track, shade: u8, lo: u32, set: *[256]bool) u32 {
    @memset(set, false);
    var n: u32 = 0;
    for ([_][]const trk.Face{ t.faces, t.inner }) |fs| for (fs) |f| {
        const c: u8 = if (shade == 0 or f.alt == 0) f.colour else @truncate(f.alt >> @intCast(8 * (shade - 1)));
        if (c < 16 or c >= lo or (c >= CAR_FIRST and c < CAR_END) or set[c]) continue;
        set[c] = true;
        n += 1;
    };
    return n;
}

fn nearest(target: u32, self_c: ?u32) struct { i: u32, d: u32 } {
    var best: u32 = 0xFFFF_FFFF;
    var bi: u32 = 0;
    for (pool[0..used], 0..) |p, i| {
        const d = dist(p, target);
        if (d < best) {
            best = d;
            bi = @intCast(i);
        }
    }
    if (self_c) |c| if (dist(c, target) < best) return .{ .i = 256, .d = 0 };
    return .{ .i = bi, .d = best };
}

/// Build the LUTs and the pool for track `t` in shading `shade` (project.shade: key i rebuilds the look) from the palette
/// just installed (`pal`, entries 0..255). Writes nothing into the palette: paint() does, on each page.
pub fn build(pal: [*]const u32, t: *const trk.Track, shade: u8) Outcome {
    active = false;
    pool_lo = 256;
    shadow.keep_from = 256;
    used = 0;
    r_set = 0;
    lut = identity();
    const m = &t.mood;
    if (m.haze_strength == 0) return .none;
    if (!on) return .off;
    const lo: u32 = @min(256, 16 + 8 * @max(@as(u32, @intCast(t.palette.len)), 19));
    var set: [256]bool = undefined;
    if (trackColours(t, shade, lo, &set) > 256 - lo) return .no_room;
    const haze = 0xFF00_0000 | @as(u32, m.haze[0]) | @as(u32, m.haze[1]) << 8 | @as(u32, m.haze[2]) << 16;
    for (1..BANDS + 1) |b| fillBand(pal, &set, lo, b, haze, @as(u32, m.haze_strength) * @as(u32, @intCast(b)) / BANDS);
    for (FAR_AT, 0..) |at, i| far[i] = mix(pal[at], haze, m.haze_strength);
    start = m.haze_start;
    pool_lo = lo;
    shadow.keep_from = lo;
    active = !break_absent;
    return .on;
}

/// Band b's LUT at blend f: each track colour its blend (a new pool entry, or an earlier one within MERGE, or the nearest
/// when the pool is spent), each car colour the nearest of the pool and itself.
fn fillBand(pal: [*]const u32, set: *const [256]bool, lo: u32, b: usize, haze: u32, f: u32) void {
    for (16..lo) |c| {
        const car = c >= CAR_FIRST and c < CAR_END;
        if (!set[c] and !car) continue;
        const tgt = mix(pal[c], haze, f);
        const n = nearest(tgt, if (car) pal[c] else null);
        var e: u32 = if (n.i == 256) @intCast(c) else lo + n.i;
        if (!car and used < 256 - lo and n.d > (if (b == 1) 0 else MERGE)) { // band 1 exact (equal blends share)
            pool[used] = tgt;
            e = lo + used;
            used += 1;
        }
        lut[b * 256 + c] = @intCast(e);
    }
}

/// The hazed entries into one page's palette (after palette.install; nothing when the haze is not active).
pub fn paint(pal: [*]u32) void {
    if (pool_lo == 256) return;
    for (pool[0..used], 0..) |c, i| pal[pool_lo + i] = c;
    for (FAR_AT, far) |at, c| pal[at] = c;
}

/// The band of every depth key at draw distance `r` (tiles): rebuilt only when r (or the track) changed.
pub fn setR(r: u32) void {
    if (r == r_set) return;
    r_set = r;
    const edge: u32 = r * 64; // R tiles x 8 units, in the keys' 1/8 units
    const s = edge * start / 256;
    for (&band_of, 0..) |*o, k| {
        const z: u32 = KEYS - 1 - @as(u32, @intCast(k));
        const b: u32 = if (z <= s) 0 else @min(BANDS, ((z - s) * 2 * BANDS / @max(edge - s, 1) + 1) / 2);
        o.* = @intCast(if (break_near) @min(BANDS, b + 1) else b);
    }
}

/// Force setR to rebuild (a --break switch moved).
pub fn invalidate() void {
    r_set = 0;
}

pub inline fn band(key: u16) u8 {
    return band_of[key];
}

/// The colour a polygon with this key is drawn in.
pub inline fn colour(key: u16, c: u8) u8 {
    return lut[@as(usize, band_of[key]) * 256 + c];
}
