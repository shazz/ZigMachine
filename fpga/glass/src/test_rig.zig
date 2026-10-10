// The test rig the app tests share: a simulated glass, a fake DDR window and a
// shelf directory with a fat disk (a.zmd) and a wasm-only one (b.zmd).
const std = @import("std");
const zx0 = @import("zx0");
const map = @import("map.zig");
const sim = @import("sim.zig");
const zmd = @import("zmd.zig");
const App = @import("app.zig").App;

const gpa = std.testing.allocator;
const io = std.testing.io;

pub const Rig = struct {
    glass: sim.Glass = .{},
    words: [1024]u32 = [_]u32{0} ** 1024,
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

    pub fn app(r: *Rig) !App {
        return App.init(gpa, io, r.glass.regs(), .{ .words = &r.words }, r.dir);
    }
};

pub fn press(a: *App, code: u16) void {
    a.key(code, 1);
    a.key(code, 0);
}
