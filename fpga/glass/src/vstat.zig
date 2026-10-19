// The video probe for the control channel's ZMSTAT line: where ZIGGY's frame goes, as the
// firmware measured it (map_cart.zig "the video probe", cycles/vstat.h). The block holds per-frame
// MEANS over the firmware's own last window (VS_N frames, about a quarter second at 60 fps), not
// over the `stats` window. Read past the writer: taken only when VS_SEQ is the same even value
// before and after the copy. The calibration block (VCAL) is written once, at the cart's boot.
const std = @import("std");
const mc = @import("map_cart.zig");
const bus = @import("bus.zig");

pub const NMEAN = mc.VSTAT_WORDS - mc.VS_FRAME;
pub const NCAL = mc.VCAL_WORDS - mc.VC_MIX1;

pub const Info = struct {
    ok: bool = false, // a whole window was read
    n: u32 = 0,
    flags: u32 = 0,
    mean: [NMEAN]u32 = [_]u32{0} ** NMEAN,
    cal: ?[NCAL]u32 = null,
};

const TRIES = 4;

pub fn read(ddr: bus.Ddr) Info {
    if (ddr.bytes() < mc.MB_BYTES) return .{};
    const mb = (ddr.bytes() - mc.MB_BYTES) / 4;
    const at = mb + mc.VSTAT_AT;
    const info = Info{ .cal = readCal(ddr) };
    if (ddr.words[mb] != mc.MB_MAGIC or ddr.words[at + mc.VS_MAGIC] != mc.VSTAT_MAGIC) return info;
    var w: [mc.VSTAT_WORDS]u32 = undefined;
    for (0..TRIES) |_| {
        const seq = ddr.words[at + mc.VS_SEQ];
        for (&w, 0..) |*x, i| x.* = ddr.words[at + i];
        if (seq & 1 == 0 and ddr.words[at + mc.VS_SEQ] == seq) return decode(&w, info.cal);
    }
    return info;
}

pub fn decode(w: *const [mc.VSTAT_WORDS]u32, cal: ?[NCAL]u32) Info {
    var info = Info{ .cal = cal, .n = w[mc.VS_N], .flags = w[mc.VS_FLAGS] };
    info.ok = w[mc.VS_MAGIC] == mc.VSTAT_MAGIC and info.n != 0; // n = 0: no window closed yet
    @memcpy(&info.mean, w[mc.VS_FRAME..]);
    return info;
}

fn readCal(ddr: bus.Ddr) ?[NCAL]u32 {
    if (ddr.bytes() < mc.VCAL_FROM_TOP) return null; // a test's one-page window
    const at = (ddr.bytes() - mc.VCAL_FROM_TOP) / 4;
    if (ddr.words[at + mc.VC_MAGIC] != mc.VCAL_MAGIC or ddr.words[at + mc.VC_REPS] != mc.VCAL_REPS) return null;
    var c: [NCAL]u32 = undefined;
    for (&c, 0..) |*x, i| x.* = ddr.words[at + mc.VC_MIX1 + i];
    return c;
}

// The fields, in the line's order: key and the block word they show.
const KEYS = [_]struct { []const u8, u32 }{
    .{ "frame_c", mc.VS_FRAME },  .{ "cart_c", mc.VS_CART },        .{ "seq_c", mc.VS_SEQC },
    .{ "wait_ready", mc.VS_READY }, .{ "drain", mc.VS_DRAIN },    .{ "painted", mc.VS_PAINTED },
    .{ "hbl", mc.VS_HBL },        .{ "plan", mc.VS_PLAN },          .{ "passes", mc.VS_PASSES },
    .{ "comp_busy", mc.VS_COMP }, .{ "dma_busy", mc.VS_DMA },       .{ "swap", mc.VS_SWAP },
};
const CAL_KEYS = [_][]const u8{ "cal_mix1", "cal_mix2", "cal_fill1", "cal_fill2" };

/// ` vs_n=.. frame_c=.. ... underrun=.. overflow=.. probe_c=.. cal_mix1=<span>/<comp> ...`,
/// every value `-` when the firmware has no probe (or no window closed yet).
pub fn write(w: *std.Io.Writer, i: *const Info) std.Io.Writer.Error!void {
    if (i.ok) try w.print(" vs_n={d}", .{i.n}) else try w.writeAll(" vs_n=-");
    for (KEYS) |k| {
        if (i.ok) try w.print(" {s}={d}", .{ k[0], i.mean[k[1] - mc.VS_FRAME] }) else try w.print(" {s}=-", .{k[0]});
    }
    if (i.ok) {
        const ur = if (i.flags & mc.VSF_UNDERRUN_AT_BOOT != 0) "boot" else if (i.flags & mc.VSF_UNDERRUN != 0) "1" else "0";
        try w.print(" underrun={s} overflow={d} probe_c={d}", .{ ur, @intFromBool(i.flags & mc.VSF_OVERFLOW != 0), i.flags >> 8 & 0xFF });
    } else try w.writeAll(" underrun=- overflow=- probe_c=-");
    for (CAL_KEYS, 0..) |k, n| {
        if (i.cal) |c| try w.print(" {s}={d}/{d}", .{ k, c[2 * n], c[2 * n + 1] }) else try w.print(" {s}=-", .{k});
    }
}
