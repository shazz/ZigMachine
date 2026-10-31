// The OSD after KOS's power-on (app_drive.zig), against the simulated glass: the shelf still pages
// by Page Up/Down, and F11's second line (the frame budget, app_budget.zig) comes up over the
// desktop that the power-on booted with no shelf disk "loaded" (Matt's board run, 26 Oct).
const std = @import("std");
const zx0 = @import("zx0");
const map = @import("map.zig");
const mc = @import("map_cart.zig");
const keymap = @import("keymap.zig");
const drive = @import("app_drive.zig");
const rig = @import("test_rig.zig");

const gpa = std.testing.allocator;
const io = std.testing.io;

fn card() !*rig.Rig {
    const r = try rig.Rig.init();
    const image = try zx0.pack(gpa, "the desktop's board image", .{});
    defer gpa.free(image);
    try r.tmp.dir.createDirPath(io, "kos");
    try r.tmp.dir.writeFile(io, .{ .sub_path = drive.DESKTOP, .data = image });
    const disk = try r.tmp.dir.readFileAlloc(io, "b.zmd", gpa, .limited(1 << 20));
    defer gpa.free(disk);
    for (0..16) |k| { // 18 disks: two pages of 9
        var name: [16]u8 = undefined;
        try r.tmp.dir.writeFile(io, .{ .sub_path = try std.fmt.bufPrint(&name, "d{d:0>2}.zmd", .{k}), .data = disk });
    }
    return r;
}

test "after KOS's power-on the shelf pages by Page Up/Down" {
    const r = try card();
    defer r.deinit();
    var a = try r.app();
    defer a.deinit();
    drive.powerOn(&a);
    try std.testing.expect(a.running and !a.open);
    rig.press(&a, keymap.OSD_HOTKEY);
    rig.press(&a, keymap.KEY_PAGEDOWN);
    try std.testing.expectEqual(@as(usize, 9), a.menu.list.cursor);
    rig.press(&a, keymap.KEY_PAGEDOWN);
    try std.testing.expectEqual(@as(usize, 17), a.menu.list.cursor);
    rig.press(&a, keymap.KEY_PAGEUP);
    try std.testing.expectEqual(@as(usize, 8), a.menu.list.cursor);
}

test "F11 shows the frame budget over the desktop KOS booted" {
    const r = try card();
    defer r.deinit();
    var a = try r.app();
    defer a.deinit();
    drive.powerOn(&a);
    const mb = r.words.len - mc.MB_BYTES / 4; // the firmware's probe, as cycles/bvstat.h writes it
    const vs = mb + mc.VSTAT_AT;
    r.words[mb] = mc.MB_MAGIC;
    r.words[vs + mc.VS_MAGIC] = mc.VSTAT_MAGIC;
    r.words[vs + mc.VS_N] = 16;
    for (mc.VS_FRAME..mc.VS_SWAP + 1) |w| r.words[vs + w] = 100_000;
    for (0..3) |_| a.tick();
    rig.press(&a, keymap.STATS_HOTKEY);
    var got: [5]u8 = undefined;
    for (&got, r.glass.text[map.OSD_COLS..][0..5]) |*c, w| c.* = @truncate(w);
    try std.testing.expectEqualStrings("cart ", &got);
}
