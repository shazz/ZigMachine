// --------------------------------------------------------------------------
// The last pass of a channel's block (kt_passes.zig, kt_block.zig): ring
// modulation, the envelope and the filter on each heard sample of the
// channel's source sum, panned onto its bus; the envelope stepped every
// sample. Ring modulation reads the source sum of another channel at the same
// sample, which every channel's earlier passes have already written (cyd_output:
// a gated channel's input times its ring source's oscillators, before the
// envelope), so a block can ring-modulate and stay byte for byte the same.
// --------------------------------------------------------------------------
const c = @import("kt_cyd.zig");
const adsr = @import("kt_adsr.zig");
const filter = @import("kt_filter.zig");

/// What a ring-modulated channel multiplies by: none (no ring modulation), its source channel's
/// block of sums, or 0 (a source past the song's channels).
pub const Ring = union(enum) { none, src: [*]const i32, zero };

pub fn output(rate: u32, chp: *c.Channel, src: []const i32, ring: Ring, dl: [*]i32, dr: [*]i32, has_filter: bool) void {
    const rs: ?[*]const i32 = switch (ring) {
        .src => |p| p,
        else => null,
    };
    switch (@as(u2, @intFromBool(ring != .none)) | @as(u2, @intFromBool(has_filter)) << 1) {
        inline else => |v| run(rate, chp, src, rs, v & 1 != 0, dl, dr, v & 2 != 0),
    }
}

noinline fn run(rate: u32, chp: *c.Channel, src: []const i32, rs: ?[*]const i32, comptime ringed: bool, dl: [*]i32, dr: [*]i32, comptime has_filter: bool) void {
    var a = chp.adsr;
    var flags = chp.flags;
    var flt = chp.flt;
    const gated = flags & c.GATE != 0; // only cleared inside a block (a release running out)
    const shape = chp.ym_env_shape;
    const gl = chp.gain_left;
    const gr = chp.gain_right;
    const kind = chp.flttype;
    for (src, 0..) |s, t| {
        if (gated and flags & c.GATE != 0) {
            var input = s;
            if (ringed) {
                const m: i32 = if (rs) |p| p[t] else 0;
                input = @divTrunc(input *% (m +% c.WAVE_AMP / 2), c.WAVE_AMP);
            }
            var o = adsr.output(flags, &a, input);
            if (has_filter and flags & c.FILTER != 0) {
                filter.cycle(&flt, o);
                o = filter.output(&flt, kind);
            }
            dl[t] +%= @divTrunc(o *% gl, c.STEREO_GAIN);
            dr[t] +%= @divTrunc(o *% gr, c.STEREO_GAIN);
        }
        flags = adsr.cycle(rate, flags, shape, &a);
    }
    chp.adsr = a;
    chp.flags = flags;
    chp.flt = flt;
}
