// replay.zig: run a VIC write stream (tools/c64/trace_bin.py from VICE, or the scene's own,
// tools/c64/scene_dump.zig) through the scene's sprite unit.
//   zig build-exe --dep vic -Mroot=tools/c64/replay.zig -Mvic=apps/zig/scenes/c64_1988/vic.zig
//   ./replay <writes.bin> <regs.vic> <bank3.bin> <bank0.bin> <outdir> <frame>...
//       dumps <outdir>/f<N>.pix (400x280 indices) and f<N>.border (border, split_x, split_c)
//   ./replay --diff <a.bin> <b.bin> <regs.vic> <bank3.bin> <bank0.bin>
//       runs both streams in lockstep and lists the frames whose VICE-window pictures differ
const std = @import("std");
const vic = @import("vic");

const Run = struct {
    v: vic.Vic,
    out: vic.Out,
    q: *vic.Queue,
    bin: []const u8,
    off: usize = 0,

    fn init(a: std.mem.Allocator, bin: []const u8, regs: []const u8) !Run {
        const pix = try a.create([vic.Out.ROWS_COLS]u8);
        @memset(pix, 0);
        return .{ .v = vic.Vic.init(regs[0..vic.NREG].*), .out = .{ .pix = pix }, .q = try a.create(vic.Queue), .bin = bin };
    }

    fn next(self: *Run, mem: vic.Mem) bool {
        if (self.off + 4 > self.bin.len) return false;
        const count = std.mem.readInt(u32, self.bin[self.off..][0..4], .little);
        self.off += 4;
        self.q.n = 0;
        for (0..count) |_| {
            const r = self.bin[self.off..][0..5];
            self.q.w(std.mem.readInt(u16, r[0..2], .little), r[2], r[3], r[4]);
            self.off += 5;
        }
        self.v.frame(self.q, mem, &self.out);
        return true;
    }

    // C64 colour at physical (x, y): sprite pixel, else the border (with its split).
    fn colour(self: *const Run, x: usize, y: usize) u8 {
        const p = self.out.pix[y * 400 + x];
        if (p != 0) return p - 1;
        const sx = self.out.split_x[y];
        return if (sx != 0 and x >= sx) self.out.split_c[y] else self.out.border[y];
    }
};

pub fn main(init: std.process.Init) !void {
    var args = init.minimal.args.iterate();
    _ = args.next();
    const io = init.io;
    const dir = std.Io.Dir.cwd();
    const lim: std.Io.Limit = .limited(1 << 26);
    const first = args.next().?;
    const diff = std.mem.eql(u8, first, "--diff");
    const a_bin = try dir.readFileAlloc(io, if (diff) args.next().? else first, init.gpa, lim);
    const b_bin = if (diff) try dir.readFileAlloc(io, args.next().?, init.gpa, lim) else a_bin;
    const regs = try dir.readFileAlloc(io, args.next().?, init.gpa, lim);
    const bank3 = try dir.readFileAlloc(io, args.next().?, init.gpa, lim);
    const bank0 = try dir.readFileAlloc(io, args.next().?, init.gpa, lim);
    var foreign: u32 = 0;
    const mem = vic.Mem{ .bank3 = bank3[0..16384], .bank0_2000 = bank0[0..2048], .foreign = &foreign };
    var a = try Run.init(init.gpa, a_bin, regs);
    if (diff) return lockstep(&a, try Run.init(init.gpa, b_bin, regs), mem);
    const outdir = args.next().?;
    var want = std.ArrayList(u32).empty;
    while (args.next()) |w| try want.append(init.gpa, try std.fmt.parseInt(u32, w, 10));
    var n: u32 = 1;
    while (a.next(mem)) : (n += 1) {
        for (want.items) |f| if (f == n) try dump(io, dir, outdir, n, &a.out);
    }
    std.debug.print("{d} frames, {d} foreign fetches\n", .{ n - 1, foreign });
}

fn lockstep(a: *Run, b_in: Run, mem: vic.Mem) void {
    var b = b_in;
    var n: u32 = 1;
    var bad: u32 = 0;
    while (a.next(mem) and b.next(mem)) : (n += 1) {
        var cnt: u32 = 0;
        var row0: usize = 999;
        for (5..277) |y| for (8..392) |x| if (a.colour(x, y) != b.colour(x, y)) {
            cnt += 1;
            row0 = @min(row0, y);
        };
        if (cnt == 0) continue;
        bad += 1;
        if (bad <= 60) std.debug.print("f{d}: {d} px differ from row {d}\n", .{ n, cnt, row0 });
    }
    std.debug.print("{d} frames compared, {d} differ\n", .{ n - 1, bad });
}

fn dump(io: std.Io, dir: std.Io.Dir, outdir: []const u8, n: u32, out: *const vic.Out) !void {
    var name: [256]u8 = undefined;
    try dir.writeFile(io, .{ .sub_path = try std.fmt.bufPrint(&name, "{s}/f{d}.pix", .{ outdir, n }), .data = out.pix });
    var b: [280 * 4]u8 = undefined; // border, split_x (u16 little-endian), split_c
    @memcpy(b[0..280], &out.border);
    for (0..280) |r| std.mem.writeInt(u16, b[280 + 2 * r ..][0..2], out.split_x[r], .little);
    @memcpy(b[840..1120], &out.split_c);
    try dir.writeFile(io, .{ .sub_path = try std.fmt.bufPrint(&name, "{s}/f{d}.border", .{ outdir, n }), .data = &b });
}
