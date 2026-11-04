// A program off the real floppy (app_floppy_prog.zig) against the simulated glass: GEM over the
// floppy asks for PROG.WSM, glass finds it on the floppy image with rom/kos/fat.zig, loads the
// board image named by its wasm's SHA-256 with the floppy beside it (DISK_MAGIC_PROGRAM); with no
// such image the desktop keeps running and says why; quitting goes back to the desktop over it.
const std = @import("std");
const zx0 = @import("zx0");
const map = @import("map.zig");
const mc = @import("map_cart.zig");
const plan = @import("plan.zig");
const keymap = @import("keymap.zig");
const drive = @import("app_drive.zig");
const prog = @import("app_floppy_prog.zig");
const rig = @import("test_rig.zig");
const rv = @import("app_floppy_rv.zig");

const gpa = std.testing.allocator;
const io = std.testing.io;
const WASM = "\x00asm\x01\x00\x00\x00 the program";

/// A 16-sector FAT12 disk: 1 FAT, 16 root entries, PROG.WSM in cluster 2 (data from sector 3) and,
/// given `own` (at most a sector), PROG.RV beside it in cluster 3 (KOS F3b).
fn floppyImage(own: ?[]const u8) [16 * 512]u8 {
    var b = [_]u8{0} ** (16 * 512);
    std.mem.writeInt(u16, b[11..13], 512, .little);
    b[13] = 1;
    std.mem.writeInt(u16, b[14..16], 1, .little);
    b[16] = 1;
    std.mem.writeInt(u16, b[17..19], 16, .little);
    std.mem.writeInt(u16, b[19..21], 16, .little);
    std.mem.writeInt(u16, b[22..24], 1, .little);
    b[512..][0..6].* = .{ 0xF9, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF }; // media, reserved, clusters 2 and 3: the end
    const e = b[1024..][0..32];
    @memcpy(e[0..11], "PROG    WSM");
    e[11] = 0x20;
    std.mem.writeInt(u16, e[26..28], 2, .little);
    std.mem.writeInt(u32, e[28..32], WASM.len, .little);
    @memcpy(b[3 * 512 ..][0..WASM.len], WASM);
    if (own) |c| {
        const r = b[1024 + 32 ..][0..32];
        @memcpy(r[0..11], "PROG    RV ");
        r[11] = 0x20;
        std.mem.writeInt(u16, r[26..28], 3, .little);
        std.mem.writeInt(u32, r[28..32], @intCast(c.len), .little);
        @memcpy(b[4 * 512 ..][0..c.len], c);
    }
    return b;
}

fn card(with_image: bool, own: ?[]const u8) !*rig.Rig {
    const r = try rig.Rig.init();
    const desk = try zx0.pack(gpa, "the desktop's board image", .{});
    defer gpa.free(desk);
    try r.tmp.dir.createDirPath(io, "kos");
    try r.tmp.dir.writeFile(io, .{ .sub_path = drive.DESKTOP, .data = desk });
    try r.tmp.dir.createDirPath(io, "sys/block/sdz");
    try r.tmp.dir.writeFile(io, .{ .sub_path = "sys/block/sdz/removable", .data = "1\n" });
    try r.tmp.dir.writeFile(io, .{ .sub_path = "sys/block/sdz/size", .data = "16\n" });
    try r.tmp.dir.createDirPath(io, "dev");
    try r.tmp.dir.writeFile(io, .{ .sub_path = "dev/sdz", .data = &floppyImage(own) });
    if (!with_image) return r;
    const board = try zx0.pack(gpa, "the program's board image", .{});
    defer gpa.free(board);
    const path = try prog.imagePath(gpa, ".", WASM);
    defer gpa.free(path);
    try r.tmp.dir.createDirPath(io, prog.BY_HASH);
    try r.tmp.dir.writeFile(io, .{ .sub_path = path, .data = board });
    return r;
}

/// The firmware's side of request 3 for `name` (cycles/bdiskapp.c): the block, then CART_STATE.
fn ask(r: *rig.Rig, name: []const u8) void {
    const at = (r.words.len * 4 - mc.CART_REQ_FROM_TOP) / 4;
    var bytes = [_]u8{0} ** mc.CART_REQ_NAME_MAX;
    @memcpy(bytes[0..name.len], name);
    for (0..mc.CART_REQ_NAME_MAX / 4) |i| r.words[at + 4 + i] = std.mem.readInt(u32, bytes[i * 4 ..][0..4], .little);
    const n: u32 = @intCast(name.len);
    r.words[at..][0..4].* = .{ mc.CART_REQ_MAGIC, 3, n, ~(mc.CART_REQ_MAGIC ^ 3 ^ n) };
    r.glass.request = 3;
}

fn floppyDesktop(r: *rig.Rig) !@import("app.zig").App {
    var a = try r.app();
    a.sys_root = r.dir;
    a.dev_dir = try std.fmt.allocPrint(gpa, "{s}/dev", .{r.dir});
    drive.powerOn(&a);
    rig.press(&a, keymap.OSD_HOTKEY);
    rig.press(&a, 32); // D: the floppy in drive A
    rig.press(&a, 19); // R: the desktop over it
    try std.testing.expect(a.floppy_a and a.running);
    return a;
}

test "a program off the real floppy loads the board image its wasm's hash names, the floppy beside it" {
    const r = try card(true, null);
    defer r.deinit();
    var a = try floppyDesktop(r);
    defer gpa.free(a.dev_dir);
    defer a.deinit();
    ask(r, "PROG.WSM");
    a.tick();
    const board = try zx0.pack(gpa, "the program's board image", .{});
    defer gpa.free(board);
    var p = try plan.planOver(gpa, board, &floppyImage(null), r.words.len * 4, mc.DISK_MAGIC_PROGRAM, null);
    defer p.deinit(gpa);
    const parts = p.parts();
    try std.testing.expectEqual(@as(?usize, null), rig.verifyNoKos(&r.words, &parts));
    try std.testing.expectEqualStrings("PROG.WSM running", a.menu.status.?);
}

test "no board image for the program: the desktop keeps running and says so" {
    const r = try card(false, null);
    defer r.deinit();
    var a = try floppyDesktop(r);
    defer gpa.free(a.dev_dir);
    defer a.deinit();
    const resets = r.glass.resets;
    ask(r, "PROG.WSM");
    a.tick();
    try std.testing.expect(std.mem.indexOf(u8, a.menu.status.?, "PROG.WSM: NoBoardImage") != null);
    try std.testing.expectEqual(resets, r.glass.resets);
    _ = map;
}

/// The floppy's own NAME.RV (KOS F3b), saying it was built from `wasm`.
fn ownImage(wasm: []const u8) ![]u8 {
    const board = try zx0.pack(gpa, "the board image on the floppy", .{});
    defer gpa.free(board);
    return rv.wrap(gpa, wasm, board);
}

test "a program's own PROG.RV on the floppy loads with no SD image at all, and wins over the card's" {
    for ([_]bool{ false, true }) |on_card| {
        const own = try ownImage(WASM);
        defer gpa.free(own);
        const r = try card(on_card, own);
        defer r.deinit();
        var a = try floppyDesktop(r);
        defer gpa.free(a.dev_dir);
        defer a.deinit();
        ask(r, "PROG.WSM");
        a.tick();
        try std.testing.expectEqualStrings("PROG.WSM running", a.menu.status.?);
        var p = try plan.planOver(gpa, own[rv.HEAD..], &floppyImage(own), r.words.len * 4, mc.DISK_MAGIC_PROGRAM, null);
        defer p.deinit(gpa);
        const parts = p.parts();
        try std.testing.expectEqual(@as(?usize, null), rig.verifyNoKos(&r.words, &parts));
    }
}

test "a PROG.RV built from another program is refused, even with the right image on the card" {
    const own = try ownImage("\x00asm\x01\x00\x00\x00 another build");
    defer gpa.free(own);
    const r = try card(true, own);
    defer r.deinit();
    var a = try floppyDesktop(r);
    defer gpa.free(a.dev_dir);
    defer a.deinit();
    const resets = r.glass.resets;
    ask(r, "PROG.WSM");
    a.tick();
    try std.testing.expect(std.mem.indexOf(u8, a.menu.status.?, "PROG.WSM: RvForAnotherProgram") != null);
    try std.testing.expectEqual(resets, r.glass.resets);
}
