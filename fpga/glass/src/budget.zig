// The frame budget: where ZIGGY's frame goes, from the video probe (vstat.zig, cycles/vstat.h),
// for the F11 overlay's second line and the budget page (page_budget.zig). Shows, never writes.
//
// A frame is cart.frame() + the sequencer + a little glue (the audio bridge, the disk app):
//   cart    VS_CART
//   FRESCO  the sequencer's own time: VS_SEQC less its VBL wait, its HBL handlers and its planner
//   hbl     VS_HBL + VS_PLAN (cart code in the handlers, the dirty-line planner)
//   idle    VS_SWAP: waiting for the VBL, time a 60 fps cart does not need
//   other   VS_FRAME - VS_CART - VS_SEQC
// The probe's means are over its own window (~0.25 s); Smooth averages a second of ticks and
// keeps a peak over three.
const std = @import("std");
const mc = @import("map_cart.zig");
const vstat = @import("vstat.zig");

/// ZIGGY's cycles in a 60 Hz frame at 100 MHz.
pub const FRAME_60: u32 = 1_666_667;
/// Lines a pass covers: passes / LINES is how many planes the frame composed.
pub const LINES: u32 = 280;

pub const Sample = struct {
    frame: u32 = 0,
    cart: u32 = 0,
    fresco: u32 = 0,
    hbl: u32 = 0,
    idle: u32 = 0,
    other: u32 = 0,
    passes: u32 = 0,

    /// Cycles the frame really used (all but the VBL wait).
    pub fn busy(self: Sample) u32 {
        return self.cart + self.fresco + self.hbl + self.other;
    }

    /// What the cart may spend and still make 60 fps with this many planes (negative: over).
    pub fn headroom(self: Sample) i64 {
        return @as(i64, FRAME_60) - self.fresco - self.hbl - self.other;
    }
};

fn m(i: *const vstat.Info, word: u32) u32 {
    return i.mean[word - mc.VS_FRAME];
}

/// The probe's last window as a Sample, or null before one closed.
pub fn sample(i: *const vstat.Info) ?Sample {
    if (!i.ok) return null;
    const seq = m(i, mc.VS_SEQC);
    const hbl = m(i, mc.VS_HBL) + m(i, mc.VS_PLAN);
    const idle = m(i, mc.VS_SWAP);
    const cart = m(i, mc.VS_CART);
    return .{
        .frame = m(i, mc.VS_FRAME),
        .cart = cart,
        .fresco = seq -| (idle + hbl),
        .hbl = hbl,
        .idle = idle,
        .other = m(i, mc.VS_FRAME) -| (cart + seq),
        .passes = m(i, mc.VS_PASSES),
    };
}

/// AVG ticks averaged (1 s at main.zig's 100 ms tick), the peak over all PEAK.
pub const AVG = 10;
pub const PEAK = 30;

pub const Smooth = struct {
    ring: [PEAK]Sample = [_]Sample{.{}} ** PEAK,
    n: usize = 0, // samples held, up to PEAK
    at: usize = 0, // the next slot

    pub fn reset(self: *Smooth) void {
        self.n = 0;
        self.at = 0;
    }

    pub fn push(self: *Smooth, s: Sample) void {
        self.ring[self.at] = s;
        self.at = (self.at + 1) % PEAK;
        self.n = @min(self.n + 1, PEAK);
    }

    /// The mean of the newest AVG samples, or null with none.
    pub fn avg(self: *const Smooth) ?Sample {
        const k = @min(self.n, AVG);
        if (k == 0) return null;
        var sum = [_]u64{0} ** 7;
        for (0..k) |j| {
            const s = self.ring[(self.at + PEAK - 1 - j) % PEAK];
            inline for (std.meta.fields(Sample), 0..) |f, x| sum[x] += @field(s, f.name);
        }
        var out: Sample = .{};
        inline for (std.meta.fields(Sample), 0..) |f, x| @field(out, f.name) = @intCast(sum[x] / k);
        return out;
    }

    /// The largest busy() and cart over every sample held.
    pub fn peak(self: *const Smooth) Sample {
        var out: Sample = .{};
        for (self.ring[0..self.n]) |s| {
            if (s.busy() > out.busy()) out = s;
        }
        return out;
    }
};

/// "1.23" from cycles, in Mc with two decimals.
pub fn mcText(buf: []u8, cycles: u64) []const u8 {
    const h = (cycles + 5_000) / 10_000; // hundredths of a Mc
    return std.fmt.bufPrint(buf, "{d}.{d:0>2}", .{ h / 100, h % 100 }) catch "?";
}

/// "1.0" planes from passes.
pub fn planesText(buf: []u8, passes: u32) []const u8 {
    const t = (passes * 10 + LINES / 2) / LINES;
    return std.fmt.bufPrint(buf, "{d}.{d}", .{ t / 10, t % 10 }) catch "?";
}

/// The share of the 60 fps frame the work uses, in percent.
pub fn percent(s: Sample) u32 {
    return @intCast((@as(u64, s.busy()) * 100 + FRAME_60 / 2) / FRAME_60);
}
