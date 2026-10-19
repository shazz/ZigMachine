// The video probe's ZMSTAT fields (vstat.zig) over a fake top of the cart window, laid out as
// cycles/bvstat.h and cycles/vcal.c write it.
const std = @import("std");
const mc = @import("map_cart.zig");
const bus = @import("bus.zig");
const vstat = @import("vstat.zig");

const WORDS = mc.VCAL_FROM_TOP / 4; // the window's last VCAL_FROM_TOP bytes
const MB = WORDS - mc.MB_BYTES / 4;
const VS = MB + mc.VSTAT_AT;
const VC = 0;

fn window(words: *[WORDS]u32, seq: u32, cal: bool) bus.Ddr {
    @memset(words, 0);
    words[MB] = mc.MB_MAGIC;
    words[VS + mc.VS_MAGIC] = mc.VSTAT_MAGIC;
    words[VS + mc.VS_SEQ] = seq;
    words[VS + mc.VS_N] = 16;
    words[VS + mc.VS_FLAGS] = mc.VSF_UNDERRUN | 6 << 8;
    for (0..vstat.NMEAN) |i| words[VS + mc.VS_FRAME + i] = 1000 + @as(u32, @intCast(i));
    if (cal) {
        words[VC + mc.VC_MAGIC] = mc.VCAL_MAGIC;
        words[VC + mc.VC_REPS] = mc.VCAL_REPS;
        for (0..vstat.NCAL) |i| words[VC + mc.VC_MIX1 + i] = 10 + @as(u32, @intCast(i));
    }
    return .{ .words = words };
}

fn line(i: *const vstat.Info) ![]const u8 {
    const S = struct {
        var buf: [512]u8 = undefined;
    };
    var w = std.Io.Writer.fixed(&S.buf);
    try vstat.write(&w, i);
    return w.buffered();
}

test "a whole window: every mean under its key, the flags, the calibration" {
    var words: [WORDS]u32 = undefined;
    const i = vstat.read(window(&words, 8, true));
    try std.testing.expect(i.ok);
    try std.testing.expectEqualStrings(" vs_n=16 frame_c=1000 cart_c=1001 seq_c=1002 wait_ready=1003 drain=1004 painted=1005" ++
        " hbl=1006 plan=1007 passes=1008 comp_busy=1009 dma_busy=1010 swap=1011 underrun=1 overflow=0 probe_c=6" ++
        " cal_mix1=10/11 cal_mix2=12/13 cal_fill1=14/15 cal_fill2=16/17", try line(&i));
}

test "a writer mid-update, no probe, or no window yet: dashes" {
    var words: [WORDS]u32 = undefined;
    try std.testing.expect(!vstat.read(window(&words, 9, false)).ok); // odd: being written
    const none = vstat.read(window(&words, 8, false));
    try std.testing.expect(none.ok and none.cal == null);
    words[VS + mc.VS_N] = 0;
    try std.testing.expect(!vstat.read(.{ .words = &words }).ok);
    words[VS + mc.VS_MAGIC] = 0;
    const old = vstat.read(.{ .words = &words });
    try std.testing.expect(!old.ok);
    try std.testing.expect(std.mem.startsWith(u8, try line(&old), " vs_n=- frame_c=- "));
    var page: [mc.MB_BYTES / 4]u32 = [_]u32{0} ** (mc.MB_BYTES / 4);
    try std.testing.expect(vstat.read(.{ .words = &page }).cal == null); // a window too small for VCAL
}

test "underrun already set at the cart's boot says so" {
    var words: [WORDS]u32 = undefined;
    const ddr = window(&words, 2, false);
    words[VS + mc.VS_FLAGS] = mc.VSF_UNDERRUN | mc.VSF_UNDERRUN_AT_BOOT | mc.VSF_OVERFLOW;
    const s = try line(&vstat.read(ddr));
    try std.testing.expect(std.mem.indexOf(u8, s, " underrun=boot overflow=1 probe_c=0 ") != null);
}
