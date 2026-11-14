// --------------------------------------------------------------------------
// The BARD jobs' kernels (layout.zig's Ops), ONE source for every side: the
// cart's wasm (ZIGGY alone, the page's host, a host with no coprocessor) and
// BARD's firmware (built rv32i + Zmmul by fpga/cycles/sound.mk). So a result
// is the same bytes wherever it was computed, and scene_hash cannot tell.
//
// What BARD can run: integers, MUL (Zmmul), no DIVIDE, no FPU. A divide in
// here would be libgcc's ~400-cycle __udivsi3 on BARD (and a constant one a
// MULHU): projections go through the cart's reciprocal table instead
// (Xform.ztab), bounces through a multiply and a shift. Every op is wrapping
// (+%, *%): no overflow trap differs between the two builds.
//
// Each kernel takes an index range [from, to), so the server slices a big job
// between BARD's audio renders (music and jobs share the core).
// --------------------------------------------------------------------------
const L = @import("layout.zig");

/// The point-to-screen transform of points [from, to). Returns the points on screen.
pub fn xform(a: [*]const L.Point, b: [*]const L.Point, t: i32, x: *const L.Xform, ztab: [*]const u32, out: [*]u32, from: u32, to: u32) u32 {
    var on: u32 = 0;
    var i = from;
    while (i < to) : (i += 1) {
        const pa = a[i];
        const pb = b[i];
        const px: i32 = pa.x +% ((pb.x -% @as(i32, pa.x)) *% t >> 8);
        const py: i32 = pa.y +% ((pb.y -% @as(i32, pa.y)) *% t >> 8);
        const pz: i32 = pa.z +% ((pb.z -% @as(i32, pa.z)) *% t >> 8);
        const m = &x.m;
        const rx = (m[0] *% px +% m[1] *% py +% m[2] *% pz) >> 14;
        const ry = (m[3] *% px +% m[4] *% py +% m[5] *% pz) >> 14;
        const rz = (m[6] *% px +% m[7] *% py +% m[8] *% pz) >> 14;
        out[i] = project(x, ztab, rx, ry, rz);
        if (out[i] != L.OFF) on += 1;
    }
    return on;
}

fn project(x: *const L.Xform, ztab: [*]const u32, rx: i32, ry: i32, rz: i32) u32 {
    const depth = rz +% x.zoff;
    if (depth <= 0) return L.OFF;
    const idx: u32 = @as(u32, @intCast(depth)) >> @intCast(x.zshift & 31);
    if (idx >= x.ztab_n) return L.OFF;
    const r: i32 = @bitCast(ztab[idx]); // the cart keeps |x'| * r under 2^31 (32-bit MUL on BARD)
    const sx = x.cx +% ((rx *% r) >> 16);
    const sy = x.cy +% ((ry *% r) >> 16);
    if (sx < 0 or sy < 0 or sx >= @as(i32, @intCast(x.w)) or sy >= @as(i32, @intCast(x.h))) return L.OFF;
    const shade = (idx >> @intCast(x.shade_shift & 31)) & 0xFF;
    return shade << 24 | (@as(u32, @intCast(sy)) *% x.stride +% @as(u32, @intCast(sx)));
}

/// A hash of (particle, frame): MUL and shifts only (BARD has no divide).
pub fn hash(i: u32, frame: u32) u32 {
    var h = i *% 0x9E37_79B1 ^ frame *% 0x85EB_CA77;
    h ^= h >> 15;
    h *%= 0x2C1B_3C6D;
    h ^= h >> 12;
    h *%= 0x297A_2D39;
    return h ^ (h >> 15);
}

/// One frame of particles [from, to): `in` to `st` (the next state), `out` their screen offsets.
/// Returns how many respawned.
pub fn particles(in: [*]const L.Particle, st: [*]L.Particle, p: *const L.Physics, out: [*]u32, frame: u32, from: u32, to: u32) u32 {
    var born: u32 = 0;
    var i = from;
    while (i < to) : (i += 1) {
        var q = in[i];
        q.vy +%= p.gravity;
        q.x +%= q.vx;
        q.y +%= q.vy;
        var reborn = q.x < 0 or (q.x >> 16) >= @as(i32, @intCast(p.w));
        if (q.y >= p.floor and q.vy > 0) {
            q.y = p.floor;
            q.vy = -((q.vy *% p.bounce) >> 8);
            if (-q.vy < p.rest) reborn = true;
        }
        if (reborn) {
            q = spawn(p, i, frame);
            born += 1;
        }
        st[i] = q;
        out[i] = screen(p, q);
    }
    return born;
}

fn spawn(p: *const L.Physics, i: u32, frame: u32) L.Particle {
    const h = hash(i, frame);
    const mask = (p.spread << 1) -% 1; // spread is a power of two
    const vx: i32 = @as(i32, @bitCast(h & mask)) -% @as(i32, @bitCast(p.spread));
    const up: i32 = @bitCast((h >> 7) & (p.spread -% 1));
    return .{ .x = p.ex, .y = p.ey, .vx = vx, .vy = p.lift -% up };
}

fn screen(p: *const L.Physics, q: L.Particle) u32 {
    const sx = q.x >> 16;
    const sy = q.y >> 16;
    if (sx < 0 or sy < 0 or sx >= @as(i32, @intCast(p.w)) or sy >= @as(i32, @intCast(p.h))) return L.OFF;
    return @as(u32, @intCast(sy)) *% p.stride +% @as(u32, @intCast(sx));
}

/// CRC-32 (IEEE 802.3, reflected, zlib's): the table at comptime, so BARD's is in its rodata.
pub const crc_table: [256]u32 = blk: {
    @setEvalBranchQuota(10_000);
    var t: [256]u32 = undefined;
    for (&t, 0..) |*e, n| {
        var c: u32 = @intCast(n);
        for (0..8) |_| c = if (c & 1 != 0) 0xEDB8_8320 ^ (c >> 1) else c >> 1;
        e.* = c;
    }
    break :blk t;
};

/// Continue a CRC (pass ~0 to start, ~ the answer to finish) over `n` words: the word at a time,
/// little-endian, so a 4-aligned buffer costs one load for four table steps.
pub fn crcWords(crc0: u32, src: [*]const u32, n: u32) u32 {
    var c = crc0;
    var k: u32 = 0;
    while (k < n) : (k += 1) {
        c ^= src[k];
        c = crc_table[c & 0xFF] ^ (c >> 8);
        c = crc_table[c & 0xFF] ^ (c >> 8);
        c = crc_table[c & 0xFF] ^ (c >> 8);
        c = crc_table[c & 0xFF] ^ (c >> 8);
    }
    return c;
}

/// The CRC-32 of each chunk [k0, k1) of `src` (chunk_words words each) into out[k].
pub fn crcChunks(src: [*]const u32, chunk_words: u32, out: [*]u32, k0: u32, k1: u32) void {
    var k = k0;
    while (k < k1) : (k += 1) out[k] = ~crcWords(0xFFFF_FFFF, src + k *% chunk_words, chunk_words);
}
