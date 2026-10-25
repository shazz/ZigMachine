// The test rig the app tests share: a simulated glass, a fake DDR window and a
// shelf directory with a fat disk (a.zmd) and a wasm-only one (b.zmd).
const std = @import("std");
const zx0 = @import("zx0");
const map = @import("map.zig");
const sim = @import("sim.zig");
const zmd = @import("zmd.zig");
const App = @import("app.zig").App;
const bus = @import("bus.zig");
const loader = @import("loader.zig");
const mc = @import("map_cart.zig");

const gpa = std.testing.allocator;
const io = std.testing.io;

pub const Rig = struct {
    glass: sim.Glass = .{},
    words: [4096]u32 = [_]u32{0} ** 4096, // 16 KiB: the image, the shelf disk, its descriptor
    tmp: std.testing.TmpDir,
    dir: []u8,

    pub fn init() !*Rig {
        const r = try gpa.create(Rig);
        r.* = .{ .tmp = std.testing.tmpDir(.{}), .dir = undefined };
        r.dir = try std.fmt.allocPrint(gpa, ".zig-cache/tmp/{s}", .{r.tmp.sub_path});
        const image = try zx0.pack(gpa, "board image bytes", .{});
        defer gpa.free(image);
        const disk = try zmd.testDisk(gpa, "Fat Disk", &.{.{ "CART.RV32", map.ZMD_TYPE_RV32, image }});
        defer gpa.free(disk);
        try r.tmp.dir.writeFile(io, .{ .sub_path = "a.zmd", .data = disk });
        const thin = try zmd.testDisk(gpa, "Wasm Only", &.{});
        defer gpa.free(thin);
        try r.tmp.dir.writeFile(io, .{ .sub_path = "b.zmd", .data = thin });
        return r;
    }

    pub fn deinit(r: *Rig) void {
        r.tmp.cleanup();
        gpa.free(r.dir);
        gpa.destroy(r);
    }

    /// The window against what loading a.zmd writes: the first word that differs, or null.
    pub fn loaded(r: *Rig) !?usize {
        const disk = try r.tmp.dir.readFileAlloc(io, "a.zmd", gpa, .limited(1 << 20));
        defer gpa.free(disk);
        var p = try loader.plan(gpa, disk, r.words.len * 4);
        defer p.deinit(gpa);
        const parts = p.parts();
        return verifyNoKos(&r.words, &parts);
    }

    pub fn app(r: *Rig) !App {
        return App.init(gpa, io, r.glass.regs(), .{ .words = &r.words }, r.dir);
    }
};

/// verifyParts with KOS's words (map_cart.zig: the boot words and the media word after them) left
/// out: a reset writes them after the window is verified, a media change later (app_drive.zig).
pub fn verifyNoKos(words: []u32, parts: []const bus.Part) ?usize {
    const at = (words.len * 4 - mc.KOS_BOOT_FROM_TOP) / 4;
    comptime std.debug.assert(mc.KOS_MEDIA_FROM_TOP == mc.KOS_BOOT_FROM_TOP - 8);
    const keep = [3]u32{ words[at], words[at + 1], words[at + 2] };
    @memset(words[at..][0..3], 0);
    defer @memcpy(words[at..][0..3], &keep);
    return (bus.Ddr{ .words = words }).verifyParts(parts);
}

/// KOS's boot words as a reset left them: the flags, or null when none was written.
pub fn kos(words: []const u32) ?u32 {
    const at = (words.len * 4 - mc.KOS_BOOT_FROM_TOP) / 4;
    return if (words[at] == mc.KOS_BOOT_MAGIC) words[at + 1] else null;
}

pub fn press(a: *App, code: u16) void {
    a.key(code, 1);
    a.key(code, 0);
}
