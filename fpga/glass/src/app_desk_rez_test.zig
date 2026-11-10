// The desktop's mode across a program load (map_cart.zig DESK_REZ, app_request.zig): Matt on
// the board, 9 Nov, "i ran notepad from deskmode but it seems it switched to medium res". The
// program's image starts a fresh ROM, which then said "no desktop ran" (Getrez 0xFF: medium).
// The word the firmware leaves beside its request must reach the program's window, and the
// desktop's again when the program quits; no other load may carry one.
const std = @import("std");
const map = @import("map.zig");
const mc = @import("map_cart.zig");
const request = @import("app_request.zig");
const t = @import("app_request_test.zig");

const REZ = (t.WORDS * 4 - mc.DESK_REZ_FROM_TOP) / 4;
const SKIP = (t.WORDS * 4 - mc.BOOTSEC_SKIP_FROM_TOP) / 4;

test "the desk's mode goes into the program, and back into the desktop it quits to" {
    const r = try t.Rig.init();
    defer r.deinit();
    var a = try t.started(r);
    defer a.deinit();
    r.words[REZ] = mc.DESK_REZ_TAG | 2; // the desktop's firmware: the desk
    r.ask(mc.REQ_RUN_PROGRAM, "BOOT.WSM");
    a.tick();
    try std.testing.expectEqual(mc.DESK_REZ_TAG | 2, r.words[REZ]);
    try std.testing.expectEqual(@as(?usize, REZ), try r.holds("progs/demo-dd/BOOT.WSM.zmd", mc.DISK_MAGIC_PROGRAM));
    try std.testing.expectEqual(@as(?u32, null), a.opt.desk_rez); // nothing left for the next load
    a.tick(); // the program runs: no request
    r.words[REZ] = 0; // the program's firmware zeroed it at boot ...
    r.words[REZ] = mc.DESK_REZ_TAG | 2; // ... and writes it again with its request to quit
    r.ask(mc.REQ_BACK_TO_OS, "");
    a.tick();
    try std.testing.expectEqual(mc.DESK_REZ_TAG | 2, r.words[REZ]);
    try std.testing.expectEqual(mc.BOOTSEC_SKIP, r.words[SKIP]);
    r.words[SKIP] = 0;
    try std.testing.expectEqual(@as(?usize, REZ), try r.holds("demo-dd.zmd", map.DISK_MAGIC));
}

test "no word, an untagged one or a mode past the desk: the program's window has none" {
    const bad = [_]u32{ 0, 2, mc.DESK_REZ_TAG | 3, 0x5600_0001 };
    for (bad) |w| {
        const r = try t.Rig.init();
        defer r.deinit();
        var a = try t.started(r);
        defer a.deinit();
        r.words[REZ] = w;
        r.ask(mc.REQ_RUN_PROGRAM, "BOOT.WSM");
        a.tick();
        try std.testing.expectEqual(@as(u32, 0), r.words[REZ]);
        try std.testing.expectEqual(@as(?usize, null), try r.holds("progs/demo-dd/BOOT.WSM.zmd", mc.DISK_MAGIC_PROGRAM));
    }
}

test "a failed request carries nothing into a later load" {
    const r = try t.Rig.init();
    defer r.deinit();
    var a = try t.started(r);
    defer a.deinit();
    r.words[REZ] = mc.DESK_REZ_TAG | 1;
    r.ask(mc.REQ_RUN_PROGRAM, "NOPE.WSM"); // no such program: the cart keeps running
    a.tick();
    try std.testing.expectEqual(@as(?u32, null), a.opt.desk_rez);
}

test "deskRez reads only a tagged mode the ROM knows" {
    var words = [_]u32{0} ** t.WORDS;
    const ddr = @import("bus.zig").Ddr{ .words = &words };
    try std.testing.expectEqual(@as(?u32, null), request.deskRez(ddr));
    for (0..3) |m| {
        words[REZ] = mc.DESK_REZ_TAG | @as(u32, @intCast(m));
        try std.testing.expectEqual(@as(?u32, words[REZ]), request.deskRez(ddr));
    }
    words[REZ] = mc.DESK_REZ_TAG | 0x100; // bits past the mode
    try std.testing.expectEqual(@as(?u32, null), request.deskRez(ddr));
}
