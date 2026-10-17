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
const fsin = @import("fsin.zig");
const View = @import("view.zig").View;

pub const W: usize = 208;
pub const H: usize = 109;
pub const BASE: u8 = 128; // the logo's palette entries: 128 + 1..31, trails at +32/+64/+96
const WIDTH: i32 = zg.WIDTH;
const HEIGHT: i32 = zg.HEIGHT;
const AMP: f32 = 8.0; // column wave amplitude
const HAMP_MAX: f32 = 10.0; // row wave amplitude at its widest
const START_X: i32 = (WIDTH - W) / 2;
const BASE_Y: i32 = -22; // crop the logo's ~25px top padding to sit near the top

const raw = @embedFile("../../assets/logo/trsi.raw");

// The logo as opaque runs down each column (comptime): 552 runs, 7272 pixels of
// 22672, so the draw loop never visits a transparent one.
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
const Run = struct { y0: u8, len: u8 };
const Runs = struct { first: [W + 1]u16, run: [N_RUNS]Run, top: usize, bottom: usize };
const runs: Runs = blk: {
    @setEvalBranchQuota(W * H * 16);
    var first: [W + 1]u16 = undefined; // runs of column x: first[x] .. first[x + 1]
    var r: [N_RUNS]Run = undefined;
    var n: usize = 0;
    var top: usize = H;
    var bottom: usize = 0; // the source rows that hold ink
    for (0..W) |x| {
        first[x] = @intCast(n);
        var y: usize = 0;
        while (y < H) : (y += 1) {
            if (!isInk(x, y)) continue;
            const y0 = y;
            while (y < H and isInk(x, y)) y += 1;
            r[n] = Run{ .y0 = @intCast(y0), .len = @intCast(y - y0) };
            n += 1;
            top = @min(top, y0);
            bottom = @max(bottom, y - 1);
        }
    }
    first[W] = @intCast(n);
    break :blk Runs{ .first = first, .run = r, .top = top, .bottom = bottom };
};

// The row wave never pushes a row off the plane: |hoff| <= HAMP_MAX keeps
// START_X + hoff .. + W inside 0..WIDTH, so only the column wave needs clipping.
comptime {
    const hmax: i32 = @intFromFloat(HAMP_MAX);
    if (START_X - hmax < 0 or START_X + @as(i32, W) + hmax > WIDTH) @compileError("logo row wave leaves the plane");
}

// Draw the logo at distortion phase `lphase`, palette entries offset by
// `pal_base` (BASE = full colour, BASE + 32/64/96 = the dimmer trail copies).
pub fn draw(v: View, lphase: f32, pal_base: u8) void {
    const stride: i32 = v.stride;
    // horizontal distortion amplitude breathes over time (progress/regress)
    const hamp: f32 = (fsin.sin(lphase * 0.7) * 0.5 + 0.5) * HAMP_MAX;
    var rowoff: [H]i32 = undefined; // screen offset of source row r at dy = 0, less BASE_Y rows
    for (runs.top..runs.bottom + 1) |r| {
        const hoff: i32 = @intFromFloat(fsin.sin(@as(f32, @floatFromInt(r)) * 0.06 + lphase * 1.3) * hamp);
        rowoff[r] = @as(i32, @intCast(r)) * stride + START_X + hoff;
    }
    for (0..W) |px| {
        const dy: i32 = @intFromFloat(fsin.sin(@as(f32, @floatFromInt(px)) * 0.03 + lphase) * AMP);
        const top = BASE_Y + dy; // screen row of source row 0
        const lo: usize = @intCast(@max(0, -top));
        const hi: usize = @intCast(@min(@as(i32, H), HEIGHT - top));
        const base: i32 = top * stride + @as(i32, @intCast(px));
        for (runs.run[runs.first[px]..runs.first[px + 1]]) |run| {
            const y1 = @min(hi, @as(usize, run.y0) + run.len);
            var py: usize = @max(lo, run.y0);
            while (py < y1) : (py += 1) {
                v.px[@intCast(base + rowoff[py])] = pal_base + raw[py * W + px];
            }
        }
    }
}
