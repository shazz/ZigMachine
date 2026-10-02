// Exports machine/sdk/memmap.zig, the machine's single source of truth for the
// memory map, as a Verilog header or a Python module, so the RTL and the LiteX
// SoC can never drift from what the wasm machine and every cart were built
// against. Reflection rather than parsing: Zig evaluates the expressions
// (`OFF_VRAM + VRAM_BYTES`, `@as(usize, ...)`), so nothing is re-derived here.
//
//   zig run -Mroot=fpga/tools/memmap_export.zig -Mmemmap=machine/sdk/memmap.zig \
//       --dep memmap -- verilog fpga/gen/memmap.vh
//
// (The `--dep` must come before the root module; `make memmap` spells it out.)
const std = @import("std");
const memmap = @import("memmap");

const Format = enum { verilog, python };

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    var args = init.minimal.args.iterate();
    _ = args.next();
    const fmt_arg = args.next() orelse return usage();
    const out_path = args.next() orelse return usage();
    const format = std.meta.stringToEnum(Format, fmt_arg) orelse return usage();

    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(gpa);
    try header(gpa, &buf, format);
    try emitAll(gpa, &buf, format);
    try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = out_path, .data = buf.items });
}

fn usage() error{Usage} {
    std.debug.print("usage: memmap_export verilog|python <out>\n", .{});
    return error.Usage;
}

fn header(gpa: std.mem.Allocator, buf: *std.ArrayList(u8), format: Format) !void {
    const c = if (format == .verilog) "//" else "#";
    try buf.print(gpa, "{s} GENERATED from machine/sdk/memmap.zig by fpga/tools/memmap_export.zig.\n", .{c});
    try buf.print(gpa, "{s} Do not edit: change memmap.zig and run `make -C fpga memmap`.\n", .{c});
    if (format == .verilog) try buf.appendSlice(gpa, "`ifndef ZM_MEMMAP_VH\n`define ZM_MEMMAP_VH\n");
}

// Every public integer constant, in declaration order. Non-integers (types,
// functions) are skipped: the map is numbers.
fn emitAll(gpa: std.mem.Allocator, buf: *std.ArrayList(u8), format: Format) !void {
    @setEvalBranchQuota(100_000);
    inline for (@typeInfo(memmap).@"struct".decls) |decl| {
        const value = @field(memmap, decl.name);
        switch (@typeInfo(@TypeOf(value))) {
            .int, .comptime_int => try emitOne(gpa, buf, format, decl.name, value),
            else => {},
        }
    }
    if (format == .verilog) try buf.appendSlice(gpa, "`endif\n");
}

fn emitOne(gpa: std.mem.Allocator, buf: *std.ArrayList(u8), format: Format, name: []const u8, value: anytype) !void {
    const v: i64 = @intCast(value);
    switch (format) {
        .verilog => try buf.print(gpa, "localparam integer ZM_{s} = 32'h{X};\n", .{ name, @as(u64, @bitCast(v)) & 0xFFFF_FFFF }),
        .python => try buf.print(gpa, "{s} = 0x{X}\n", .{ name, v }),
    }
}
