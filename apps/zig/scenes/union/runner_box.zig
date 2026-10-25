// --------------------------------------------------------------------------
// Union main -- the runner at full speed as one picture a frame.
//
// At scale 1 (the main screen's whole life but a hold-Left slow-down) main.zig
// erased runner.BOX to 0, then runner.draw blitted the four ghosts (dimmest,
// widest first: g 3 -> 0) and the runner over it, colour 0 clear. Each of the 7
// sprite frames therefore leaves the same box, built here at compile time with
// the very same layer order and keys from runner.zig's own sheets: one opaque
// CHISEL copy instead of a fill and five keyed blits. 7 x 128 x 28 = 25 KB.
// --------------------------------------------------------------------------
const runner = @import("runner.zig");

pub const X: usize = runner.BOX[0];
pub const W: usize = runner.BOX[1] - runner.BOX[0];
const H = runner.FHU;

pub const pictures: [runner.FRAMES][W * H]u8 = blk: {
    @setEvalBranchQuota(2_000_000);
    var t: [runner.FRAMES][W * H]u8 = undefined;
    for (0..runner.FRAMES) |f| {
        var p = [_]u8{0} ** (W * H);
        var g: usize = 4;
        while (g > 0) {
            g -= 1;
            const w = runner.FIXED_COLS[g];
            const sheet_w = runner.FRAMES * w; // runner.blitFixed's picture
            const x0: usize = @as(usize, @intCast(runner.left(g))) - X;
            for (0..H) |r| for (0..w) |c| {
                const v = runner.fixed_sheet[runner.FIXED_OFF[g] + r * sheet_w + f * w + c];
                if (v != 0) p[r * W + x0 + c] = v;
            };
        }
        const fw: usize = @intCast(runner.FW);
        const rx: usize = @as(usize, @intCast(runner.X0)) - X;
        for (0..H) |r| for (0..fw) |c| {
            const v = runner.sprites[r * runner.SW + f * fw + c];
            if (v != 0) p[r * W + rx + c] = v;
        };
        t[f] = p;
    }
    break :blk t;
};
