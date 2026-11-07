// t64_show.zig: run the Transmission64 port's show natively (apps/zig/scenes/c64_transmission64/
// show.zig) and dump frames for tools/c64/compare.py against VICE captures.
//   zig build-exe --dep show -Mroot=tools/c64/t64_show.zig -Mshow=apps/zig/scenes/c64_transmission64/show.zig
//   ./t64_show <assets dir> <outdir> <frame>...      (frames ascending)
// writes <outdir>/f<N>.pix (400x280 indices) and f<N>.border (border, split_x, split_c).
const std = @import("std");
const show_mod = @import("show");
const vic = show_mod.vic;
const data = show_mod.data;

pub fn main(init: std.process.Init) !void {
    var args = init.minimal.args.iterate();
    _ = args.next();
    const io = init.io;
    const a = init.gpa;
    const dir = std.Io.Dir.cwd();
    const assets = try dir.openDir(io, args.next().?, .{});
    const outdir = try dir.openDir(io, args.next().?, .{});
    const lim: std.Io.Limit = .limited(1 << 20);
    const p1 = try assets.readFileAlloc(io, "part1.bin", a, lim);
    const wp = try assets.readFileAlloc(io, "wipe.bin", a, lim);
    const d = data.Data{ .part1 = .{ .b = p1[0..data.PART1_LEN] }, .wipe = .{ .b = wp[0..data.WIPE_LEN] } };
    const show = try a.create(show_mod.Show);
    show.init(d);
    const pix = try a.create([vic.Out.ROWS_COLS]u8);
    @memset(pix, 0);
    var out = vic.Out{ .pix = pix };
    while (args.next()) |fs| {
        const f = try std.fmt.parseInt(u32, fs, 10);
        while (show.frames < f) show.step(&out);
        var nb: [64]u8 = undefined;
        try outdir.writeFile(io, .{ .sub_path = try std.fmt.bufPrint(&nb, "f{d}.pix", .{f}), .data = pix });
        var b: [280 * 4]u8 = undefined;
        for (0..280) |r| {
            b[r] = out.border[r];
            std.mem.writeInt(u16, b[280 + 2 * r ..][0..2], out.split_x[r], .little);
            b[840 + r] = out.split_c[r];
        }
        try outdir.writeFile(io, .{ .sub_path = try std.fmt.bufPrint(&nb, "f{d}.border", .{f}), .data = &b });
    }
    std.debug.print("{d} frames, state {s}\n", .{ show.frames, @tagName(show.state) });
}
