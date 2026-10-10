//! The POKEY oracle for the RTL: libs/zig/players/pokey.zig (module `pokey`,
//! unchanged) run natively on a script of register writes.
//!
//!   pokey_ref <script> <trace>
//!
//! Script lines (tests/tb/pokey_tb.cpp reads the same; `#` starts a comment):
//!   w <addr> <data>   a register write, between two machine cycles
//!   run <n>           n machine cycles
//! The trace is 2 bytes a machine cycle, the levels after it: ch1 | ch2 << 4,
//! then ch3 | ch4 << 4.
const std = @import("std");
const pokey = @import("pokey");

var chip = pokey.Pokey{};
var gpa: std.mem.Allocator = undefined;
var out: std.ArrayList(u8) = .empty;

fn num(it: *std.mem.TokenIterator(u8, .any)) !u32 {
    return std.fmt.parseInt(u32, it.next() orelse return error.Syntax, 0);
}

fn run(n: u32) !void {
    for (0..n) |_| {
        chip.step();
        const a: u8 = chip.level(0) | @as(u8, chip.level(1)) << 4;
        const b: u8 = chip.level(2) | @as(u8, chip.level(3)) << 4;
        try out.appendSlice(gpa, &.{ a, b });
    }
}

fn command(raw: []const u8) !void {
    const line = if (std.mem.indexOfScalar(u8, raw, '#')) |i| raw[0..i] else raw;
    var it = std.mem.tokenizeAny(u8, line, " \t\r");
    const op = it.next() orelse return;
    if (std.mem.eql(u8, op, "w")) {
        const addr = try num(&it);
        chip.write(@intCast(addr & 0xF), @intCast(try num(&it)));
    } else if (std.mem.eql(u8, op, "run")) {
        try run(try num(&it));
    } else return error.Syntax;
}

pub fn main(init: std.process.Init) !void {
    gpa = init.arena.allocator();
    var args = init.minimal.args.iterate();
    _ = args.next();
    const script_path = args.next() orelse return error.Usage;
    const trace_path = args.next() orelse return error.Usage;
    const script = try std.Io.Dir.cwd().readFileAlloc(init.io, script_path, gpa, .limited(1 << 26));
    var lines = std.mem.splitScalar(u8, script, '\n');
    while (lines.next()) |l| try command(l);
    try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = trace_path, .data = out.items });
}
