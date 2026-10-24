// A cart's request for a cart swap (app_request.zig) against the simulated glass: GEM over
// a data disk runs BOOT.WSM off it (its prebuilt fat disk under progs/, the same disk back
// in DDR with the program's descriptor magic), the program goes back to GEM, and every way
// a request can be wrong leaves the cart running with the reason on the status line.
const std = @import("std");
const zx0 = @import("zx0");
const map = @import("map.zig");
const mc = @import("map_cart.zig");
const bus = @import("bus.zig");
const sim = @import("sim.zig");
const zmd = @import("zmd.zig");
const loader = @import("loader.zig");
const request = @import("app_request.zig");
const keymap = @import("keymap.zig");
const App = @import("app.zig").App;
const press = @import("test_rig.zig").press;

const gpa = std.testing.allocator;
const io = std.testing.io;
const WORDS = 4096;

const Rig = struct {
    glass: sim.Glass = .{},
    words: [WORDS]u32 = [_]u32{0} ** WORDS,
    tmp: std.testing.TmpDir,
    dir: []u8,

    fn init() !*Rig {
        const r = try gpa.create(Rig);
        r.* = .{ .tmp = std.testing.tmpDir(.{}), .dir = undefined };
        r.dir = try std.fmt.allocPrint(gpa, ".zig-cache/tmp/{s}", .{r.tmp.sub_path});
        try r.fat("demo-dd.zmd", "gem image");
        try r.tmp.dir.createDirPath(io, "progs/demo-dd");
        try r.fat("progs/demo-dd/BOOT.WSM.zmd", "the program's image");
        return r;
    }

    /// A data disk (BOOT.WSM, SAMPLE.RAW) + a board image: what tools/glass_shelf.py stages.
    fn fat(r: *Rig, path: []const u8, image: []const u8) !void {
        const packed_image = try zx0.pack(gpa, image, .{});
        defer gpa.free(packed_image);
        const files = .{ .{ "BOOT.WSM", map.ZMD_TYPE_WASM, "\x00asm" }, .{ "SAMPLE.RAW", map.ZMD_TYPE_RAW, "pcm" }, .{ "CART.RV32", map.ZMD_TYPE_RV32, packed_image } };
        const disk = try zmd.testDisk(gpa, "data disk", &files);
        defer gpa.free(disk);
        try r.tmp.dir.writeFile(io, .{ .sub_path = path, .data = disk });
    }

    fn deinit(r: *Rig) void {
        r.tmp.cleanup();
        gpa.free(r.dir);
        gpa.destroy(r);
    }

    fn ddr(r: *Rig) bus.Ddr {
        return .{ .words = &r.words };
    }

    /// The firmware's side (cycles/bdiskapp.c): the block, then CART_STATE.
    fn ask(r: *Rig, req: u32, name: []const u8) void {
        const at = (WORDS * 4 - mc.CART_REQ_FROM_TOP) / 4;
        var bytes = [_]u8{0} ** mc.CART_REQ_NAME_MAX;
        @memcpy(bytes[0..name.len], name);
        for (0..mc.CART_REQ_NAME_MAX / 4) |i| r.words[at + 4 + i] = std.mem.readInt(u32, bytes[i * 4 ..][0..4], .little);
        const n: u32 = @intCast(name.len);
        r.words[at..][0..4].* = .{ mc.CART_REQ_MAGIC, req, n, ~(mc.CART_REQ_MAGIC ^ req ^ n) };
        r.glass.request = req;
    }

    /// The window against loading `path` with `magic`: the first word that differs, or null.
    fn holds(r: *Rig, path: []const u8, magic: u32) !?usize {
        const disk = try r.tmp.dir.readFileAlloc(io, path, gpa, .limited(1 << 20));
        defer gpa.free(disk);
        var p = try loader.planAs(gpa, disk, WORDS * 4, magic);
        defer p.deinit(gpa);
        const parts = p.parts();
        return r.ddr().verifyParts(&parts);
    }
};

fn started(r: *Rig) !App {
    var a = try App.init(gpa, io, r.glass.regs(), r.ddr(), r.dir);
    press(&a, keymap.KEY_ENTER); // GEM over the data disk
    try std.testing.expectEqual(@as(?usize, 0), a.current);
    return a;
}

fn status(a: *const App) []const u8 {
    return a.menu.status orelse "";
}

test "GEM runs BOOT.WSM off the disk, and the program goes back to GEM over it" {
    const r = try Rig.init();
    defer r.deinit();
    var a = try started(r);
    defer a.deinit();
    r.ask(mc.REQ_RUN_PROGRAM, "BOOT.WSM");
    a.tick();
    try std.testing.expectEqual(@as(?usize, null), try r.holds("progs/demo-dd/BOOT.WSM.zmd", mc.DISK_MAGIC_PROGRAM));
    try std.testing.expectEqualStrings("BOOT.WSM running", status(&a));
    try std.testing.expect(r.glass.ctrl & map.CTRL_RUN != 0 and a.current.? == 0);
    a.tick(); // the program runs: no request
    r.ask(mc.REQ_BACK_TO_OS, "");
    a.tick();
    try std.testing.expectEqual(@as(?usize, null), try r.holds("demo-dd.zmd", map.DISK_MAGIC));
    try std.testing.expect(r.glass.ctrl & map.CTRL_RUN != 0);
}

test "the F11 overlay stays see-through over the program and back over GEM" {
    // The loader once kept CTRL_OSD but dropped CTRL_OSD_STATS, and nothing after a
    // program load put it back: an opaque window sat in the corner over the program.
    const r = try Rig.init();
    defer r.deinit();
    var a = try started(r);
    defer a.deinit();
    const overlay = map.CTRL_OSD | map.CTRL_OSD_STATS;
    press(&a, keymap.STATS_HOTKEY);
    try std.testing.expectEqual(overlay, r.glass.ctrl & overlay);
    r.ask(mc.REQ_RUN_PROGRAM, "BOOT.WSM");
    a.tick();
    try std.testing.expectEqualStrings("BOOT.WSM running", status(&a));
    try std.testing.expectEqual(overlay, r.glass.ctrl & overlay);
    r.ask(mc.REQ_BACK_TO_OS, "");
    a.tick();
    try std.testing.expectEqual(overlay, r.glass.ctrl & overlay);
}

fn refused(r: *Rig, a: *App, why: []const u8) !void {
    const resets = r.glass.resets;
    a.tick();
    a.tick(); // handled once: not retried while the cart keeps asking
    try std.testing.expect(std.mem.indexOf(u8, status(a), why) != null);
    try std.testing.expectEqual(resets, r.glass.resets); // the cart kept running
    const at = (WORDS * 4 - mc.CART_REQ_FROM_TOP) / 4;
    @memset(r.words[at..][0 .. 4 + mc.CART_REQ_NAME_MAX / 4], 0); // the firmware's block: the rest is GEM's load
    try std.testing.expectEqual(@as(?usize, null), try r.holds("demo-dd.zmd", map.DISK_MAGIC));
}

test "a request the glass cannot serve leaves the cart running and says why" {
    const r = try Rig.init();
    defer r.deinit();
    var a = try started(r);
    defer a.deinit();
    r.ask(mc.REQ_RUN_PROGRAM, "../../etc/x");
    try refused(r, &a, "BadProgramName");
    r.glass.request = 0;
    a.tick(); // the cart stopped asking: the next request is a new one
    r.ask(mc.REQ_RUN_PROGRAM, "NOPE.WSM");
    try refused(r, &a, "FileNotFound");
    r.glass.request = 0;
    a.tick();
    try r.fat("progs/demo-dd/SAMPLE.RAW.zmd", "a data file's image"); // SAMPLE.RAW is there, type RAW
    r.ask(mc.REQ_RUN_PROGRAM, "SAMPLE.RAW");
    try refused(r, &a, "NotAProgram");
    r.glass.request = 0;
    a.tick();
    r.ask(7, "");
    try refused(r, &a, "UnknownRequest");
}

test "a request block that never checks is refused after a few polls" {
    const r = try Rig.init();
    defer r.deinit();
    var a = try started(r);
    defer a.deinit();
    r.ask(mc.REQ_RUN_PROGRAM, "BOOT.WSM");
    r.words[(WORDS * 4 - mc.CART_REQ_FROM_TOP) / 4 + 3] ^= 1; // the check word not landed yet
    for (0..request.BLOCK_POLLS - 1) |_| a.tick();
    try std.testing.expect(std.mem.indexOf(u8, status(&a), "BadRequestBlock") == null);
    a.tick();
    try std.testing.expect(std.mem.indexOf(u8, status(&a), "BadRequestBlock") != null);
}

test "names and paths: only a FAT name, under progs/<disk>" {
    try std.testing.expect(request.validName("BOOT.WSM") and request.validName("A-1_B.X"));
    for ([_][]const u8{ "", ".hidden", "a/b", "..", "a\\b", "THIS.NAME.IS.TOO.LONG", "SP ACE" }) |n|
        try std.testing.expect(!request.validName(n));
    const p = try request.programPath(gpa, "/mnt/sd/zigmachine", "demo-st_replay.zmd", "BOOT.WSM");
    defer gpa.free(p);
    try std.testing.expectEqualStrings("/mnt/sd/zigmachine/progs/demo-st_replay/BOOT.WSM.zmd", p);
}

fn index(a: *const App, file: []const u8) usize {
    for (a.disks.disks, 0..) |d, k| if (std.mem.eql(u8, d.file, file)) return k;
    unreachable;
}

test "a cart boots another off the shelf by tag (a Union Demo door), and -1 goes back to it" {
    const r = try Rig.init();
    defer r.deinit();
    try r.fat("demo-union_demo.zmd", "the street");
    try r.fat("demo-union_tnt1.zmd", "a door's screen");
    var a = try App.init(gpa, io, r.glass.regs(), r.ddr(), r.dir);
    defer a.deinit();
    const street = index(&a, "demo-union_demo.zmd");
    a.menu.list.cursor = street;
    press(&a, keymap.KEY_ENTER);
    try std.testing.expectEqual(@as(?usize, street), a.current);
    r.ask(mc.REQ_LOAD_CART, "union_tnt1");
    a.tick();
    try std.testing.expectEqual(@as(?usize, index(&a, "demo-union_tnt1.zmd")), a.current);
    try std.testing.expectEqual(@as(?usize, null), try r.holds("demo-union_tnt1.zmd", map.DISK_MAGIC));
    r.glass.request = 0;
    a.tick(); // the door's screen runs: no request
    r.ask(mc.REQ_BACK, "");
    a.tick();
    try std.testing.expectEqual(@as(?usize, street), a.current);
    try std.testing.expectEqual(@as(?usize, null), try r.holds("demo-union_demo.zmd", map.DISK_MAGIC));
    r.glass.request = 0;
    a.tick();
    r.ask(mc.REQ_BACK, ""); // nothing loaded the street: back is the menu, the cart keeps running
    a.tick();
    try std.testing.expect(a.open);
    try std.testing.expectEqual(@as(?usize, street), a.current);
}

test "a tag that is not a shelf disk, or not a tag, leaves the cart running and says why" {
    const r = try Rig.init();
    defer r.deinit();
    var a = try started(r);
    defer a.deinit();
    r.ask(mc.REQ_LOAD_CART, "../etc");
    try refused(r, &a, "BadCartTag");
    r.glass.request = 0;
    a.tick();
    r.ask(mc.REQ_LOAD_CART, "union_nope");
    try refused(r, &a, "NoSuchCart");
    for ([_][]const u8{ "union_tnt1", "union_superscroller", "a1_b2" }) |t| try std.testing.expect(request.validTag(t));
    for ([_][]const u8{ "", "UNION", "a/b", "a.b", "x" ** 41 }) |t| try std.testing.expect(!request.validTag(t));
}
