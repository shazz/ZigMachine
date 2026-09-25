// --------------------------------------------------------------------------
// P10 wobbling text scroller over copper bars. Kernels $1E8E0 / $1E8FA /
// $1E914, top border open; all the work is inside the kernel.
//   PRE    one new glyph column goes into the 50-row code strip: each strip word
//          is the opcode move.w Rn,(a1) whose source register IS the font value
//   SETUP  line L (strip row L/3) jumps into its row at a wobbling entry word
//   DISPLAY one move.w per strip word, 8 cycles apart, up to 53 or an rts
//          planted in the strip; odd entries start 4 px further left
//   POST   the line colours LC[] = 10 additive sine bars through a brightness
//          ramp that fades in (and out on the third kernel)
// --------------------------------------------------------------------------
const core = @import("core.zig");
const out = @import("out.zig");
const rip = @import("rip.zig");
const assets = @import("assets.zig");

const ROW = 258; // strip words a row
const PAL_AT = 0x506EC - 0x506BE; // offsets into p10_region
const GMAP_AT = 0x506D6 - 0x506BE;
const FONT_AT = 0x5070C - 0x506BE;

var strip: [50 * ROW + 300]u16 = undefined; // the generated code, patched every frame
var tp: u32 = 0; // $506AE, text pointer (offset into the region)
var gc: u32 = 0; // glyph column, 0..$3F
var pos: u32 = 0;
var pos_old: u32 = 0;
var ph: u32 = 0;
var mask: u32 = 0;
var step: u32 = 0;
var dir: u32 = 0;
var level: i32 = 0; // $43CE8
var phases: [10]u32 = undefined; // $43CD4
var lc: [150]u16 = undefined;
var gmap: [256]u32 = undefined; // $201A2: font offset per character
var ramps: [8][64]u16 = undefined; // $20168: $43854 and 7 darker copies

pub fn reset() void {
    for (&strip, 0..) |*w, i| w.* = core.le16(assets.p10_strip, i);
    tp = rip.P10_TP;
    gc = rip.P10_VARS[0];
    pos = rip.P10_VARS[1];
    pos_old = rip.P10_VARS[2];
    ph = rip.P10_VARS[3];
    mask = rip.P10_VARS[4];
    step = rip.P10_VARS[5];
    dir = rip.P10_DIR;
    level = rip.P10_LEVEL;
    for (&phases, rip.P10_PHASES) |*p, v| p.* = v;
    @memset(&lc, 0);
}

pub fn init() void {
    @memset(&gmap, 0);
    var o: u32 = 0;
    var p: usize = GMAP_AT;
    while (assets.p10_region[p] != 0) : (p += 1) {
        gmap[assets.p10_region[p]] = o;
        o += 0x640;
    }
    ramps[0] = rip.P10_RAMP;
    for (1..8) |k| {
        for (&ramps[k], ramps[k - 1]) |*n, d3| {
            const d4 = ((((d3 | 0x888) -% 0x111) | d3) >> 3) & 0x111;
            n.* = d3 -% d4;
        }
    }
    level = 0;
}

pub fn vbl() void {
    core.colour = 0;
}

/// $5067C: the wobble table, 2048 entries of T * 40 >> 16, + 40.
fn wob(i: u32) i32 {
    const t: i32 = @as(i16, @bitCast(core.le16(assets.p10_wob, i % 1024)));
    return ((t * 40) >> 16) + 40;
}

fn reg(src: u16, L: usize) u16 {
    return switch (src) {
        0 => lc[L],
        1...5 => core.be16(assets.p10_region, PAL_AT + 2 * @as(usize, src)),
        10...13 => core.be16(assets.p10_region, PAL_AT + 2 * @as(usize, src - 4)),
        else => 0,
    };
}

pub fn kernel(l0: u32, k: u2) void {
    dir = if (k == 2) 1 else 0;
    mask = if (k == 0) 0 else 0xFFFF;
    step = if (k == 0) 0 else 8;
    // PRE
    const ch = assets.p10_region[tp];
    const fo: u32 = gmap[ch] + @as(u32, @intCast(core.sw(gc) >> 1));
    const col = (pos_old & 0xFFFE) >> 1;
    for (0..50) |r| {
        const f = assets.p10_region[FONT_AT + fo + 0x20 * r];
        const v: u16 = 0x3200 | ((0x80 + @as(u16, f)) & 0xFF);
        strip[r * ROW + col] = v;
        strip[r * ROW + col + 128] = v;
    }
    // SETUP + DISPLAY
    var a6 = (ph & mask) >> 1;
    var d2: u32 = 150;
    var t: u32 = 35592;
    for (0..150) |L| {
        const d6: u32 = @as(u32, @intCast(wob(a6) + @as(i32, @intCast(pos + ((d2 >> 2) & mask))))) & 0xFFFF;
        a6 += step >> 1;
        d2 -= 1;
        const e = (L / 3) * ROW + ((d6 & 0xFFFE) >> 1);
        const first = t + @as(u32, if (d6 & 1 != 0) 56 else 60);
        var n: u32 = 0;
        while (n < 53) : (n += 1) {
            const w = strip[e + n];
            if (w == 0x4E75) break;
            out.emit(l0, first + 8 * n, reg(w & 0x3F, L));
        }
        t += 88 + 8 * n;
    }
    out.emit(l0, t + 4, 0);
    core.colour = 0;
    post();
}

/// Counters, the text, and the line colours for the next frame.
fn post() void {
    gc += 1;
    if (gc == 0x40) {
        gc = 0;
        tp += 1;
        if (assets.p10_region[tp] == 0) tp = 0;
    }
    pos_old = pos;
    pos = (pos + 1) & 0xFF;
    ph = (ph + 0x10) & 0x7FF;
    var I = [_]u8{0} ** 152;
    for (&phases) |*p| {
        const d1 = p.*;
        const d2v: i32 = @as(i16, @bitCast(core.le16(assets.p10_wob, d1 >> 1)));
        p.* = (d1 + 0x20) & 0x7FF;
        const o: usize = @intCast(core.sw(@bitCast(((0x3E * d2v) >> 16) * 2 + 0x3E)));
        for (0..26) |i| I[o + i] +%= rip.P10_PROF[i];
    }
    const ramp_ofs: u32 = 0x380 - ((@as(u32, @intCast(level)) & 0xFFFC) << 5);
    const flat: *const [512]u16 = @ptrCast(&ramps);
    for (&lc, I[0..150]) |*c, i| c.* = flat[(ramp_ofs >> 1) + i];
    if (dir == 0) {
        if (level + 1 < 0x20) level += 1;
    } else if (level - 1 >= 0) level -= 1;
}
