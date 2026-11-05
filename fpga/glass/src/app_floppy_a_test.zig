// The real floppy in KOS's drive A (app_floppy_a.zig) against the simulated glass: D reads the USB
// floppy raw (a fake /sys/block and /dev in a temp directory) and puts it in drive A under the
// running desktop as a media change; a reset boots the desktop over it; no floppy, or one that is no
// FAT disk, says why and leaves drive A as it was.
const std = @import("std");
const zx0 = @import("zx0");
const map = @import("map.zig");
const plan = @import("plan.zig");
const keymap = @import("keymap.zig");
const drive = @import("app_drive.zig");
const floppy_a = @import("app_floppy_a.zig");
const rig = @import("test_rig.zig");

const gpa = std.testing.allocator;
const io = std.testing.io;
const KEY_D = 32; // evdev
const KEY_R = 19;

/// test_rig's card, KOS's desktop, and a tiny "floppy" at <dir>/dev/sdz (removable, 8 sectors).
fn card(fat: bool) !*rig.Rig {
    const r = try rig.Rig.init();
    const desk = try zx0.pack(gpa, "the desktop's board image", .{});
    defer gpa.free(desk);
    try r.tmp.dir.createDirPath(io, "kos");
    try r.tmp.dir.writeFile(io, .{ .sub_path = drive.DESKTOP, .data = desk });
    try r.tmp.dir.createDirPath(io, "sys/block/sdz");
    try r.tmp.dir.writeFile(io, .{ .sub_path = "sys/block/sdz/removable", .data = "1\n" });
    try r.tmp.dir.writeFile(io, .{ .sub_path = "sys/block/sdz/size", .data = "8\n" });
    try r.tmp.dir.createDirPath(io, "dev");
    const img = try gpa.alloc(u8, 8 * 512); // 8 sectors: the test window is 16 KiB
    defer gpa.free(img);
    @memset(img, 0);
    if (fat) std.mem.writeInt(u16, img[11..13], 512, .little); // a BPB's bytes a sector: the rest is the desktop's to read
    try r.tmp.dir.writeFile(io, .{ .sub_path = "dev/sdz", .data = img });
    return r;
}

fn powered(r: *rig.Rig) !@import("app.zig").App {
    var a = try r.app();
    a.sys_root = r.dir;
    a.dev_dir = try std.fmt.allocPrint(gpa, "{s}/dev", .{r.dir});
    drive.powerOn(&a);
    return a;
}

/// The window's disk descriptor names a disk of `bytes` bytes.
fn diskBytes(r: *rig.Rig) u32 {
    const desc = (r.words.len * 4 - map.DISK_DESC_FROM_TOP) / 4;
    // DISK_MAGIC_FLOPPY: the real floppy, drive A's FLOPPY label (KOS F4)
    return if (r.words[desc] == @import("map_cart.zig").DISK_MAGIC_FLOPPY) r.words[desc + 2] else 0;
}

test "D puts the raw floppy in drive A under the running desktop, and a reset boots over it" {
    const r = try card(true);
    defer r.deinit();
    var a = try powered(r);
    defer gpa.free(a.dev_dir);
    defer a.deinit();
    try std.testing.expectEqual(@as(u32, 0), diskBytes(r)); // an empty drive
    rig.press(&a, keymap.OSD_HOTKEY);
    const resets = r.glass.resets;
    rig.press(&a, KEY_D);
    try std.testing.expect(a.floppy_a and a.drive == null);
    try std.testing.expectEqual(resets, r.glass.resets); // a media change, no reset
    try std.testing.expectEqual(@as(u32, 8 * 512), diskBytes(r));
    rig.press(&a, KEY_R);
    try std.testing.expectEqual(@as(u32, 8 * 512), diskBytes(r)); // the desktop over the floppy
    try std.testing.expect(std.mem.indexOf(u8, a.menu.status.?, "the floppy running") != null);
}

test "no floppy, or a floppy that is no FAT disk, leaves drive A as it was" {
    const r = try card(false);
    defer r.deinit();
    var a = try powered(r);
    defer gpa.free(a.dev_dir);
    defer a.deinit();
    rig.press(&a, keymap.OSD_HOTKEY);
    rig.press(&a, KEY_D);
    try std.testing.expect(std.mem.indexOf(u8, a.menu.status.?, "floppy: NotFat") != null and !a.floppy_a);
    try r.tmp.dir.deleteTree(io, "sys/block/sdz");
    rig.press(&a, KEY_D);
    try std.testing.expect(std.mem.indexOf(u8, a.menu.status.?, "floppy: NoFloppy") != null and !a.floppy_a);
    _ = plan;
}

/// An 8-sector FAT12 disk (1 reserved, 1 FAT, a 16-entry root, 5 clusters) whose root holds `name`.
fn fat12(name: *const [11]u8) [8 * 512]u8 {
    var img = [_]u8{0} ** (8 * 512);
    std.mem.writeInt(u16, img[11..13], 512, .little);
    img[13] = 1; // sectors a cluster
    std.mem.writeInt(u16, img[14..16], 1, .little); // reserved
    img[16] = 1; // FATs
    std.mem.writeInt(u16, img[17..19], 16, .little); // root entries
    std.mem.writeInt(u16, img[19..21], 8, .little); // sectors
    std.mem.writeInt(u16, img[22..24], 1, .little); // sectors a FAT
    @memcpy(img[2 * 512 ..][0..11], name); // the root's first entry, an empty file
    img[2 * 512 + 11] = 0x20;
    return img;
}

test "a cart floppy (.zmd in its root) is counted; any other FAT disk is not" {
    try std.testing.expectEqual(@as(usize, 1), floppy_a.carts(&fat12("DEMO-A~1ZMD")));
    try std.testing.expectEqual(@as(usize, 0), floppy_a.carts(&fat12("README  TXT")));
    try std.testing.expectEqual(@as(usize, 0), floppy_a.carts(&([_]u8{0} ** 4096)));
}

test "D on a cart floppy says F lists its carts" {
    const r = try card(true);
    defer r.deinit();
    const img = fat12("DEMO-A~1ZMD");
    try r.tmp.dir.writeFile(io, .{ .sub_path = "dev/sdz", .data = &img });
    var a = try powered(r);
    defer gpa.free(a.dev_dir);
    defer a.deinit();
    rig.press(&a, keymap.OSD_HOTKEY);
    rig.press(&a, KEY_D);
    try std.testing.expect(a.floppy_a);
    try std.testing.expect(std.mem.indexOf(u8, a.menu.status.?, "A: 1 .zmd carts, F lists them") != null);
}
