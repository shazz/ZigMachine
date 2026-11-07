// scene_dump.zig: run the scene's show (apps/zig/scenes/c64_1988/show.zig) natively and write
// its VIC writes, frame by frame, in trace_bin.py's format (lines >= 312 are the next frame's:
// the sprite unit carries them, as it does in the cart).
//   zig build-exe --dep show -Mroot=tools/c64/scene_dump.zig -Mshow=apps/zig/scenes/c64_1988/show.zig
//   ./scene_dump <assets dir> <out.bin> <frames>
const std = @import("std");
const show_mod = @import("show");

pub fn main(init: std.process.Init) !void {
    var args = init.minimal.args.iterate();
    _ = args.next();
    const io = init.io;
    const dir = std.Io.Dir.cwd();
    const assets = try dir.openDir(io, args.next().?, .{});
    const out_path = args.next().?;
    const frames = try std.fmt.parseInt(u32, args.next().?, 10);
    const lim: std.Io.Limit = .limited(1 << 20);
    const bank3 = try assets.readFileAlloc(io, "bank3.bin", init.gpa, lim);
    const bank0 = try assets.readFileAlloc(io, "bank0.bin", init.gpa, lim);
    const rip = try assets.readFileAlloc(io, "ripped.bin", init.gpa, lim);
    const d = show_mod.Data{ .bank3 = bank3[0..16384], .bank0 = bank0[0..2048], .rip = rip[0..show_mod.RIPPED_LEN] };

    const show = try init.gpa.create(show_mod.Show);
    show.* = show_mod.Show.init(d);
    const pix = try init.gpa.create([show_mod.vic.Out.ROWS_COLS]u8);
    @memset(pix, 0);
    var out = show_mod.vic.Out{ .pix = pix };
    var bin = std.ArrayList(u8).empty;
    for (0..frames) |_| {
        show.step(&out);
        const it = show.q.items(); // the sprite unit needs line order (lines >= 312 last)
        for (1..@max(it.len, 1)) |i| if (it[i].line < it[i - 1].line) {
            std.debug.print("frame {d} ({s}): write {d} line {d} after line {d}\n", .{ show.frames, @tagName(show.state), i, it[i].line, it[i - 1].line });
            break;
        };
        var count: [4]u8 = undefined;
        std.mem.writeInt(u32, &count, @intCast(show.q.n), .little);
        try bin.appendSlice(init.gpa, &count);
        for (show.q.items()) |w| {
            var r: [5]u8 = undefined;
            std.mem.writeInt(u16, r[0..2], w.line, .little);
            r[2] = w.cyc;
            r[3] = w.reg;
            r[4] = w.val;
            try bin.appendSlice(init.gpa, &r);
        }
    }
    try dir.writeFile(io, .{ .sub_path = out_path, .data = bin.items });
    std.debug.print("{d} frames, state {s}, foreign {d}\n", .{ frames, @tagName(show.state), show.foreign });
}
