// KOS's drive A against the simulated glass (app_drive.zig, app_media.zig): power-on with the OSD
// closed over what glass.cfg's drive_a= holds, the desktop over a data disk or an empty drive,
// the POST's flags, insert + reset, a media change while a cart runs, and every way it fails.
const std = @import("std");
const zx0 = @import("zx0");
const map = @import("map.zig");
const mc = @import("map_cart.zig");
const zmd = @import("zmd.zig");
const plan = @import("plan.zig");
const config = @import("config.zig");
const keymap = @import("keymap.zig");
const drive = @import("app_drive.zig");
const rig = @import("test_rig.zig");
const App = @import("app.zig").App;

const gpa = std.testing.allocator;
const io = std.testing.io;
const POST = mc.KOS_POST_FRAMES << mc.KOS_POST_SHIFT;
const KEY_I = 23; // evdev
const KEY_E = 18;

/// test_rig's card (a.zmd bootable fat disk, b.zmd a data disk) plus KOS's desktop image.
fn card(desktop: bool) !*rig.Rig {
    const r = try rig.Rig.init();
    if (!desktop) return r;
    const image = try zx0.pack(gpa, "the desktop's board image", .{});
    defer gpa.free(image);
    try r.tmp.dir.createDirPath(io, "kos");
    try r.tmp.dir.writeFile(io, .{ .sub_path = drive.DESKTOP, .data = image });
    return r;
}

fn powered(r: *rig.Rig, cfg: []const u8) !App {
    if (cfg.len > 0) try r.tmp.dir.writeFile(io, .{ .sub_path = config.FILE, .data = cfg });
    var a = try r.app();
    drive.powerOn(&a);
    return a;
}

/// The window against the desktop's plan over shelf file `disk` (null: an empty drive).
fn holdsDesktop(r: *rig.Rig, disk: ?[]const u8) !?usize {
    const desk = try r.tmp.dir.readFileAlloc(io, drive.DESKTOP, gpa, .limited(1 << 20));
    defer gpa.free(desk);
    const bytes = if (disk) |f| try r.tmp.dir.readFileAlloc(io, f, gpa, .limited(1 << 20)) else null;
    defer if (bytes) |b| gpa.free(b);
    var p = try plan.planDesktop(gpa, desk, bytes, r.words.len * 4, null);
    defer p.deinit(gpa);
    const parts = p.parts();
    return rig.verifyNoKos(&r.words, &parts);
}

fn has(a: *const App, part: []const u8) bool {
    return std.mem.indexOf(u8, a.menu.status orelse "", part) != null;
}

test "power-on with an empty drive runs the desktop at once, the OSD closed, with the POST" {
    const r = try card(true);
    defer r.deinit();
    var a = try powered(r, "");
    defer a.deinit();
    try std.testing.expect(a.running and !a.open and r.glass.ctrl & map.CTRL_RUN != 0);
    try std.testing.expectEqual(@as(?usize, null), try holdsDesktop(r, null)); // no disk, no descriptor
    try std.testing.expectEqual(@as(?u32, POST), rig.kos(&r.words));
    try std.testing.expectEqual(@as(?usize, null), a.current);
}

test "drive_a= boots its disk: a bootable one its cart, a data disk the desktop over it" {
    const r = try card(true);
    defer r.deinit();
    {
        var a = try powered(r, "drive_a=a.zmd\n");
        defer a.deinit();
        try std.testing.expectEqual(@as(?usize, null), try r.loaded());
        try std.testing.expectEqual(@as(?usize, 0), a.drive);
    }
    var a = try powered(r, "drive_a=b.zmd\npost=0\n");
    defer a.deinit();
    try std.testing.expectEqual(@as(?usize, null), try holdsDesktop(r, "b.zmd"));
    try std.testing.expectEqual(@as(?u32, 0), rig.kos(&r.words)); // post=0: a cold reset, no POST
}

test "Enter inserts and resets, Shift skips the POST, and drive_a is saved" {
    const r = try card(true);
    defer r.deinit();
    {
        var a = try powered(r, "");
        defer a.deinit();
        rig.press(&a, keymap.OSD_HOTKEY);
        a.key(keymap.KEY_LEFTSHIFT, 1);
        rig.press(&a, keymap.KEY_ENTER); // a.zmd, the first on the shelf
        a.key(keymap.KEY_LEFTSHIFT, 0);
        try std.testing.expectEqual(@as(?u32, 0), rig.kos(&r.words));
        try std.testing.expectEqual(@as(?usize, null), try r.loaded());
        try std.testing.expect(!a.open); // closing the OSD saves glass.cfg
    }
    try std.testing.expectEqualStrings("a.zmd", config.load(io, r.dir).settings.drive_a.slice());
}

test "insert and eject while a cart runs: a media change, no reset" {
    const r = try card(true);
    defer r.deinit();
    var a = try powered(r, "");
    defer a.deinit();
    const resets = r.glass.resets;
    const media = (r.words.len * 4 - mc.KOS_MEDIA_FROM_TOP) / 4;
    const desc = (r.words.len * 4 - map.DISK_DESC_FROM_TOP) / 4;
    rig.press(&a, keymap.OSD_HOTKEY);
    rig.press(&a, keymap.KEY_DOWN);
    rig.press(&a, KEY_I); // b.zmd, a data disk: the desktop's disk now
    try std.testing.expectEqual(resets, r.glass.resets);
    try std.testing.expectEqual(mc.KOS_MEDIA_TAG | 1, r.words[media]);
    try std.testing.expectEqual(map.DISK_MAGIC, r.words[desc]);
    try std.testing.expectEqual(@as(?usize, null), try holdsDesktop(r, "b.zmd")); // as a reset would place it
    try std.testing.expect(has(&a, "media change"));
    rig.press(&a, KEY_E);
    try std.testing.expectEqual(mc.KOS_MEDIA_TAG | 2, r.words[media]);
    try std.testing.expectEqual(@as(u32, 0), r.words[desc]);
    try std.testing.expectEqual(@as(?usize, null), a.drive);
}

test "what fails says why: no desktop, a missing drive_a, a bootable disk the board cannot run" {
    const r = try card(false);
    defer r.deinit();
    {
        var a = try powered(r, "");
        defer a.deinit();
        try std.testing.expect(has(&a, "no kos/desktop.rv32 on the card") and a.open and !a.running);
    }
    {
        var a = try powered(r, "drive_a=gone.zmd\n");
        defer a.deinit();
        try std.testing.expect(has(&a, "drive A: no gone.zmd on the card") and a.drive == null);
    }
    const disk = try r.tmp.dir.readFileAlloc(io, "b.zmd", gpa, .limited(1 << 20));
    defer gpa.free(disk);
    std.mem.writeInt(u16, disk[0x1FE..0x200], 0, .big);
    std.mem.writeInt(u16, disk[0x1FE..0x200], 0x1234 -% zmd.beSum(disk[0..512]), .big); // now sums to $1234
    try std.testing.expect((try zmd.parse(disk)).bootable());
    try r.tmp.dir.writeFile(io, .{ .sub_path = "b.zmd", .data = disk });
    var a = try powered(r, "drive_a=b.zmd\n");
    defer a.deinit();
    try std.testing.expect(has(&a, "b.zmd: NoBoardImage") and !a.running);
}

test "W writes the warm flag over the running cart's memory" {
    const r = try card(true);
    defer r.deinit();
    var a = try powered(r, "drive_a=a.zmd\n");
    defer a.deinit();
    r.words[100] = 0xC0FFEE; // the cart's memory
    rig.press(&a, keymap.OSD_HOTKEY);
    rig.press(&a, 17); // W
    try std.testing.expectEqual(@as(u32, 0xC0FFEE), r.words[100]);
    try std.testing.expectEqual(@as(?u32, mc.KOS_WARM | POST), rig.kos(&r.words));
    try std.testing.expect(a.running and !a.open);
}

test "a disk that does not fit after the running image changes nothing" {
    const r = try card(true);
    defer r.deinit();
    const raw = try gpa.alloc(u8, 20_000); // past the 16 KiB test window
    defer gpa.free(raw);
    @memset(raw, 1);
    const huge = try zmd.testDisk(gpa, "huge", &.{.{ "BIG.RAW", map.ZMD_TYPE_RAW, raw }});
    defer gpa.free(huge);
    try r.tmp.dir.writeFile(io, .{ .sub_path = "c.zmd", .data = huge });
    var a = try powered(r, "drive_a=b.zmd\n");
    defer a.deinit();
    const before = r.words;
    rig.press(&a, keymap.OSD_HOTKEY);
    rig.press(&a, keymap.KEY_DOWN);
    rig.press(&a, KEY_I); // c.zmd ("huge": the shelf is in title order)
    try std.testing.expect(has(&a, "drive A: DiskTooBig"));
    try std.testing.expectEqualStrings("b.zmd", a.disks.disks[a.drive.?].file); // still in
    try std.testing.expectEqualSlices(u32, &before, &r.words); // nothing written, no media count
}

test "a media change under a program goes after the program's image, not the desktop's" {
    const r = try card(true);
    defer r.deinit();
    const big = try gpa.alloc(u8, 9000); // the program's image: past the desktop's first 4 KiB
    defer gpa.free(big);
    @memset(big, 0x5A);
    const packed_big = try zx0.pack(gpa, big, .{});
    defer gpa.free(packed_big);
    const files = .{ .{ "BOOT.WSM", map.ZMD_TYPE_WASM, "\x00asm" }, .{ "CART.RV32", map.ZMD_TYPE_RV32, packed_big } };
    const prog = try zmd.testDisk(gpa, "data disk", &files);
    defer gpa.free(prog);
    try r.tmp.dir.createDirPath(io, "progs/b");
    try r.tmp.dir.writeFile(io, .{ .sub_path = "progs/b/BOOT.WSM.zmd", .data = prog });
    var a = try powered(r, "drive_a=b.zmd\n"); // the desktop over b.zmd
    defer a.deinit();
    try @import("app_request.zig").runProgram(&a, 1, "BOOT.WSM");
    try std.testing.expectEqual(@as(u32, 12288), a.disk_from); // 9000 bytes, 4 KiB-aligned
    rig.press(&a, keymap.OSD_HOTKEY);
    rig.press(&a, keymap.KEY_DOWN);
    rig.press(&a, KEY_I);
    const desc = (r.words.len * 4 - map.DISK_DESC_FROM_TOP) / 4;
    try std.testing.expectEqual(map.DISK_MAGIC, r.words[desc]);
    try std.testing.expectEqual(a.disk_from, r.words[desc + 1]);
}
