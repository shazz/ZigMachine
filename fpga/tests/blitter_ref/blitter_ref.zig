//! The blitter oracle for the RTL: machine/blitter.zig itself (module `blitter`,
//! unchanged) run natively. It reads and writes linear addresses (HW_VIDEO_BASE =
//! 0x300000), so the harness maps the machine's memory at those very addresses.
//!
//!   blitter_ref <script> <trace>
//!
//! Script lines (tests/tb/blitter_script.h reads the same; `#` starts a comment):
//!   seed <n>             fill 0x100000..0x700000 from a PRNG (few distinct bytes, so keys hit);
//!                        the register block (offsets 0..0xFF) is kept
//!   w8|w16|w32 <off> <v> write the register at video-region offset <off> (little-endian)
//!   run <cmd>            write COMMAND = cmd, then hwBlit(); emits a trace line
//!   dump <file>          write the 6 MiB window raw
//! A trace line is `R <n> <cycles> <status> <hash>`: the hash covers the window except the
//! video register block (the RTL has its own).
const std = @import("std");
const blitter = @import("blitter");

const LO: usize = 0x100000;
const HI: usize = 0x700000;
const VIDEO: usize = 0x300000; // memmap.HW_VIDEO_BASE
const REGS_END: usize = VIDEO + 0x100; // the register block: not memory
const CMD: usize = 0x80; // memmap.BLIT_COMMAND
const STATUS: usize = 0x83;
const CYCLES: usize = 0xE0;
const PAL = [8]u8{ 0, 1, 2, 0x55, 0xAA, 0xFF, 0x0F, 0xF0 };

extern "c" fn mmap(addr: ?*anyopaque, len: usize, prot: c_int, flags: c_int, fd: c_int, off: i64) ?*anyopaque;

var win: []u8 = undefined; // the window, win[0] = address LO
var rng: u64 = 1;
var gpa: std.mem.Allocator = undefined;
var out: std.ArrayList(u8) = .empty;
var runs: u32 = 0;

fn next() u64 {
    rng ^= rng << 13;
    rng ^= rng >> 7;
    rng ^= rng << 17;
    return rng;
}

fn seed(n: u64) void {
    var regs: [REGS_END - VIDEO]u8 = undefined; // the register block survives a re-seed
    @memcpy(&regs, win[VIDEO - LO .. REGS_END - LO]);
    rng = n *% 0x9E3779B97F4A7C15 +% 1;
    for (LO..HI) |a| {
        const v: u8 = @truncate(next() >> 16);
        win[a - LO] = if (v & 0xE0 == 0) v else PAL[v & 7];
    }
    @memcpy(win[VIDEO - LO .. REGS_END - LO], &regs);
}

fn mix(h0: u64, from: usize, to: usize) u64 {
    var h = h0;
    var a = from;
    while (a < to) : (a += 8) {
        h = (h ^ std.mem.readInt(u64, win[a - LO ..][0..8], .little)) *% 0x100000001b3;
        h ^= h >> 29;
    }
    return h;
}

fn hash() u64 {
    return mix(mix(0xcbf29ce484222325, LO, VIDEO), REGS_END, HI);
}

fn reg(off: usize, size: usize, v: u32) void {
    for (0..size) |k| win[VIDEO - LO + off + k] = @truncate(v >> @intCast(8 * k));
}

fn run(cmd: u8) !void {
    win[VIDEO - LO + CMD] = cmd;
    blitter.execute();
    const cycles = std.mem.readInt(u32, win[VIDEO - LO + CYCLES ..][0..4], .little);
    const line = try std.fmt.allocPrint(gpa, "R {d} {d} {d} {x:0>16}\n", .{ runs, cycles, win[VIDEO - LO + STATUS], hash() });
    try out.appendSlice(gpa, line);
    runs += 1;
}

fn num(it: *std.mem.TokenIterator(u8, .any)) !u64 {
    return std.fmt.parseInt(u64, it.next() orelse return error.Syntax, 0);
}

fn command(io: std.Io, raw: []const u8) !void {
    const line = if (std.mem.indexOfScalar(u8, raw, '#')) |i| raw[0..i] else raw;
    var it = std.mem.tokenizeAny(u8, line, " \t\r");
    const op = it.next() orelse return;
    if (std.mem.eql(u8, op, "seed")) {
        seed(try num(&it));
    } else if (std.mem.eql(u8, op, "run")) {
        try run(@intCast(try num(&it)));
    } else if (std.mem.eql(u8, op, "dump")) {
        try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = it.next() orelse return error.Syntax, .data = win });
    } else if (op[0] == 'w') {
        const size: usize = (try std.fmt.parseInt(usize, op[1..], 10)) / 8;
        const off: usize = @intCast(try num(&it));
        reg(off, size, @intCast(try num(&it)));
    } else return error.Syntax;
}

pub fn main(init: std.process.Init) !void {
    gpa = init.arena.allocator();
    var args = init.minimal.args.iterate();
    _ = args.next();
    const script_path = args.next() orelse return error.Usage;
    const trace_path = args.next() orelse return error.Usage;
    // MAP_PRIVATE | MAP_ANONYMOUS | MAP_FIXED_NOREPLACE, PROT_READ | PROT_WRITE
    const p = mmap(@ptrFromInt(LO), HI - LO, 3, 0x2 | 0x20 | 0x100000, -1, 0) orelse return error.Mmap;
    if (@intFromPtr(p) != LO) return error.Mmap;
    win = @as([*]u8, @ptrCast(p))[0 .. HI - LO];
    seed(1);
    const script = try std.Io.Dir.cwd().readFileAlloc(init.io, script_path, gpa, .limited(1 << 26));
    var lines = std.mem.splitScalar(u8, script, '\n');
    while (lines.next()) |l| try command(init.io, l);
    try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = trace_path, .data = out.items });
}
