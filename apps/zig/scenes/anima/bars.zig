// --------------------------------------------------------------------------
// The copper's contents, rebuilt once a frame into raster.zig's tables.
//
// BACKGROUND (entry 0): a night gradient with six copper bars turning round a
// drum, Amiga style: each bar's height on the screen is the sine of its angle,
// its brightness the cosine, and the bars behind are painted first so the
// front ones cover them. Below the horizon (the scroller's sea) every line is
// the mirror of a line above, darkened, its row wobbling on a slow sine: the
// bars reflected in water. During DARK the drum's radius grows from zero, so
// the bars are born from one line in the middle of the screen.
//
// LOGO BODY: a chrome ramp (sky, horizon flash, earth) sliding down the logo.
// FONT BODY: a rainbow cycling up the scroller.
//
// Every value is computed per row and stored only when it differs from the
// table: the bars move every frame, the gradient between them does not.
// All tables are comptime; the frame does loads, adds and compares.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const trig = zg.fixtrig;
const P = @import("palette.zig");
const R = @import("raster.zig");
const T = @import("timeline.zig");

pub const HORIZON: usize = 214; // the sea starts here (the scroller's band)
const BARS = 6;
const BAR_H = 15;
const DEPTHS = 8;
const CENTRE: i32 = 122; // the drum's axis, physical row
const RADIUS: i32 = 74;

const HUES = [BARS][3]u32{ .{ 15, 3, 3 }, .{ 15, 11, 2 }, .{ 4, 15, 4 }, .{ 2, 13, 15 }, .{ 9, 4, 15 }, .{ 15, 5, 13 } };

// BAR[h][d][i]: bar h's line i at depth d (0 far .. 7 near), STE levels.
const BAR: [BARS][DEPTHS][BAR_H]u32 = blk: {
    @setEvalBranchQuota(100_000);
    var t: [BARS][DEPTHS][BAR_H]u32 = undefined;
    for (0..BARS) |h| for (0..DEPTHS) |d| for (0..BAR_H) |i| {
        const iu: u32 = i;
        const edge: u32 = if (iu < BAR_H - 1 - iu) iu else BAR_H - 1 - iu;
        const k: u32 = BAR_H / 2 - edge; // 7 at the edges, 0 in the core
        const lit: u32 = 16 - 2 * k; // 2..16
        const depth: u32 = 6 + d + d / 2; // 6..16
        var c = [3]u32{ 0, 0, 0 };
        for (0..3) |g| c[g] = @min(15, HUES[h][g] * lit * depth / 256 + (if (k == 0) 4 else 0));
        t[h][d][i] = P.ste(c[0], c[1], c[2]);
    };
    break :blk t;
};

const BASE: [R.ROWS]u32 = blk: {
    @setEvalBranchQuota(100_000);
    var t: [R.ROWS]u32 = undefined;
    for (0..R.ROWS) |r| {
        const ru: u32 = r;
        // night blue, brightest at the drum's axis, black at the horizon
        var b: u32 = 3;
        if (ru < 122) b = 1 + ru * 2 / 122 else b -= @min(b, (ru - 122) * 4 / 84);
        t[r] = P.ste(0, 0, b);
    }
    break :blk t;
};

const CHROME: [64]u32 = blk: {
    @setEvalBranchQuota(100_000);
    const stops = [_][3]u32{ .{ 2, 4, 12 }, .{ 6, 9, 15 }, .{ 13, 15, 15 }, .{ 15, 15, 15 }, .{ 5, 3, 2 }, .{ 9, 6, 3 }, .{ 15, 12, 6 }, .{ 4, 6, 13 } };
    var t: [64]u32 = undefined;
    for (0..64) |i| {
        const a = stops[i / 8];
        const b = stops[(i / 8 + 1) % stops.len];
        const f: u32 = i % 8;
        t[i] = P.ste((a[0] * (8 - f) + b[0] * f) / 8, (a[1] * (8 - f) + b[1] * f) / 8, (a[2] * (8 - f) + b[2] * f) / 8);
    }
    break :blk t;
};

const RAINBOW: [48]u32 = blk: {
    @setEvalBranchQuota(100_000);
    var t: [48]u32 = undefined;
    for (0..48) |i| {
        const seg = i / 8;
        const f: u32 = (i % 8) * 2;
        const up = 1 + f; // 1..15
        const dn = 15 - f;
        t[i] = switch (seg) {
            0 => P.ste(15, up, 1),
            1 => P.ste(dn, 15, 1),
            2 => P.ste(1, 15, up),
            3 => P.ste(1, dn, 15),
            4 => P.ste(up, 1, 15),
            else => P.ste(15, 1, dn),
        };
    }
    break :blk t;
};

/// The music's pulse, 0..3: lifts every bar toward the front shade (app.zig sets it
/// from the YM volumes BARD mirrors into zigos.ym_regs; 0 headless).
pub var beat: u32 = 0;
var ys: [BARS]i32 = undefined;
var ds: [BARS]u8 = undefined;
var order: [BARS]u8 = undefined;

fn placeBars(t: u32) void {
    const grow: i32 = @intCast(T.ramp(t, 0, T.OPEN));
    for (0..BARS) |i| {
        const a: trig.Angle = @as(u32, t) *% (1 << 24) +% @as(u32, @intCast(i)) *% (0xFFFF_FFFF / BARS);
        const s = trig.sin(a);
        const c = trig.cos(a);
        ys[i] = CENTRE + ((((RADIUS * s) >> 16) * grow) >> 8) - BAR_H / 2;
        ds[i] = @intCast(@min(DEPTHS - 1, ((c + 65536) * (DEPTHS - 1) >> 17) + @as(i32, @intCast(beat))));
        order[i] = @intCast(i);
    }
    // far to near: insertion sort on depth (six bars)
    for (1..BARS) |i| {
        var j = i;
        while (j > 0 and ds[order[j - 1]] > ds[order[j]]) : (j -= 1) {
            const x = order[j];
            order[j] = order[j - 1];
            order[j - 1] = x;
        }
    }
}

fn skyAt(r: usize) u32 {
    var v = BASE[r];
    const ri: i32 = @intCast(r);
    for (order) |b| {
        const d = ri - ys[b];
        if (d >= 0 and d < BAR_H) v = BAR[b][ds[b]][@intCast(d)];
    }
    return v;
}

pub fn build(t: u32, logo_top: usize, logo_rows: usize, font_top: usize, font_rows: usize) void {
    placeBars(t);
    const wob = t *% (1 << 25);
    for (0..R.ROWS) |r| {
        var v: u32 = undefined;
        if (r < HORIZON) v = skyAt(r) else {
            const w = trig.sin(wob +% @as(u32, @intCast(r)) *% (1 << 27)) >> 15; // -2..2
            const m: i32 = 2 * @as(i32, HORIZON) - 1 - @as(i32, @intCast(r)) + w;
            v = P.dim(skyAt(@intCast(@max(0, m))), 9);
        }
        if (R.lines[r][0] != v) R.lines[r][0] = v;
    }
    for (logo_top..logo_top + logo_rows) |r| {
        const v = CHROME[(r - logo_top + 64 * 4 - (t >> 1) % 64) % 64];
        if (R.lines[r][1] != v) R.lines[r][1] = v;
    }
    for (font_top..font_top + font_rows) |r| {
        const v = RAINBOW[(r + t) % 48];
        if (R.lines[r][2] != v) R.lines[r][2] = v;
    }
}
