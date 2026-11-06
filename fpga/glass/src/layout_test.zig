// The SD card's two layouts (layout.zig): which one a card has, and that every SD path glass reads
// follows it: the shelf from CARTS/, glass.cfg, KOS's desktop and the programs from KESTREL/; the old
// card's zigmachine/ holds all of them.
const std = @import("std");
const zx0 = @import("zx0");
const sim = @import("sim.zig");
const zmd = @import("zmd.zig");
const layout = @import("layout.zig");
const config = @import("config.zig");
const drive = @import("app_drive.zig");
const request = @import("app_request.zig");
const prog = @import("app_floppy_prog.zig");
const App = @import("app.zig").App;

const gpa = std.testing.allocator;
const io = std.testing.io;

const Card = struct {
    tmp: std.testing.TmpDir,
    root: []u8,
    glass: sim.Glass = .{},
    words: [4096]u32 = [_]u32{0} ** 4096,

    fn init() !*Card {
        const c = try gpa.create(Card);
        c.* = .{ .tmp = std.testing.tmpDir(.{}), .root = undefined };
        c.root = try std.fmt.allocPrint(gpa, ".zig-cache/tmp/{s}", .{c.tmp.sub_path});
        return c;
    }
    fn deinit(c: *Card) void {
        c.tmp.cleanup();
        gpa.free(c.root);
        gpa.destroy(c);
    }
    /// A wasm-only disk titled `title` at `sub`.
    fn put(c: *Card, sub: []const u8, title: []const u8) !void {
        if (std.fs.path.dirname(sub)) |d| try c.tmp.dir.createDirPath(io, d);
        const disk = try zmd.testDisk(gpa, title, &.{});
        defer gpa.free(disk);
        try c.tmp.dir.writeFile(io, .{ .sub_path = sub, .data = disk });
    }
    /// `dir`/glass.cfg saying volume=`vol`.
    fn cfg(c: *Card, dir: []const u8, vol: u8) !void {
        try c.tmp.dir.createDirPath(io, dir);
        var b: [256]u8 = undefined;
        const p = try std.fmt.bufPrint(&b, "{s}/{s}", .{ dir, config.FILE });
        var t: [256]u8 = undefined;
        try c.tmp.dir.writeFile(io, .{ .sub_path = p, .data = config.format(.{ .volume = vol }, &t) });
    }
    fn app(c: *Card, dirs: layout.Dirs) !App {
        return App.init(gpa, io, c.glass.regs(), .{ .words = &c.words }, dirs);
    }
};

fn expectUnder(root: []const u8, sub: []const u8, got: []const u8) !void {
    var b: [512]u8 = undefined;
    try std.testing.expectEqualStrings(try std.fmt.bufPrint(&b, "{s}/{s}", .{ root, sub }), got);
}

test "a KESTREL card: the shelf is CARTS/, the settings and system files KESTREL/" {
    const c = try Card.init();
    defer c.deinit();
    try c.put("CARTS/demos/demo-a.zmd", "In Carts");
    try c.put("KESTREL/demos/demo-k.zmd", "In Kestrel"); // never on the shelf
    try c.put("zigmachine/demos/demo-z.zmd", "Old Copy"); // a half-migrated card: KESTREL wins
    try c.cfg("KESTREL", 17);
    try c.cfg("CARTS", 99);
    const dirs = try layout.detect(gpa, io, c.root);
    defer dirs.deinit(gpa);
    try std.testing.expectEqual(layout.Kind.kestrel, dirs.kind);
    try expectUnder(c.root, "KESTREL", dirs.sys);
    try expectUnder(c.root, "CARTS", dirs.carts);
    var a = try c.app(dirs);
    defer a.deinit();
    try std.testing.expectEqual(@as(usize, 1), a.disks.disks.len);
    try std.testing.expectEqualStrings("demo-a.zmd", a.disks.disks[0].file);
    try std.testing.expectEqual(@as(u8, 17), a.menu.settings.volume); // KESTREL/glass.cfg
    const p = try request.programPath(gpa, a.sys_dir, "demo-st_replay.zmd", "BOOT.WSM");
    defer gpa.free(p);
    try expectUnder(c.root, "KESTREL/progs/demo-st_replay/BOOT.WSM.zmd", p);
    const h = try prog.imagePath(gpa, a.sys_dir, "wasm");
    defer gpa.free(h);
    try std.testing.expect(std.mem.startsWith(u8, h[c.root.len..], "/KESTREL/progs/by-hash/"));
}

test "a KESTREL card's settings save to KESTREL/glass.cfg; KOS's desktop is read from KESTREL/kos" {
    const c = try Card.init();
    defer c.deinit();
    try c.put("CARTS/demos/demo-a.zmd", "In Carts");
    try c.tmp.dir.createDirPath(io, "KESTREL");
    const dirs = try layout.detect(gpa, io, c.root);
    defer dirs.deinit(gpa);
    var a = try c.app(dirs);
    defer a.deinit();
    try std.testing.expectError(error.NoDesktop, drive.planBoot(&a, null, a.opt)); // none in KESTREL/kos yet
    const image = try zx0.pack(gpa, "the desktop's board image", .{});
    defer gpa.free(image);
    try c.tmp.dir.createDirPath(io, "CARTS/kos");
    try c.tmp.dir.writeFile(io, .{ .sub_path = "CARTS/" ++ drive.DESKTOP, .data = image }); // the wrong place
    try std.testing.expectError(error.NoDesktop, drive.planBoot(&a, null, a.opt));
    a.menu.settings.volume = 42;
    a.settings_dirty = true;
    a.setOpen(false); // saves
    var b: [256]u8 = undefined;
    const got = try c.tmp.dir.readFile(io, "KESTREL/" ++ config.FILE, &b);
    try std.testing.expect(std.mem.indexOf(u8, got, "volume=42") != null);
    try std.testing.expectError(error.FileNotFound, c.tmp.dir.readFile(io, "CARTS/" ++ config.FILE, &b));
}

test "an old card: zigmachine/ holds the shelf and the system files" {
    const c = try Card.init();
    defer c.deinit();
    try c.put("zigmachine/demos/demo-z.zmd", "Old Card");
    try c.put("CARTS/demos/demo-a.zmd", "No Kestrel"); // CARTS alone does not make a KESTREL card
    try c.cfg("zigmachine", 23);
    const dirs = try layout.detect(gpa, io, c.root);
    defer dirs.deinit(gpa);
    try std.testing.expectEqual(layout.Kind.old, dirs.kind);
    try expectUnder(c.root, "zigmachine", dirs.sys);
    try std.testing.expectEqualStrings(dirs.sys, dirs.carts);
    var a = try c.app(dirs);
    defer a.deinit();
    try std.testing.expectEqual(@as(usize, 1), a.disks.disks.len);
    try std.testing.expectEqualStrings("demo-z.zmd", a.disks.disks[0].file);
    try std.testing.expectEqual(@as(u8, 23), a.menu.settings.volume);
}

test "neither: the directory given is the shelf itself (the old `glass run /mnt/sd/zigmachine`)" {
    const c = try Card.init();
    defer c.deinit();
    try c.put("demos/demo-f.zmd", "Flat");
    const dirs = try layout.detect(gpa, io, c.root);
    defer dirs.deinit(gpa);
    try std.testing.expectEqual(layout.Kind.flat, dirs.kind);
    try std.testing.expectEqualStrings(c.root, dirs.sys);
    try std.testing.expectEqualStrings(c.root, dirs.carts);
    var a = try c.app(dirs);
    defer a.deinit();
    try std.testing.expectEqualStrings("demo-f.zmd", a.disks.disks[0].file);
}
