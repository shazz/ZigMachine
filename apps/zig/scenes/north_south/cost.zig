// --------------------------------------------------------------------------
// What a battle frame did, counted for the pacing model (pacing.zig): sprite
// rows by 16-px words and shift class, pixels plotted, grid lookups, hit-test
// and draw-list scans, RNG calls, AI steps... None of it changes the game.
//
// The reference model sums coef x count in the order each counter was FIRST
// touched this frame (a Python Counter), with Python 3.12's compensated
// float sum. The same order and the same summation are kept here, so the
// fitted frame length comes out bit for bit and the VBL count agrees exactly.
// --------------------------------------------------------------------------
pub const Key = enum(u8) {
    ai,
    ai_op,
    anim,
    blits,
    clip_blits,
    clip_rows,
    dm,
    dm_it,
    draw_it,
    flip_bytes,
    grid,
    hit_it,
    hits,
    hl_px,
    hlines,
    play,
    plots,
    reform,
    rnd,
    rows,
    rw_a1,
    rw_an,
    rw_l1,
    rw_ln,
    rw_r1,
    rw_rn,
    rw_sh,
    u_cannon,
    u_cavalry,
    u_infantry,
    spawn, // counted by the model, not in the fit
};
pub const N = @typeInfo(Key).@"enum".fields.len;

/// pacing_params.json "coef" (pacing_fit.py's least squares on the harness).
pub const CONST: f64 = 152342.40144503955;
const COEF = blk: {
    var c = [_]f64{0} ** N;
    c[@intFromEnum(Key.ai)] = 922.6966673227636;
    c[@intFromEnum(Key.ai_op)] = 1262.693263386066;
    c[@intFromEnum(Key.anim)] = 366.05656953233506;
    c[@intFromEnum(Key.blits)] = 1132.1318486878347;
    c[@intFromEnum(Key.clip_blits)] = 483.61022399589183;
    c[@intFromEnum(Key.clip_rows)] = 280.08777688249484;
    c[@intFromEnum(Key.dm)] = 881.9683547284733;
    c[@intFromEnum(Key.dm_it)] = 549.8896012538547;
    c[@intFromEnum(Key.draw_it)] = 796.1681187663559;
    c[@intFromEnum(Key.flip_bytes)] = 26.54445561458328;
    c[@intFromEnum(Key.grid)] = 787.2589844675574;
    c[@intFromEnum(Key.hit_it)] = 674.4901731428457;
    c[@intFromEnum(Key.hits)] = 1531.0062109931546;
    c[@intFromEnum(Key.hl_px)] = 8.00013026210396;
    c[@intFromEnum(Key.hlines)] = 1030.6446811827016;
    c[@intFromEnum(Key.play)] = 1847.710825833432;
    c[@intFromEnum(Key.plots)] = 579.1264411498846;
    c[@intFromEnum(Key.reform)] = 3442.908500939554;
    c[@intFromEnum(Key.rnd)] = 776.2157982675851;
    c[@intFromEnum(Key.rows)] = -256.0023296246894;
    c[@intFromEnum(Key.rw_a1)] = 426.30234886340895;
    c[@intFromEnum(Key.rw_an)] = 271.552700253353;
    c[@intFromEnum(Key.rw_l1)] = 371.9631288921578;
    c[@intFromEnum(Key.rw_ln)] = 331.2849613449318;
    c[@intFromEnum(Key.rw_r1)] = 360.52809194792655;
    c[@intFromEnum(Key.rw_rn)] = 313.0305321622808;
    c[@intFromEnum(Key.rw_sh)] = 6.250458138906435;
    c[@intFromEnum(Key.u_cannon)] = 1504.0757211601388;
    c[@intFromEnum(Key.u_cavalry)] = 4964.0308970786955;
    c[@intFromEnum(Key.u_infantry)] = 7359.068764549964;
    break :blk c;
};

pub const Cost = struct {
    count: [N]i64,
    order: [N]Key,
    seen: [N]bool,
    n: u8,

    pub fn reset(self: *Cost) void {
        @memset(&self.count, 0);
        @memset(&self.seen, false);
        self.n = 0;
    }

    pub fn add(self: *Cost, k: Key, v: i64) void {
        const i = @intFromEnum(k);
        if (!self.seen[i]) {
            self.seen[i] = true;
            self.order[self.n] = k;
            self.n += 1;
        }
        self.count[i] += v;
    }

    pub fn get(self: *const Cost, k: Key) i64 {
        return self.count[@intFromEnum(k)];
    }

    /// CONST + sum(coef x count): CPython 3.12's sum() of floats, i.e.
    /// Neumaier's compensated summation, in first-touched order.
    pub fn work(self: *const Cost) f64 {
        var f: f64 = 0;
        var c: f64 = 0;
        for (self.order[0..self.n]) |k| {
            const coef = COEF[@intFromEnum(k)];
            if (coef == 0) continue; // an int 0 in the Python sum: adds nothing
            const x = coef * @as(f64, @floatFromInt(self.count[@intFromEnum(k)]));
            const t = f + x;
            if (@abs(f) >= @abs(x)) c += (f - t) + x else c += (x - t) + f;
            f = t;
        }
        if (c != 0 and std.math.isFinite(c)) f += c;
        return CONST + f;
    }
};

const std = @import("std");
