//! Does cycles/bdinval.h invalidate every D-cache line a blitter op changes? machine/blitter.zig
//! (module `blitter`, unchanged, as in blitter_ref.zig) runs a blitter script natively over the
//! machine's memory mapped at its linear addresses; before each `run`, bdi_range() (dinval_host.c)
//! names the lines it would invalidate, and after it every 32-byte line of the window whose bytes
//! changed must be one of them, unless bdi_range() asked for the whole-cache invalidate.
//!
//!   dinval_check <script>
//!
//! Prints `DINVAL runs <n> range <n> full <n> empty <n> lines <n> uncovered <n>` and exits 1 on an
//! uncovered line (each one printed as `MISS <run> <cmd> <addr>`). The script format is
//! blitter_ref.zig's; `dump` is ignored.
const std = @import("std");
const blitter = @import("blitter");

const LO: usize = 0x100000;
const HI: usize = 0x700000;
const VIDEO: usize = 0x300000; // memmap.HW_VIDEO_BASE
const REGS_END: usize = VIDEO + 0x100; // the register block: STATUS and CYCLES are the CPU's
const CMD: usize = 0x80; // memmap.BLIT_COMMAND
const LINE: usize = 32;
const PAL = [8]u8{ 0, 1, 2, 0x55, 0xAA, 0xFF, 0x0F, 0xF0 };

extern "c" fn mmap(addr: ?*anyopaque, len: usize, prot: c_int, flags: c_int, fd: c_int, off: i64) ?*anyopaque;
extern fn dinval_host_range(r: [*]const u8, cmd: u8, lines: *[*]const usize, n: *c_uint) c_int;

var win: []u8 = undefined; // the window, win[0] = address LO
var before: []u8 = undefined;
var rng: u64 = 1;
var runs: u32 = 0;
var n_range: u32 = 0;
var n_full: u32 = 0;
var n_empty: u32 = 0;
var n_lines: u64 = 0;
var n_miss: u32 = 0;

fn next() u64 {
    rng ^= rng << 13;
    rng ^= rng >> 7;
    rng ^= rng << 17;
    return rng;
}

fn seed(n: u64) void { // blitter_ref.zig's seed(): the same memory image
    var regs: [REGS_END - VIDEO]u8 = undefined;
    @memcpy(&regs, win[VIDEO - LO .. REGS_END - LO]);
    rng = n *% 0x9E3779B97F4A7C15 +% 1;
    for (LO..HI) |a| {
        const v: u8 = @truncate(next() >> 16);
        win[a - LO] = if (v & 0xE0 == 0) v else PAL[v & 7];
    }
    @memcpy(win[VIDEO - LO .. REGS_END - LO], &regs);
}

fn reg(off: usize, size: usize, v: u32) void {
    for (0..size) |k| win[VIDEO - LO + off + k] = @truncate(v >> @intCast(8 * k));
}

fn covered(lines: []const usize, a: usize) bool {
    for (lines) |l| if (l == a) return true;
    return false;
}

fn run(cmd: u8) !void {
    win[VIDEO - LO + CMD] = cmd;
    var lp: [*]const usize = undefined;
    var n: c_uint = 0;
    const ok = dinval_host_range(win[VIDEO - LO ..].ptr, cmd, &lp, &n);
    if (ok < 0) return error.TooManyLines;
    const lines = lp[0..n];
    @memcpy(before, win);
    blitter.execute();
    var changed: u32 = 0;
    var a: usize = LO;
    while (a < HI) : (a += LINE) {
        if (a + LINE > VIDEO and a < REGS_END) continue;
        if (std.mem.eql(u8, win[a - LO ..][0..LINE], before[a - LO ..][0..LINE])) continue;
        changed += 1;
        if (ok == 0 or covered(lines, a)) continue;
        n_miss += 1;
        if (n_miss <= 20) std.debug.print("MISS {d} {d} 0x{x}\n", .{ runs, cmd, a });
    }
    if (ok == 0) n_full += 1 else if (n == 0) n_empty += 1 else n_range += 1;
    n_lines += n;
    runs += 1;
}

fn num(it: *std.mem.TokenIterator(u8, .any)) !u64 {
    return std.fmt.parseInt(u64, it.next() orelse return error.Syntax, 0);
}

fn command(raw: []const u8) !void {
    const line = if (std.mem.indexOfScalar(u8, raw, '#')) |i| raw[0..i] else raw;
    var it = std.mem.tokenizeAny(u8, line, " \t\r");
    const op = it.next() orelse return;
    if (std.mem.eql(u8, op, "seed")) {
        seed(try num(&it));
    } else if (std.mem.eql(u8, op, "run")) {
        try run(@intCast(try num(&it)));
    } else if (std.mem.eql(u8, op, "dump")) {
        return;
    } else if (op[0] == 'w') {
        const size: usize = (try std.fmt.parseInt(usize, op[1..], 10)) / 8;
        const off: usize = @intCast(try num(&it));
        reg(off, size, @intCast(try num(&it)));
    } else return error.Syntax;
}

pub fn main(init: std.process.Init) !void {
    const gpa = init.arena.allocator();
    var args = init.minimal.args.iterate();
    _ = args.next();
    const script_path = args.next() orelse return error.Usage;
    // MAP_PRIVATE | MAP_ANONYMOUS | MAP_FIXED_NOREPLACE, PROT_READ | PROT_WRITE
    const p = mmap(@ptrFromInt(LO), HI - LO, 3, 0x2 | 0x20 | 0x100000, -1, 0) orelse return error.Mmap;
    if (@intFromPtr(p) != LO) return error.Mmap;
    win = @as([*]u8, @ptrCast(p))[0 .. HI - LO];
    before = try gpa.alloc(u8, HI - LO);
    seed(1);
    const script = try std.Io.Dir.cwd().readFileAlloc(init.io, script_path, gpa, .limited(1 << 26));
    var lines = std.mem.splitScalar(u8, script, '\n');
    while (lines.next()) |l| try command(l);
    std.debug.print("DINVAL runs {d} range {d} full {d} empty {d} lines {d} uncovered {d}\n", .{ runs, n_range, n_full, n_empty, n_lines, n_miss });
    if (n_miss != 0) std.process.exit(1);
}
