// --------------------------------------------------------------------------
// Algorithms of this file follow freds72's PICO-8 racer engine (github.com/freds72/virtua-on,
// vracing_main.p8; MIT, Copyright (c) freds72; licence text at the head of frame.zig).
//
// RACER: one face into the frame's kept list, from any vertex set. `build` is what the track's
// faces and decals, the cars and the skidmarks all go through: transform each vertex through a
// (frame-stamped) cache, trivial-reject by outcode, clip when a vertex is past the near plane or
// the guard band, project, give it a depth key and push it. The keys are 1,024 buckets of 1/8
// unit, far to near; a decal passes its parent's key, a car one key for all its faces (carview.zig: never below the
// ground face under it, or a long road quad would paint over it: the plan's risk 4).
// No ZigOS import.
// --------------------------------------------------------------------------
const cam = @import("cam.zig");
const clip = @import("clip.zig");
const frame = @import("frame.zig");
const fx = @import("fx.zig");
const haze = @import("haze.zig");
const trk = @import("trk.zig");
const types = @import("types.zig");
const xf = @import("xform.zig");

/// Each field on its own word (board optimisation): with byte fields side by side LLVM wrote two of them as one i16 store at
/// an odd stack offset, which traps on ZIGGY (perf_audit's misaligned probe, ~210 cycles a car face).
pub const Key = struct { fixed: ?u16 align(4) = null, dc: u8 align(4) = 0, shadow: bool align(4) = false, light: bool align(4) = false }; // fixed: a decal's parent key, a car's own (carview.zig); dc: added to the palette index (a livery); shadow: darkens what is under it (shadow.zig)

/// The debug shading (key i): 0 the face's stored colour, 1 / 2 the alternates a VR import stores in `alt` (lit by the
/// normal as the converter lights the oval; gently lit). A face with no alternates (every committed track, the cars) keeps its colour.
pub const SHADES = [_][]const u8{ "FLAT", "LIT", "SOFT" };
pub const TAGS = [_][]const u8{ "", "/LIT", "/SOFT" }; // after the track name on the HUD (none in the default)
pub var shade: u8 = 0;

/// The shadow headroom (R82, key 9 / the options' SHADOW row on a track that has it): in the FLAT shading, a face whose
/// import stored a headroom colour (alt byte 2: the same ramp, never level 0, so the shadow's one-darker always shows;
/// tools/racer/vr_colours.py --shadow-headroom) is drawn in it. No other track has one.
pub var headroom: bool = false;

/// True when any face of `t` stored a headroom colour (a scan of the faces: the options screen, on a change only).
pub fn hasHeadroom(t: *const trk.Track) bool {
    for (t.faces) |*f| if (f.alt >> 16 & 0xFF != 0) return true;
    return false;
}

pub fn colourOf(f: *const trk.Face) u8 {
    if (shade == 0 and headroom and f.alt >> 16 & 0xFF != 0) return @truncate(f.alt >> 16);
    if (shade == 0 or f.alt == 0) return f.colour;
    return @truncate(f.alt >> @intCast(8 * (shade - 1)));
}

/// "Nothing kept": build's and push's result when a face is culled. A u32 sentinel, not a ?u16 (M6: a ?u16 result is a
/// 4-byte value at align 2 written through the caller's stack slot, an i32 store that trapped misaligned on ZIGGY ~70 %
/// of the calls: perf_audit).
pub const NONE: u32 = 0xFFFF_FFFF;

/// Project face `f` (vertex ids into `verts`) into `fr`. Returns the key kept, or NONE when nothing is left to draw.
pub fn build(fr: *frame.Frame, cache: *xf.Cache, verts: []const trk.Vert, v: *const cam.View, f: *const trk.Face, k: Key) u32 {
    const nv = f.nv;
    var es: [4]*xf.Entry = undefined;
    var all: u8 = 0xFF;
    var any_guard: u8 = 0;
    var zsum: i32 = 0;
    for (0..nv) |i| {
        es[i] = xf.get(cache, v, verts, f.v[i]);
        all &= es[i].rej;
        any_guard |= es[i].guard;
        zsum += es[i].v[2];
    }
    if (all != 0) {
        fr.stats.rejected += 1;
        return NONE;
    }
    var rec: frame.Rec = undefined;
    if (clip.break_drop and any_guard != 0) return NONE;
    if (any_guard == 0) {
        rec.n = nv;
        for (0..nv) |i| {
            rec.x[i] = es[i].sx;
            rec.y[i] = es[i].sy;
        }
    } else if (!clipped(fr, &rec, es[0..nv], any_guard)) {
        fr.stats.rejected += 1;
        return NONE;
    }
    if (types.offScreen(&rec)) return NONE;
    const mean = if (nv == 4) zsum >> 2 else fx.mulsh16(zsum, 21845);
    const key = k.fixed orelse depthKey(mean);
    rec.c = colourOf(f) +% k.dc;
    if (haze.active) { // M6: the band's colour; a shadow in a band is washed out (haze.zig)
        if ((k.shadow or k.light) and haze.band(key) != 0) return NONE;
        rec.c = haze.colour(key, rec.c);
    }
    if (k.shadow) rec.n |= types.SHADOW;
    if (k.light) rec.n |= types.LIGHT; // a smoke puff (smoke.zig)
    return push(fr, rec, key);
}

/// The depth bucket of a view depth z (Q16): 1/8 unit buckets, far (0) to near (BUCKETS - 1).
pub fn depthKey(z: i32) u16 {
    return @intCast(frame.BUCKETS - 1 - @min(@max(z >> 13, 0), frame.BUCKETS - 1));
}

fn clipped(fr: *frame.Frame, rec: *frame.Rec, es: []*xf.Entry, mask: u8) bool {
    var p = clip.Poly{};
    for (es) |e| {
        p.p[p.n] = e.v;
        p.n += 1;
    }
    clip.clip(&p, mask);
    if (p.n < 3) return false;
    fr.stats.clipped += 1;
    rec.n = @intCast(p.n);
    for (p.p[0..p.n], 0..) |q, i| {
        const s = xf.project(q);
        rec.x[i] = @intCast(s.x);
        rec.y[i] = @intCast(s.y);
    }
    return true;
}

/// Keep a polygon with its key. `frame.collect` zeroes the counts, so extras go in after it and before `sort`.
pub fn push(fr: *frame.Frame, rec: frame.Rec, key: u16) u32 {
    const i = fr.stats.polys;
    if (i == fr.kept.len) {
        fr.stats.dropped += 1;
        return NONE;
    }
    fr.kept[i] = rec;
    fr.key[i] = key;
    fr.count[key + 1] += 1;
    fr.stats.polys = i + 1;
    return key;
}
