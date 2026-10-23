// --------------------------------------------------------------------------
// gen_anima: the build-time generator of ANIMA's logo and scroller font.
//
//   gen_anima <font16.raw> <anima_logo.bin> <anima_font.bin>
//
// build.zig runs it on the HOST and embeds both outputs in the carts' generated
// packed_assets module; art.zig says what they are and how they are made.
// Deterministic: the same font gives the same bytes.
// --------------------------------------------------------------------------
const std = @import("std");
const art = @import("art.zig");
const gen = @import("gen.zig");

var logo: [art.LH * art.LW]u8 = undefined;
var strip: [art.CELL_H * art.STRIP_W]u8 = undefined;

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    var args = init.minimal.args.iterate();
    _ = args.next();
    const font_path = args.next() orelse return error.Usage;
    const logo_path = args.next() orelse return error.Usage;
    const font_out = args.next() orelse return error.Usage;
    const cwd = std.Io.Dir.cwd();
    const font = try cwd.readFileAlloc(io, font_path, init.arena.allocator(), .limited(1 << 16));
    if (font.len != gen.SHEET_BYTES) return error.FontSize;
    art.buildLogo(font[0..gen.SHEET_BYTES], &logo);
    art.buildFont(font[0..gen.SHEET_BYTES], &strip);
    try cwd.writeFile(io, .{ .sub_path = logo_path, .data = &logo });
    try cwd.writeFile(io, .{ .sub_path = font_out, .data = &strip });
}
