// --------------------------------------------------------------------------
// The reverb's taps a block at a time (kt_fxblock.zig), planned once at
// start: taps that read the same delay share one read of the line, a side
// whose gain is 0 is not computed (its product truncates to 0), and the reads
// run in groups of up to four of one kind (left only, right only, centred,
// both), each group over runs of samples where none of its reads wraps, the
// bus's l[t], r[t] loaded and stored once a group instead of once a tap.
// Every tap still adds its own truncated product, so the sums are the same
// (wrapping adds, in any order the same) as kt_fx.zig's tap by tap.
// Why: the songs' taps are mostly hard-panned pairs on one delay (starport2,
// dpintro), and the tap-by-tap loop was ~40 rv32 instructions a tap and
// sample on BARD, the biggest single cost of a reverb song.
// --------------------------------------------------------------------------
const song = @import("kt_song.zig");

pub const Kind = enum(u2) { left, right, centred, both };

/// One read of the line: its delay and the gains of the taps on it (0: no tap on that side).
pub const Read = struct { delay: u32 = 0, gl: i32 = 0, gr: i32 = 0 };

pub const Plan = struct {
    reads: [song.RVB_TAPS]Read = [_]Read{.{}} ** song.RVB_TAPS, // by kind: left, right, centred, both
    count: [4]u8 = .{ 0, 0, 0, 0 },
};

/// What a tap's (gain_l, gain_r) is, as one side or both.
fn kindOf(gl: i32, gr: i32) Kind {
    if (gr == 0) return .left;
    if (gl == 0) return .right;
    return if (gl == gr) .centred else .both;
}

/// The reads of `taps` (gain_l, gain_r, delay), merged by delay where a delay has at most one tap a side.
pub fn plan(p: *Plan, taps: anytype) void {
    var reads: [song.RVB_TAPS]Read = undefined;
    var n: usize = 0;
    outer: for (taps) |t| {
        for (reads[0..n]) |*r| {
            if (r.delay != t.delay) continue;
            if (t.gain_l != 0 and r.gl != 0 or t.gain_r != 0 and r.gr != 0) continue; // a side taken: its own read
            if (t.gain_l != 0) r.gl = t.gain_l;
            if (t.gain_r != 0) r.gr = t.gain_r;
            continue :outer;
        }
        reads[n] = .{ .delay = t.delay, .gl = t.gain_l, .gr = t.gain_r };
        n += 1;
    }
    p.count = .{ 0, 0, 0, 0 };
    var at: usize = 0;
    inline for (.{ Kind.left, Kind.right, Kind.centred, Kind.both }, 0..) |k, ki| {
        for (reads[0..n]) |r| if (kindOf(r.gl, r.gr) == k) {
            p.reads[at] = r;
            at += 1;
            p.count[ki] += 1;
        };
    }
}

/// Every read over the block: sample t was written at p0 - (n - 1 - t), read at that minus the delay.
pub fn run(p: *const Plan, line: []const i32, l: [*]i32, r: [*]i32, n: usize, p0: u32) void {
    var at: usize = 0;
    inline for (.{ Kind.left, Kind.right, Kind.centred, Kind.both }, 0..) |k, ki| {
        var left: usize = p.count[ki];
        while (left > 0) {
            const g = @min(left, 4);
            switch (g) {
                inline 1, 2, 3, 4 => |gc| group(k, gc, p.reads[at..][0..gc], line, l, r, n, p0),
                else => unreachable,
            }
            at += g;
            left -= g;
        }
    }
}

/// `g` reads of kind `k` over the block, in runs that no read's wrap splits.
fn group(comptime k: Kind, comptime g: usize, reads: *const [g]Read, line: []const i32, l: [*]i32, r: [*]i32, n: usize, p0: u32) void {
    const size: u32 = @intCast(line.len);
    const back: u32 = @intCast(n - 1);
    var pos: [g]u32 = undefined;
    var gl: [g]i32 = undefined;
    var gr: [g]i32 = undefined;
    inline for (0..g) |i| {
        const d = reads[i].delay + back; // < size: the bus is blockable
        pos[i] = if (p0 >= d) p0 - d else p0 + size - d;
        gl[i] = reads[i].gl;
        gr[i] = reads[i].gr;
    }
    var t: usize = 0;
    while (t < n) {
        var run_n: usize = n - t;
        inline for (0..g) |i| run_n = @min(run_n, size - pos[i]);
        var src: [g][*]const i32 = undefined;
        inline for (0..g) |i| src[i] = line.ptr + pos[i];
        for (t..t + run_n, 0..) |s, j| {
            var sl: i32 = 0;
            var sr: i32 = 0;
            inline for (0..g) |i| {
                const v = src[i][j];
                switch (k) {
                    .left => sl +%= @divTrunc(gl[i] *% v, 2048),
                    .right => sr +%= @divTrunc(gr[i] *% v, 2048),
                    .centred => sl +%= @divTrunc(gl[i] *% v, 2048),
                    .both => {
                        sl +%= @divTrunc(gl[i] *% v, 2048);
                        sr +%= @divTrunc(gr[i] *% v, 2048);
                    },
                }
            }
            switch (k) {
                .left => l[s] +%= sl,
                .right => r[s] +%= sr,
                .centred => {
                    l[s] +%= sl;
                    r[s] +%= sl;
                },
                .both => {
                    l[s] +%= sl;
                    r[s] +%= sr;
                },
            }
        }
        inline for (0..g) |i| {
            pos[i] += @intCast(run_n);
            if (pos[i] == size) pos[i] = 0;
        }
        t += run_n;
    }
}
