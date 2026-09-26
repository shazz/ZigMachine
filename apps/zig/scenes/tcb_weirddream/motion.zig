// --------------------------------------------------------------------------
// WEIRD DREAM: everything that MOVES, as one Layout a frame (screen.js go()).
// update() fills a Layout and advances the counters; draw.zig paints it.
//
// All positions come out of screen.js's own expressions in its DOUBLED canvas
// coordinates, then map to the ST pixel whose centre the doubled position
// covers: st = floor(doubled / 2 + 0.5). The canvas smooths fractional
// positions; an ST places at whole pixels, so the nearest one is used.
// --------------------------------------------------------------------------
const std = @import("std");

const DEG: f64 = std.math.pi / 180.0;

// --------------------------------------------------------------------------
// The scroller's per-row x offset (screen.js:204-247, precalc_scroll_x)
// --------------------------------------------------------------------------
// A PLAYLIST of segments read at (vbl + row) % 802, so the wobble changes
// character as vbl walks through it. The fourth block of the original rewrites
// entries 0..388 with the first block's own formula (it indexes a bare `i`):
// the values are identical, so it is recorded here and not run.
const Segment = struct { count: usize, amp: f64, deg: f64, amp2: f64 = 0, deg2: f64 = 0 };
const SEGMENTS = [_]Segment{
    .{ .count = 389, .amp = 20, .deg = 7, .amp2 = 30, .deg2 = 3 },
    .{ .count = 120, .amp = 4, .deg = 72 },
    .{ .count = 68, .amp = 40, .deg = 8 },
    .{ .count = 36, .amp = 4, .deg = 72 },
    .{ .count = 189, .amp = 30, .deg = 8 },
};
pub const SCROLL_LEN: usize = 802;

/// The table in ST pixels: go() reads its row from canvas x 64 + scroll_x,
/// i.e. ST x 32 + round(scroll_x / 2).
pub const scroll_off: [SCROLL_LEN]i8 = blk: {
    @setEvalBranchQuota(200_000);
    var t: [SCROLL_LEN]i8 = undefined;
    var at: usize = 0;
    for (SEGMENTS) |seg| {
        // stp = deg / 180 * PI, in that order, as screen.js computes it
        const stp1 = seg.deg / 180.0 * std.math.pi;
        const stp2 = seg.deg2 / 180.0 * std.math.pi;
        for (0..seg.count) |i| {
            const f: f64 = @floatFromInt(i);
            var sx = seg.amp * @sin(f * stp1);
            if (seg.amp2 != 0) sx += seg.amp2 * @cos(f * stp2);
            t[at] = @intFromFloat(@floor(sx / 2.0 + 0.5));
            at += 1;
        }
    }
    if (at != SCROLL_LEN) @compileError("precalc_scroll_x is 802 entries");
    break :blk t;
};

// --------------------------------------------------------------------------
// The layout of one main-part frame
// --------------------------------------------------------------------------
pub const COLUMNS = 40; // 40 blocks of 8 pixels (16 in the canvas)

pub const Logo = struct {
    zoom: u8, // 1-based precalc frame; 0 = not drawn (screen.js: `if (zz > 0)`)
    top: i32, // doubled top row: yrep-22 / ytcb-25
};

pub const Layout = struct {
    rep: Logo,
    tcb: Logo,
    tcb_on_top: bool, // ztcb >= zrep: REPLICANTS drawn first
    col_y: [COLUMNS]u8, // ST row of each scroller block's top
    sprite_y: [2]u8, // left, right UNION sprite
    text_at: i64, // stream pixel at scroller x 0 before the row offset
    table_at: usize, // vbl % 802
};

/// The phases go() reads and then steps. The two logo angles step by whole
/// degrees (steprep = 2/180*PI, steptcb = 7/180*PI), so they are kept as
/// integer degrees mod 360: exactly periodic, where the original's float
/// accumulators drift. offsetscr steps by 0.1 rad and is never periodic, so it
/// stays the original's f64 accumulator, bit for bit.
pub const Phase = struct {
    vbl: u32,
    rep_deg: u16,
    tcb_deg: u16,
    offsetscr: f64,

    pub fn reset(self: *Phase) void {
        self.vbl = 0;
        self.rep_deg = 0;
        self.tcb_deg = 0;
        self.offsetscr = 0;
    }

    pub fn layout(self: *const Phase, out: *Layout) void {
        logos(self.rep_deg, self.tcb_deg, out);
        for (&out.col_y, 0..) |*y, c| {
            const at = self.offsetscr + @as(f64, @floatFromInt(c)) * 0.1;
            y.* = stRow(280 + 35 + @cos(at) * 35);
        }
        out.sprite_y[0] = stRow(326 - @abs(@cos(self.offsetscr) * 24));
        out.sprite_y[1] = stRow(326 - @abs(@sin(self.offsetscr) * 24));
        // The 8-pixel `letter` canvas reaches stream pixel 0 on draw 16 and the
        // 768-wide strip appends it at x=760, one draw a frame: after draw n the
        // strip's x holds stream pixel 8n - 888 + x, read from x 64 + scroll_x.
        // Halved: 4(vbl+1) - 444 + 32.
        out.text_at = 4 * (@as(i64, self.vbl) + 1) - 412;
        out.table_at = self.vbl % SCROLL_LEN;
    }

    pub fn step(self: *Phase) void {
        self.rep_deg = (self.rep_deg + 2) % 360;
        self.tcb_deg = (self.tcb_deg + 7) % 360;
        self.offsetscr += 0.1;
        self.vbl +%= 1;
    }
};

fn stRow(doubled: f64) u8 {
    return @intFromFloat(@floor(doubled / 2.0 + 0.5));
}

fn jsRound(v: f64) i32 {
    return @intFromFloat(@floor(v + 0.5));
}

// screen.js:406-430, verbatim.
fn logos(rep_deg: u16, tcb_deg: u16, out: *Layout) void {
    const offrep = @as(f64, @floatFromInt(rep_deg)) * DEG;
    const offtcb = @as(f64, @floatFromInt(tcb_deg)) * DEG;
    const zrep = @max(0.0, (1 + @sin(offrep)) / 2);
    const yrep = 140 + (@cos(offrep) + @sin(offrep)) * 40;
    const ztcb = zrep + @cos(offtcb) / 8;
    const ytcb = yrep + @sin(offtcb) * (70 * zrep);
    out.rep = .{ .zoom = @intCast(jsRound(zrep * 35)), .top = jsRound(yrep) - 22 };
    out.tcb = .{ .zoom = @intCast(jsRound(4 + ztcb * 32)), .top = jsRound(ytcb) - 25 };
    out.tcb_on_top = ztcb >= zrep;
}

// --------------------------------------------------------------------------
// The starfield (starfield2D_dot over the 640x280 `stars` canvas)
// --------------------------------------------------------------------------
// 3 layers of 35 dots, speedx 11.2 / 5.6 / 2.8 canvas pixels, size 2, drawn
// OVER the logos. x is kept in tenths of a canvas pixel so the speeds are
// integers; a dot plots, then moves, and past x > 640 restarts at exactly 0.
pub const STARS = 105;
pub const STAR_ROWS = 140; // the stars canvas is 280 canvas rows = ST 0..139
const X_END: u16 = 6400;
const SPEED = [3]u16{ 112, 56, 28 };

pub const Star = struct { x10: u16, y: u8, layer: u8 };

/// CODEF seeds the dots from Math.random(); a fixed xorshift32 here, so the
/// field is the same every run (the harness replays the same sequence).
pub fn seedStars(stars: *[STARS]Star) void {
    var s: u32 = 0x0345_1989;
    for (stars, 0..) |*star, i| {
        s = xorshift(s);
        star.x10 = @intCast(s % X_END);
        s = xorshift(s);
        star.y = @intCast(s % STAR_ROWS);
        star.layer = @intCast(i / 35);
    }
}

fn xorshift(v: u32) u32 {
    var x = v;
    x ^= x << 13;
    x ^= x >> 17;
    x ^= x << 5;
    return x;
}

/// The ST column a dot plots at (fillRect(x, y, 2, 2): its centre is x + 1).
pub fn starX(star: Star) u16 {
    return (star.x10 + 10) / 20;
}

pub fn moveStars(stars: *[STARS]Star) void {
    for (stars) |*star| {
        star.x10 += SPEED[star.layer];
        if (star.x10 > X_END) star.x10 = 0;
    }
}
