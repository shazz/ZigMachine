// --------------------------------------------------------------------------
// A program's G_ICON (G16): the AES's ICONBLK as it lies in the program's memory
// (34 bytes: ib_pmask, ib_pdata, ib_ptext, ib_char, then the char's, the icon's
// and the label's boxes), turned into the engine's IconBlk. Its mask and data are
// the program's own 1 bpp images, rows word-padded as the AES's; or, ours, when
// ib_pmask is 0, ib_pdata names one of the ROM's own icons, the desktop's set
// (the asset set's, else TOS 1.0's: iconset.zig): 0 floppy, 1 hard disk, 2 trash,
// 3 folder, 4 program, 5 document. Every address is checked (wire.Mem).
// --------------------------------------------------------------------------
const std = @import("std");
const obj = @import("../engine/obj.zig");
const wire = @import("wire.zig");

pub const Iconblk = extern struct { pmask: u32, pdata: u32, ptext: u32, char: u16, xchar: i16, ychar: i16, xicon: i16, yicon: i16, wicon: i16, hicon: i16, xtext: i16, ytext: i16, wtext: i16, htext: i16 };
pub const SIZE = 34; // the AES's (the extern struct pads to 36)
pub const MAX_ICON = 16;

/// One of the ROM's icons: 1 bpp mask and data, rows of `bpr` bytes.
pub const Art = struct { w: i16, h: i16, bpr: i16, mask: []const u8, data: []const u8 };

/// The engine's icon for the ICONBLK at `addr` into `out`, null when it cannot be read.
pub fn load(m: wire.Mem, addr: u32, sys: []const Art, out: *obj.IconBlk) bool {
    const b = m.slice(addr, SIZE) orelse return false;
    var ib: Iconblk = undefined;
    @memcpy(std.mem.asBytes(&ib)[0..SIZE], b);
    out.* = .{ .mask = &.{}, .data = &.{}, .w = ib.wicon, .h = ib.hicon, .text = m.str(ib.ptext), .ix = ib.xicon, .iy = ib.yicon, .tx = ib.xtext, .ty = ib.ytext, .tw = ib.wtext, .th = ib.htext, .color = ib.char & 0xFF00 };
    if (ib.pmask == 0) {
        if (ib.pdata >= sys.len) return false;
        const a = sys[ib.pdata];
        out.* = .{ .mask = a.mask, .data = a.data, .w = a.w, .h = a.h, .bpr = a.bpr, .text = out.text, .ix = out.ix, .iy = out.iy, .tx = out.tx, .ty = out.ty, .tw = out.tw, .th = out.th, .color = out.color };
        return true;
    }
    if (ib.wicon <= 0 or ib.hicon <= 0 or ib.wicon > 256 or ib.hicon > 256) return false;
    const bpr: usize = (@as(usize, @intCast(ib.wicon)) + 15) / 16 * 2; // word-padded rows
    const n = bpr * @as(usize, @intCast(ib.hicon));
    out.mask = m.slice(ib.pmask, n) orelse return false;
    out.data = m.slice(ib.pdata, n) orelse return false;
    out.bpr = @intCast(bpr);
    return true;
}

const expect = std.testing.expect;

test "a program's own icon, a system icon by number, and a bad one" {
    var mem: [128]u8 align(4) = @splat(0);
    const m: wire.Mem = .{ .base = 0x1000, .bytes = &mem };
    const ib: Iconblk = .{ .pmask = 0x1000 + 64, .pdata = 0x1000 + 80, .ptext = 0x1000 + 100, .char = 0x1000, .xchar = 0, .ychar = 0, .xicon = 4, .yicon = 0, .wicon = 16, .hicon = 4, .xtext = 0, .ytext = 6, .wtext = 24, .htext = 6 };
    @memcpy(mem[0..SIZE], std.mem.asBytes(&ib)[0..SIZE]);
    @memcpy(mem[100..103], "HI\x00");
    var out: obj.IconBlk = undefined;
    try expect(load(m, 0x1000, &.{}, &out));
    try expect(out.bpr == 2 and out.mask.len == 8 and std.mem.eql(u8, out.text, "HI") and out.color == 0x1000);
    var sys_ib = ib;
    sys_ib.pmask = 0;
    sys_ib.pdata = 1;
    @memcpy(mem[0..SIZE], std.mem.asBytes(&sys_ib)[0..SIZE]);
    const arts = [_]Art{ .{ .w = 8, .h = 1, .bpr = 1, .mask = "a", .data = "b" }, .{ .w = 32, .h = 2, .bpr = 4, .mask = "12345678", .data = "abcdefgh" } };
    try expect(load(m, 0x1000, &arts, &out) and out.w == 32 and out.data[0] == 'a');
    sys_ib.pdata = 9; // no such icon
    @memcpy(mem[0..SIZE], std.mem.asBytes(&sys_ib)[0..SIZE]);
    try expect(!load(m, 0x1000, &arts, &out));
    try expect(!load(m, 0x1000 + 120, &arts, &out)); // runs past the window
}
