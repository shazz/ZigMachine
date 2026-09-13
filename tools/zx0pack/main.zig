// zx0pack — pack files into ZigMachine's ZX0 container (libs/zig/depackers/zx0.zig).
//
//   zx0pack [--fx F] [--text MSG] <in> <out>
//       pack one file, verify it depacks bit-exact, write it (always repacks)
//   zx0pack [--fx F] [--text MSG] [--stats] [--force] --pairs <in> <out> [<in> <out>...]
//   zx0pack [--stats] [--force] --manifest <file>
//       batch: skip every output newer than its input (unless --force), keep
//       going past failures, exit 1 if any file failed
//   zx0pack -m <file>...
//       measure only, nothing written: "raw packed path" per file
//
// F is none|rasters|bar|text|fade|noise|automation (the effect shown while the cart depacks);
// --text is required with text and rejected otherwise; --bars N (AtariDecrunch's
// MaxBarHeight, 0..255: Kick Off 2 100, Elite Snooker 30) likewise with automation.
//
// Manifest: one job per line, TAB-separated `in  out  [fx  [text|bars]]`; blank
// lines and lines starting with '#' are ignored. The staleness check compares
// file times only, so after changing a line's fx or text run with --force.
//
// --stats prints one aligned line per file (name, raw, packed, ratio, pack ms)
// and a total line.
//
// build.zig builds and runs this for cart assets that embed packed; by hand:
//   zig build-exe -OReleaseFast --dep zx0_pack -Mroot=tools/zx0pack/main.zig \
//       -Mzx0_pack=libs/zig/depackers/zx0_pack.zig
const std = @import("std");
const zx0_pack = @import("zx0_pack");
const zx0 = zx0_pack.zx0;

const Mode = enum { single, pairs, manifest, measure };

const Cli = struct {
    mode: Mode = .single,
    stats: bool = false,
    force: bool = false,
    options: zx0_pack.Options = .{},
    manifest: []const u8 = "",
    paths: std.ArrayList([]const u8) = .empty,
};

const Job = struct { in: []const u8, out: []const u8, options: zx0_pack.Options };

const Totals = struct { files: usize = 0, failed: usize = 0, raw: u64 = 0, packed_bytes: u64 = 0, ms: u64 = 0 };

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    var cli = try parseArgs(init, arena);
    switch (cli.mode) {
        .single => {
            if (cli.paths.items.len != 2) return usage("need <in> and <out>");
            const image = try packVerified(init.gpa, init.io, cli.paths.items[0], cli.options);
            defer init.gpa.free(image.bytes);
            try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = cli.paths.items[1], .data = image.bytes });
        },
        .measure => for (cli.paths.items) |path| {
            const image = try packVerified(init.gpa, init.io, path, .{});
            defer init.gpa.free(image.bytes);
            std.debug.print("{d} {d} {s}\n", .{ image.raw_len, image.bytes.len, path });
        },
        .pairs, .manifest => {
            const jobs = if (cli.mode == .pairs) try pairJobs(&cli, arena) else try manifestJobs(init, arena, cli.manifest);
            var totals = Totals{};
            for (jobs) |job| runJob(init, cli, job, &totals);
            if (cli.stats) printTotal(totals);
            if (totals.failed > 0) {
                std.debug.print("zx0pack: {d} of {d} file(s) failed\n", .{ totals.failed, totals.files });
                std.process.exit(1);
            }
        },
    }
}

fn parseArgs(init: std.process.Init, arena: std.mem.Allocator) !Cli {
    var args = init.minimal.args.iterate();
    _ = args.next();
    var cli = Cli{};
    while (args.next()) |arg| {
        if (eql(arg, "-m")) {
            cli.mode = .measure;
        } else if (eql(arg, "--pairs")) {
            cli.mode = .pairs;
        } else if (eql(arg, "--manifest")) {
            cli.mode = .manifest;
            cli.manifest = args.next() orelse return usage("--manifest needs a file");
        } else if (eql(arg, "--stats")) {
            cli.stats = true;
        } else if (eql(arg, "--force")) {
            cli.force = true;
        } else if (eql(arg, "--fx")) {
            const name = args.next() orelse return usage("--fx needs a value");
            cli.options.fx = zx0_pack.parseFx(name) orelse return usage("unknown effect (none|rasters|bar|text|fade|noise|automation)");
        } else if (eql(arg, "--text")) {
            cli.options.text = args.next() orelse return usage("--text needs a value");
        } else if (eql(arg, "--bars")) {
            const n = args.next() orelse return usage("--bars needs a value");
            cli.options.bars = std.fmt.parseInt(u8, n, 10) catch return usage("--bars is 0..255");
        } else {
            try cli.paths.append(arena, arg);
        }
    }
    return cli;
}

fn eql(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

fn usage(why: []const u8) error{Usage} {
    std.debug.print("zx0pack: {s}\n" ++
        "usage: zx0pack [--fx none|rasters|bar|text|fade|noise|automation] [--text MSG] [--bars N] <in> <out>\n" ++
        "       zx0pack [--fx F] [--text MSG] [--stats] [--force] --pairs <in> <out>...\n" ++
        "       zx0pack [--stats] [--force] --manifest <file>\n" ++
        "       zx0pack -m <file>...\n", .{why});
    return error.Usage;
}

fn pairJobs(cli: *const Cli, arena: std.mem.Allocator) ![]Job {
    const p = cli.paths.items;
    if (p.len == 0 or p.len % 2 != 0) return usage("--pairs needs <in> <out> pairs");
    const jobs = try arena.alloc(Job, p.len / 2);
    for (jobs, 0..) |*j, i| j.* = .{ .in = p[2 * i], .out = p[2 * i + 1], .options = cli.options };
    return jobs;
}

fn manifestJobs(init: std.process.Init, arena: std.mem.Allocator, path: []const u8) ![]Job {
    const text = std.Io.Dir.cwd().readFileAlloc(init.io, path, arena, .limited(1 << 20)) catch |err| {
        std.debug.print("zx0pack: {s}: {s}\n", .{ path, @errorName(err) });
        return err;
    };
    var jobs: std.ArrayList(Job) = .empty;
    var lines = std.mem.splitScalar(u8, text, '\n');
    var n: usize = 0;
    while (lines.next()) |raw_line| {
        n += 1;
        const line = std.mem.trimEnd(u8, raw_line, "\r");
        if (line.len == 0 or line[0] == '#') continue;
        var fields = std.mem.splitScalar(u8, line, '\t');
        var job = Job{ .in = fields.next().?, .out = fields.next() orelse "", .options = .{} };
        if (job.out.len == 0) return manifestError(path, n, "needs <in> TAB <out>");
        if (fields.next()) |fx| job.options.fx = zx0_pack.parseFx(fx) orelse return manifestError(path, n, "unknown effect");
        if (fields.next()) |param| {
            // the 4th field is the effect's parameter: text's message, automation's bar height
            if (job.options.fx == .automation) {
                job.options.bars = std.fmt.parseInt(u8, param, 10) catch return manifestError(path, n, "bar height is 0..255");
            } else job.options.text = param;
        }
        try jobs.append(arena, job);
    }
    return jobs.items;
}

fn manifestError(path: []const u8, line: usize, why: []const u8) error{Manifest} {
    std.debug.print("zx0pack: {s}:{d}: {s}\n", .{ path, line, why });
    return error.Manifest;
}

fn runJob(init: std.process.Init, cli: Cli, job: Job, totals: *Totals) void {
    totals.files += 1;
    const t0 = std.Io.Timestamp.now(init.io, .awake);
    if (!cli.force) if (upToDate(init.io, job)) |sizes| {
        totals.raw += sizes.raw;
        totals.packed_bytes += sizes.out;
        if (cli.stats) printLine(job.in, sizes.raw, sizes.out, null);
        return;
    };
    const image = packVerified(init.gpa, init.io, job.in, job.options) catch {
        totals.failed += 1;
        return;
    };
    defer init.gpa.free(image.bytes);
    std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = job.out, .data = image.bytes }) catch |err| {
        std.debug.print("zx0pack: {s}: {s}\n", .{ job.out, @errorName(err) });
        totals.failed += 1;
        return;
    };
    const ms: u64 = @intCast(@max(0, t0.untilNow(init.io, .awake).toMilliseconds()));
    totals.raw += image.raw_len;
    totals.packed_bytes += image.bytes.len;
    totals.ms += ms;
    if (cli.stats) printLine(job.in, image.raw_len, image.bytes.len, ms);
}

/// Sizes of a job whose output is already newer than its input, else null.
fn upToDate(io: std.Io, job: Job) ?struct { raw: u64, out: u64 } {
    const cwd = std.Io.Dir.cwd();
    const in = cwd.statFile(io, job.in, .{}) catch return null;
    const out = cwd.statFile(io, job.out, .{}) catch return null;
    if (out.mtime.toNanoseconds() < in.mtime.toNanoseconds()) return null;
    return .{ .raw = in.size, .out = out.size };
}

fn printLine(name: []const u8, raw: u64, packed_len: u64, ms: ?u64) void {
    const ratio = if (raw == 0) 100.0 else 100.0 * @as(f64, @floatFromInt(packed_len)) / @as(f64, @floatFromInt(raw));
    if (ms) |t| {
        std.debug.print("{s:<60} {d:>9} {d:>9} {d:>6.1}% {d:>7} ms\n", .{ name, raw, packed_len, ratio, t });
    } else {
        std.debug.print("{s:<60} {d:>9} {d:>9} {d:>6.1}%  up to date\n", .{ name, raw, packed_len, ratio });
    }
}

fn printTotal(t: Totals) void {
    const ratio = if (t.raw == 0) 100.0 else 100.0 * @as(f64, @floatFromInt(t.packed_bytes)) / @as(f64, @floatFromInt(t.raw));
    std.debug.print("{s:<60} {d:>9} {d:>9} {d:>6.1}% {d:>7} ms  ({d} files, {d} failed)\n", .{ "TOTAL", t.raw, t.packed_bytes, ratio, t.ms, t.files, t.failed });
}

const Packed = struct { raw_len: usize, bytes: []u8 };

/// Pack a file and refuse to hand back anything that does not depack to it.
/// Every failure is printed with the file's name before it is returned.
fn packVerified(gpa: std.mem.Allocator, io: std.Io, path: []const u8, options: zx0_pack.Options) !Packed {
    errdefer |err| std.debug.print("zx0pack: {s}: {s}\n", .{ path, @errorName(err) });
    const data = try std.Io.Dir.cwd().readFileAlloc(io, path, gpa, .limited(64 << 20));
    defer gpa.free(data);
    const image = try zx0_pack.pack(gpa, data, options);
    errdefer gpa.free(image);
    const check = try gpa.alloc(u8, data.len);
    defer gpa.free(check);
    const n = zx0.depack(image, check) orelse return error.VerifyFailed;
    if (n != data.len or !std.mem.eql(u8, check, data)) return error.VerifyFailed;
    return .{ .raw_len = data.len, .bytes = image };
}
