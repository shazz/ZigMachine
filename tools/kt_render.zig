// kt_render: the BARD .kt player's core (libs/zig/players/kt_core.zig) renders a song natively, as
// apps/ports/klystrack/kt_ref renders it with upstream's cyd: the two raw files compare byte for byte.
//
//   kt_render <song.kt> <seconds> <out.s16> [trace]   interleaved stereo s16le at 22050 Hz; with
//                                                     a trace count, each channel's state after each of
//                                                     the first ticks, as kt_ref --trace prints it
//
//   zig build-exe -OReleaseFast --dep kt -Mroot=tools/kt_render.zig -Mkt=libs/zig/players/kt_core.zig
const std = @import("std");
const kt = @import("kt");

pub fn main(init: std.process.Init) !void {
    var args = init.minimal.args.iterate();
    _ = args.next();
    const in = args.next() orelse return usage();
    const secs_s = args.next() orelse return usage();
    const out = args.next() orelse return usage();
    const secs = try std.fmt.parseFloat(f64, secs_s);
    const src = try std.Io.Dir.cwd().readFileAlloc(init.io, in, init.gpa, .limited(1 << 20));
    defer init.gpa.free(src);
    const mem = try init.gpa.alloc(u8, 1 << 20);
    defer init.gpa.free(mem);
    const core = try init.gpa.create(kt.Core);
    defer init.gpa.destroy(core);
    core.* = .{};
    try core.load(src, mem);
    try core.start(kt.RATE);
    if (args.next()) |t| {
        trace_left = try std.fmt.parseInt(u32, t, 10);
        core.engine.on_tick = trace;
    }
    const n: usize = @intFromFloat(secs * kt.RATE);
    const pcm = try init.gpa.alloc(i16, 2 * n);
    defer init.gpa.free(pcm);
    var at: usize = 0;
    while (at < n) { // in 2000-sample blocks, as kt_ref (the block size does not change the output)
        const k: usize = @min(2000, n - at);
        core.render(pcm[2 * at ..][0 .. 2 * k]);
        at += k;
    }
    try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = out, .data = std.mem.sliceAsBytes(pcm) });
}

var trace_left: u32 = 0;
var trace_tick: u32 = 0;

fn trace(e: *const kt.Engine) void {
    if (trace_left == 0) return;
    trace_left -= 1;
    for (e.synth.chn[0..e.synth.n], 0..) |*c, i| {
        std.debug.print("T{d} c{d} n={d} vp={d} arp={d} fix={d} fl={x} pw={d} f={d} acc={d} env={d} st={d} vol={d} ft={d} fx={d} pan={d}\n", .{
            trace_tick, i, e.chn[i].note, e.track[i].vibrato_position, e.chn[i].arpeggio_note, e.chn[i].fixed_note, c.flags,      c.pw,        c.subosc[0].frequency, c.subosc[0].accumulator,
            c.adsr.envelope,      c.adsr.state,   c.adsr.volume, c.flttype,  c.fx_bus,             c.panning,
        });
    }
    trace_tick += 1;
}

fn usage() error{Usage} {
    std.debug.print("usage: kt_render <song.kt> <seconds> <out.s16>\n", .{});
    return error.Usage;
}
