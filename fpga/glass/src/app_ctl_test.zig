// The control channel driven like the lead's script drives it (app_ctl.zig), against the
// simulated block: a load by file name, keys and the pad reaching the cart, the menu, a
// cart stopped, and the ZMSTAT line for a running, a silent and a trapped cart.
const std = @import("std");
const map = @import("map.zig");
const app_ctl = @import("app_ctl.zig");
const App = @import("app.zig").App;
const Rig = @import("test_rig.zig").Rig;

var now_ms: i64 = 1000;

fn clock() i64 {
    return now_ms;
}

const Reply = struct {
    buf: [4096]u8 = undefined,
    len: usize = 0,

    fn text(self: *const Reply) []const u8 {
        return self.buf[0..self.len];
    }
};

fn run(a: *App, line: []const u8) Reply {
    var r = Reply{};
    var w = std.Io.Writer.fixed(&r.buf);
    app_ctl.exec(a, line, &w);
    r.len = w.buffered().len;
    return r;
}

fn expectStarts(reply: Reply, want: []const u8) !void {
    if (std.mem.startsWith(u8, reply.text(), want)) return;
    std.debug.print("want \"{s}...\", got \"{s}\"\n", .{ want, reply.text() });
    return error.TestExpectedEqual;
}

fn rigApp(r: *Rig) !App {
    var a = try r.app();
    a.clock = clock;
    return a;
}

test "load by file name runs the cart and closes the menu; a wrong name is an err" {
    const r = try Rig.init();
    defer r.deinit();
    var a = try rigApp(r);
    defer a.deinit();
    try expectStarts(run(&a, "list"), "a.zmd\tFat Disk\nb.zmd\tWasm Only\nok 2 disks");
    try expectStarts(run(&a, "load nope.zmd"), "err no disk nope.zmd");
    try expectStarts(run(&a, "load b.zmd"), "err b.zmd: NoBoardImage");
    try expectStarts(run(&a, "load A.ZMD"), "ok a.zmd running");
    try std.testing.expectEqual(@as(?usize, 0), a.current);
    try std.testing.expect(r.glass.ctrl & map.CTRL_OSD == 0);
    try std.testing.expectEqual(@as(?usize, null), try r.loaded());
    try expectStarts(run(&a, "bogus"), "err UnknownCommand");
}

test "a tapped key goes down now and up a tick later; joy and the menu follow the OSD" {
    const r = try Rig.init();
    defer r.deinit();
    var a = try rigApp(r);
    defer a.deinit();
    try expectStarts(run(&a, "osd close"), "err no cart"); // nothing to go back to
    try expectStarts(run(&a, "load a.zmd"), "ok");
    try expectStarts(run(&a, "key 1"), "ok key 0x31 tap to the cart");
    try std.testing.expectEqual(@as(?u32, '1' | map.KEY_DOWN), r.glass.pop());
    a.tick(); // not held TAP_MS yet
    try std.testing.expectEqual(@as(?u32, null), r.glass.pop());
    now_ms += app_ctl.TAP_MS;
    a.tick();
    try std.testing.expectEqual(@as(?u32, '1'), r.glass.pop());
    _ = run(&a, "key esc down");
    try std.testing.expectEqual(@as(?u32, map.KEY_ESCAPE | map.KEY_DOWN), r.glass.pop());
    try expectStarts(run(&a, "joy right+fire"), "ok joy 0x28");
    try std.testing.expectEqual(map.JOY_RIGHT | map.JOY_FIRE, r.glass.joy);
    try expectStarts(run(&a, "osd open"), "ok menu open");
    try std.testing.expectEqual(@as(?u32, map.KEY_ESCAPE), r.glass.pop()); // the held key let go
    try std.testing.expectEqual(@as(u32, 0), r.glass.joy);
    try expectStarts(run(&a, "joy fire"), "err the menu is open");
    try expectStarts(run(&a, "key down"), "ok key 0xE021 tap to the menu"); // the menu's cursor
    try std.testing.expectEqual(@as(usize, 1), a.menu.list.cursor);
    try expectStarts(run(&a, "osd close"), "ok menu closed");
}

test "stats: a running cart's rate, then quit-cart, a silent boot and a trap" {
    const r = try Rig.init();
    defer r.deinit();
    var a = try rigApp(r);
    defer a.deinit();
    try expectStarts(run(&a, "stats"), "ZMSTAT cart=- fps=- frame_ms=- bard=- player=- state=idle");
    _ = run(&a, "load a.zmd");
    for (0..20) |_| { // 2 s of ticks; the stand-in firmware finishes a frame a CART_STATE read
        now_ms += 100;
        a.tick();
    }
    try expectStarts(run(&a, "stats 1"), "ZMSTAT cart=a.zmd fps=10.0 frame_ms=100.0 bard=- player=old_fw state=running frames=10 secs=1.0 missed=50");
    try expectStarts(run(&a, "quit-cart"), "ok a.zmd stopped");
    try std.testing.expect(r.glass.ctrl & map.CTRL_RUN == 0);
    try std.testing.expect(a.open);
    try expectStarts(run(&a, "stats"), "ZMSTAT cart=a.zmd fps=- frame_ms=- bard=- player=- state=quit");
    r.glass.cart = .silent;
    try expectStarts(run(&a, "load a.zmd"), "err a.zmd: CartSilent");
    try std.testing.expect(std.mem.indexOf(u8, run(&a, "stats").text(), "state=silent frames=- secs=- missed=- beat=0 trap=- err=CartSilent") != null);
    r.glass.cart = .traps;
    try expectStarts(run(&a, "load a.zmd"), "err a.zmd: CartTrapped");
    try std.testing.expect(std.mem.indexOf(u8, run(&a, "stats").text(), "state=trapped") != null);
}
