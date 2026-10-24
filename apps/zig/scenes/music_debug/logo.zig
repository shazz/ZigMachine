// --------------------------------------------------------------------------
// The sine-distorted TRSI logo: every source column is shifted down by a
// column wave, every source row right by a breathing row wave.
//
// Drawn column by column, as the first version did, so where two source
// pixels land on one screen pixel the same one wins (the later column). Each
// column is a comptime list of opaque runs, and each row's screen offset is
// computed once a draw, so the inner loop is a load and a store per pixel.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const wave = @import("wave.zig");
const ft = zg.fixtrig;
const View = @import("view.zig").View;

pub const W: usize = 208;
pub const H: usize = 109;
pub const BASE: u8 = 128; // the logo's palette entries: 128 + 1..31, trails at +32/+64/+96
const WIDTH: i32 = zg.WIDTH;
const HEIGHT: i32 = zg.HEIGHT;
const START_X: i32 = (WIDTH - W) / 2;
const BASE_Y: i32 = -22; // crop the logo's ~25px top padding to sit near the top

const raw = @embedFile("../../assets/logo/trsi.raw");

// The logo as opaque runs down each column (comptime): 552 runs, 7272 pixels of
// 22672, so the draw loop never visits a transparent one. Their colours are stored
// in run order: read straight from the row-major picture, a column walk missed the
// 4 KB D-cache on every pixel (a third of the logo's cost on the board).
fn isInk(x: usize, y: usize) bool {
    return raw[y * W + x] != 0;
}
const N_RUNS: usize = blk: {
    @setEvalBranchQuota(W * H * 8);
    var n: usize = 0;
    for (0..W) |x| {
        for (0..H) |y| {
            if (isInk(x, y) and (y == 0 or !isInk(x, y - 1))) n += 1;
        }
    }
    break :blk n;
};
const N_INK: usize = blk: {
    @setEvalBranchQuota(W * H * 2);
    var n: usize = 0;
    for (raw) |c| n += @intFromBool(c != 0);
    break :blk n;
};
const Run = struct { y0: u8, len: u8, ink: u16 }; // ink: its first colour in Runs.ink
const Runs = struct { first: [W + 1]u16, run: [N_RUNS]Run, ink: [N_INK]u8, top: usize, bottom: usize };
const runs: Runs = blk: {
    @setEvalBranchQuota(W * H * 16);
    var first: [W + 1]u16 = undefined; // runs of column x: first[x] .. first[x + 1]
    var r: [N_RUNS]Run = undefined;
    var ink: [N_INK]u8 = undefined;
    var k: usize = 0;
    var n: usize = 0;
    var top: usize = H;
    var bottom: usize = 0; // the source rows that hold ink
    for (0..W) |x| {
        first[x] = @intCast(n);
        var y: usize = 0;
        while (y < H) : (y += 1) {
            if (!isInk(x, y)) continue;
            const y0 = y;
            r[n] = Run{ .y0 = @intCast(y0), .len = 0, .ink = @intCast(k) };
            while (y < H and isInk(x, y)) : (y += 1) {
                ink[k] = raw[y * W + x];
                k += 1;
            }
            r[n].len = @intCast(y - y0);
            n += 1;
            top = @min(top, y0);
            bottom = @max(bottom, y - 1);
        }
    }
    first[W] = @intCast(n);
    break :blk Runs{ .first = first, .run = r, .ink = ink, .top = top, .bottom = bottom };
};

// The row wave never pushes a row off the plane: |hoff| <= HAMP8_MAX keeps
// START_X + hoff .. + W inside 0..WIDTH, so only the column wave needs clipping.
comptime {
    const hmax: i32 = HAMP8_MAX >> 8;
    if (START_X - hmax < 0 or START_X + @as(i32, W) + hmax > WIDTH) @compileError("logo row wave leaves the plane");
}

// The logo's phase as three Angles, one per wave: the column wave at lphase, the
// breathing amplitude at lphase * 0.7 and the row wave at lphase * 1.3 (the f32
// screen's factors, applied to the steps and offsets at compile time).
pub const Phase = struct {
    col: wave.Angle = 0,
    breath: wave.Angle = 0,
    row: wave.Angle = 0,

    const STEP = 0.045; // radians of lphase a frame
    pub fn step(self: *Phase) void {
        self.col +%= wave.rad(STEP);
        self.breath +%= wave.rad(STEP * 0.7);
        self.row +%= wave.rad(STEP * 1.3);
    }

    /// The phase `lag` radians of lphase earlier (a trail copy).
    pub fn back(self: Phase, comptime lag: f64) Phase {
        return .{ .col = self.col -% wave.rad(lag), .breath = self.breath -% wave.rad(lag * 0.7), .row = self.row -% wave.rad(lag * 1.3) };
    }
};

const COL_STEP = wave.rad(0.03); // column wave phase a source column
const ROW_STEP = wave.rad(0.06); // row wave phase a source row
const AMP8: i32 = 8 * 256; // column wave amplitude, Q8
const HAMP8_MAX: i32 = 10 * 256; // row wave amplitude at its widest, Q8

// The runs' colours already offset by each copy's palette base (comptime): copy t
// uses BASE + 32 t + ink, so the inner loop is two loads, an add and a store.
const INK: [4][N_INK]u8 = blk: {
    @setEvalBranchQuota(N_INK * 8);
    var t: [4][N_INK]u8 = undefined;
    for (0..4) |c| {
        for (runs.ink, 0..) |k, i| t[c][i] = BASE + 32 * c + k;
    }
    break :blk t;
};

/// Each source row's screen offset at dy = 0 (less BASE_Y rows): row r shifted
/// right by the row wave, whose amplitude breathes 0..HAMP_MAX.
fn rowOffsets(rowoff: *[H]i32, stride: i32, p: Phase) void {
    const hamp8: i32 = @intCast((@as(i64, ft.sin(p.breath)) + ft.ONE) * @divExact(HAMP8_MAX, 2) >> 16);
    var a = p.row +% @as(u32, @intCast(runs.top)) *% ROW_STEP;
    for (runs.top..runs.bottom + 1) |r| {
        rowoff[r] = @as(i32, @intCast(r)) * stride + START_X + wave.offset(a, hamp8);
        a +%= ROW_STEP;
    }
}

// Draw copy `trail` of the logo at phase `p`: 0 = full colour (BASE), 1..3 = the
// dimmer trail copies (BASE + 32/64/96).
pub fn draw(v: View, p: Phase, trail: usize) void {
    const stride: i32 = v.stride;
    var rowoff: [H]i32 = undefined;
    rowOffsets(&rowoff, stride, p);
    const inks = &INK[trail];
    var a = p.col;
    for (0..W) |px| {
        defer a +%= COL_STEP;
        const col = runs.run[runs.first[px]..runs.first[px + 1]];
        if (col.len == 0) continue; // no ink: its wave offset is never used
        const top = BASE_Y + wave.offset(a, AMP8); // screen row of source row 0
        const lo: usize = @intCast(@max(0, -top));
        const hi: usize = @intCast(@min(@as(i32, H), HEIGHT - top));
        const base: i32 = top * stride + @as(i32, @intCast(px));
        for (col) |run| {
            const y1 = @min(hi, @as(usize, run.y0) + run.len);
            const y0 = @max(lo, run.y0);
            if (y0 >= y1) continue;
            // walking pointers, two pixels a turn: the loop's own overhead was
            // nearly half of each pixel's cost (~24k pixels a frame)
            var ip: [*]const u8 = inks[run.ink + (y0 - run.y0) ..].ptr;
            var rp: [*]const i32 = rowoff[y0..].ptr;
            var n = y1 - y0;
            while (n >= 2) : (n -= 2) {
                v.px[@intCast(base + rp[0])] = ip[0];
                v.px[@intCast(base + rp[1])] = ip[1];
                ip += 2;
                rp += 2;
            }
            if (n != 0) v.px[@intCast(base + rp[0])] = ip[0];
        }
    }
}
