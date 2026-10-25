// Drive A's media change while a cart runs (app_drive.zig I / E; docs/ZIGTOS_BOOT.md 4.1): the
// running cart is not reset. In the window, after the running image (Plan.disk_from, a lean
// cart's .bss), the glass:
//
//   1. zeroes the disk descriptor, so a firmware that looks now finds no disk;
//   2. writes the disk the browser would mount (a fat disk with zmd_fat undone), or nothing;
//   3. writes the descriptor (DISK_MAGIC) for it;
//   4. bumps the media word (map_cart.zig KOS_MEDIA_*).
//
// The firmware (cycles/bdiskapp.c bdiskapp_media) sees the new count at its next frame and
// tells the cart (insertDisk) and KOS (kosMediaChange). The cart may be reading the old disk
// while it changes: as on an ST, a disk pulled mid-read gives that read garbage.
const std = @import("std");
const map = @import("map.zig");
const mc = @import("map_cart.zig");
const zmd = @import("zmd.zig");
const plan = @import("plan.zig");
const App = @import("app.zig").App;
const drive = @import("app_drive.zig");

pub fn change(app: *App) !void {
    const words = app.ddr.words;
    const desc = (app.ddr.bytes() - map.DISK_DESC_FROM_TOP) / 4;
    @memset(words[desc..][0..map.DISK_DESC_WORDS], 0);
    if (app.drive) |i| try place(app, i, desc);
    const media = (app.ddr.bytes() - mc.KOS_MEDIA_FROM_TOP) / 4;
    words[media] = mc.KOS_MEDIA_TAG | ((words[media] +% 1) & mc.KOS_MEDIA_COUNT);
}

/// Steps 2 and 3 for disk `i`: its shelf disk, then the descriptor that names it.
fn place(app: *App, i: usize, desc: usize) !void {
    const file = try drive.readDisk(app, i);
    defer app.gpa.free(file);
    const d = try zmd.parse(file);
    const disk = if (d.boardImage()) |_| try d.shelfDisk(app.gpa) else |_| try app.gpa.dupe(u8, file);
    defer app.gpa.free(disk);
    const at = try plan.diskAt(app.disk_from, disk.len, app.ddr.bytes());
    for (0..(disk.len + 3) / 4) |k| { // a word at a time, as the loader writes the window
        var w = [_]u8{0} ** 4;
        const part = disk[k * 4 .. @min(disk.len, k * 4 + 4)];
        @memcpy(w[0..part.len], part);
        app.ddr.words[at / 4 + k] = std.mem.readInt(u32, &w, .little);
    }
    const n: u32 = @intCast(disk.len);
    const w = [map.DISK_DESC_WORDS]u32{ map.DISK_MAGIC, at, n, ~(map.DISK_MAGIC ^ at ^ n) };
    for (w, 0..) |x, k| app.ddr.words[desc + k] = x;
}
