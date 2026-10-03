// The glass program driven like a user would, against the simulated block:
// F12, the menu, keys reaching the cart, a load, and a cart that traps.
const std = @import("std");
const zx0 = @import("zx0");
const map = @import("map.zig");
const bus = @import("bus.zig");
const sim = @import("sim.zig");
const zmd = @import("zmd.zig");
const keymap = @import("keymap.zig");
const pad = @import("pad.zig");
const mouse = @import("mouse.zig");
const App = @import("app.zig").App;

const gpa = std.testing.allocator;
const io = std.testing.io;

const Rig = struct {
    glass: sim.Glass = .{},
    words: [1024]u32 = [_]u32{0} ** 1024,
    tmp: std.testing.TmpDir,
    dir: []u8,

    fn init() !*Rig {
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

    fn deinit(r: *Rig) void {
        r.tmp.cleanup();
        gpa.free(r.dir);
        gpa.destroy(r);
    }

    fn app(r: *Rig) !App {
        return App.init(gpa, io, r.glass.regs(), .{ .words = &r.words }, r.dir);
    }
};

fn press(a: *App, code: u16) void {
    a.key(code, 1);
    a.key(code, 0);
}

test "the menu comes up, loads a disk, and the OSD gets out of the way" {
    const r = try Rig.init();
    defer r.deinit();
    var a = try r.app();
    defer a.deinit();
    try std.testing.expect(r.glass.ctrl & map.CTRL_OSD != 0);
    try std.testing.expectEqual(@as(u32, map.OSD_INVERSE | ' '), r.glass.text[0]); // the title bar is on screen
    press(&a, keymap.KEY_ENTER); // the cursor starts on a.zmd
    try std.testing.expect(r.glass.ctrl & map.CTRL_RUN != 0);
    try std.testing.expect(r.glass.ctrl & map.CTRL_OSD == 0);
    try std.testing.expectEqual(@as(?usize, null), (bus.Ddr{ .words = &r.words }).verify("board image bytes"));
    try std.testing.expectEqual(@as(?usize, 0), a.current);
}

test "keys reach the cart only while the OSD is closed, and are released when it opens" {
    const r = try Rig.init();
    defer r.deinit();
    var a = try r.app();
    defer a.deinit();
    press(&a, keymap.KEY_ENTER);
    _ = r.glass.pop(); // nothing queued by the load: the FIFO was flushed
    a.key(30, 1); // 'a' down, held
    try std.testing.expectEqual(@as(?u32, 'a' | map.KEY_DOWN), r.glass.pop());
    a.key(keymap.OSD_HOTKEY, 1);
    try std.testing.expect(r.glass.ctrl & map.CTRL_OSD != 0);
    try std.testing.expectEqual(@as(?u32, 'a'), r.glass.pop()); // released for the cart
    a.key(31, 1); // 's' goes to the menu, not the cart
    try std.testing.expectEqual(@as(?u32, null), r.glass.pop());
    a.key(keymap.KEY_ESC, 1); // Esc closes the menu over a running cart
    try std.testing.expect(r.glass.ctrl & map.CTRL_OSD == 0);
    a.padEvent(pad.EV_ABS, pad.ABS_HAT0X, 1, .{}, .{});
    try std.testing.expectEqual(map.JOY_RIGHT, r.glass.joy);
}

test "a disk without a board image says so and nothing runs" {
    const r = try Rig.init();
    defer r.deinit();
    var a = try r.app();
    defer a.deinit();
    press(&a, keymap.KEY_DOWN);
    press(&a, keymap.KEY_ENTER);
    try std.testing.expect(r.glass.ctrl & map.CTRL_RUN == 0);
    try std.testing.expect(r.glass.ctrl & map.CTRL_OSD != 0);
    try std.testing.expect(std.mem.indexOf(u8, a.menu.status, "NoBoardImage") != null);
    a.key(keymap.KEY_ESC, 1); // with no cart to go back to, the menu stays
    try std.testing.expect(r.glass.ctrl & map.CTRL_OSD != 0);
}

test "a cart that traps brings the menu back and is held" {
    const r = try Rig.init();
    defer r.deinit();
    var a = try r.app();
    defer a.deinit();
    press(&a, keymap.KEY_ENTER);
    r.glass.cart = .traps;
    a.watch();
    try std.testing.expect(r.glass.ctrl & map.CTRL_RUN == 0);
    try std.testing.expect(r.glass.ctrl & map.CTRL_OSD != 0);
    try std.testing.expect(std.mem.indexOf(u8, a.menu.status, "trapped (code 5)") != null);
}

test "the mouse reaches the cart only while the OSD is closed; a held button is released first" {
    const r = try Rig.init();
    defer r.deinit();
    var a = try r.app();
    defer a.deinit();
    a.mouseEvent(mouse.EV_REL, mouse.REL_X, 50, 0); // over the menu: dropped
    a.sync();
    try std.testing.expectEqual(@as(u32, 0), r.glass.ptr_seq);
    press(&a, keymap.KEY_ENTER); // load: the OSD closes
    a.mouseEvent(mouse.EV_REL, mouse.REL_X, 10, 0);
    a.mouseEvent(mouse.EV_KEY, mouse.BTN_LEFT, 1, 0);
    a.sync();
    const held = a.mouse.word(map.PTR_BTN_PRESS);
    try std.testing.expectEqual(held, r.glass.ptr);
    try std.testing.expectEqual(@as(u32, 330), a.mouse.x());
    a.key(keymap.OSD_HOTKEY, 1);
    try std.testing.expectEqual(a.mouse.word(0), r.glass.ptr); // released, kept in place
    const seq = r.glass.ptr_seq;
    a.mouseEvent(mouse.EV_KEY, mouse.BTN_LEFT, 0, 5); // the real release, behind the menu
    a.mouseEvent(mouse.EV_REL, mouse.REL_Y, 40, 5);
    a.sync();
    try std.testing.expectEqual(seq, r.glass.ptr_seq); // nothing reached the cart
}
