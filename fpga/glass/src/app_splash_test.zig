// The boot screen at power-on (app_splash.zig) against the simulated glass: the start policy
// (first boot, restart, cfg off, missing cart, a cart already running, --no-splash), the splash
// loaded as a plain cart then KOS powered on when it asks to leave, and every way it is cut short
// (a key, the cap, a trap, a broken disk, another load over it).
const std = @import("std");
const zx0 = @import("zx0");
const map = @import("map.zig");
const mc = @import("map_cart.zig");
const config = @import("config.zig");
const drive = @import("app_drive.zig");
const splash = @import("app_splash.zig");
const rig = @import("test_rig.zig");
const App = @import("app.zig").App;

const gpa = std.testing.allocator;
const io = std.testing.io;
const POST = mc.KOS_POST_FRAMES << mc.KOS_POST_SHIFT;

var now: i64 = 0;
fn clock() i64 {
    return now;
}

/// test_rig's card plus KOS's desktop and, if `cart`, the splash disk (a copy of a.zmd's cart).
fn card(cart: bool) !*rig.Rig {
    const r = try rig.Rig.init();
    const image = try zx0.pack(gpa, "the desktop's board image", .{});
    defer gpa.free(image);
    try r.tmp.dir.createDirPath(io, "kos");
    try r.tmp.dir.writeFile(io, .{ .sub_path = drive.DESKTOP, .data = image });
    if (!cart) return r;
    const disk = try r.tmp.dir.readFileAlloc(io, "a.zmd", gpa, .limited(1 << 20));
    defer gpa.free(disk);
    try r.tmp.dir.writeFile(io, .{ .sub_path = splash.DISK, .data = disk });
    return r;
}

const Booted = struct { app: App, why: splash.Why, mark: []u8 };

/// A glass start on the rig's card, its mark in the card's directory (a restart finds it there).
fn start(r: *rig.Rig, cfg: []const u8, no_splash: bool) !Booted {
    if (cfg.len > 0) try r.tmp.dir.writeFile(io, .{ .sub_path = config.FILE, .data = cfg });
    const mark = try std.fmt.allocPrint(gpa, "{s}/splashed", .{r.dir});
    var a = try r.app();
    a.splash_mark = mark;
    a.clock = clock;
    now = 1000;
    const why = splash.startOrPowerOn(&a, no_splash);
    return .{ .app = a, .why = why, .mark = mark };
}

fn done(b: *Booted) void {
    b.app.deinit();
    gpa.free(b.mark);
}

/// KOS powered on as without a splash: the desktop (drive A empty) running, the POST asked for.
fn onDesktop(r: *rig.Rig, a: *const App) !void {
    try std.testing.expect(a.running and !a.open and a.splash.disk == null);
    try std.testing.expectEqual(@as(?usize, null), a.current);
    try std.testing.expectEqual(@as(?u32, POST), rig.kos(&r.words));
}

fn index(a: *const App, file: []const u8) usize {
    for (a.disks.disks, 0..) |d, i| if (std.mem.eql(u8, d.file, file)) return i;
    unreachable;
}

test "the policy: only the first start, cfg on, nothing running or asked for, the cart there" {
    const play = splash.Inputs{ .enabled = true, .first = true, .running = false, .asked = false, .disk = 3 };
    try std.testing.expectEqual(splash.Why.play, splash.decide(play));
    var in = play;
    in.first = false;
    try std.testing.expectEqual(splash.Why.restart, splash.decide(in));
    in = play;
    in.enabled = false;
    try std.testing.expectEqual(splash.Why.off, splash.decide(in));
    in = play;
    in.disk = null;
    try std.testing.expectEqual(splash.Why.missing, splash.decide(in));
    in = play;
    in.running = true;
    try std.testing.expectEqual(splash.Why.running, splash.decide(in));
    in = play;
    in.asked = true;
    try std.testing.expectEqual(splash.Why.asked, splash.decide(in));
}

test "first boot: the splash runs as a plain cart, then KOS powers on when it asks to leave" {
    const r = try card(true);
    defer r.deinit();
    var b = try start(r, "", false);
    defer done(&b);
    const a = &b.app;
    try std.testing.expectEqual(splash.Why.play, b.why);
    try std.testing.expect(a.running and !a.open);
    try std.testing.expectEqual(@as(?usize, index(a, splash.DISK)), a.current);
    try std.testing.expectEqual(@as(?u32, null), rig.kos(&r.words)); // no KOS boot words: no POST yet
    a.tick();
    try std.testing.expect(a.splash.disk != null); // still playing
    r.glass.request = mc.REQ_BACK; // the cart is black and asks to leave (demo_main -1)
    a.tick();
    try onDesktop(r, a);
}

test "a restart (the mark is there), splash=0 and a missing cart all power KOS on at once" {
    const r = try card(true);
    defer r.deinit();
    {
        var b = try start(r, "", false);
        defer done(&b);
        try std.testing.expectEqual(splash.Why.play, b.why);
    }
    {
        var b = try start(r, "", false); // the same power-on: S99glass's loop, or killall glass
        defer done(&b);
        try std.testing.expectEqual(splash.Why.restart, b.why);
        try onDesktop(r, &b.app);
    }
    const off = try card(true);
    defer off.deinit();
    var b = try start(off, "splash=0\n", false);
    defer done(&b);
    try std.testing.expectEqual(splash.Why.off, b.why);
    try onDesktop(off, &b.app);
    const bare = try card(false);
    defer bare.deinit();
    var m = try start(bare, "", false);
    defer done(&m);
    try std.testing.expectEqual(splash.Why.missing, m.why);
    try onDesktop(bare, &m.app);
}

test "--no-splash, a cart already running and a broken splash disk power KOS on at once" {
    const r = try card(true);
    defer r.deinit();
    var b = try start(r, "", true);
    defer done(&b);
    try std.testing.expectEqual(splash.Why.asked, b.why);
    try onDesktop(r, &b.app);
    const busy = try card(true);
    defer busy.deinit();
    busy.glass.ctrl = map.CTRL_RUN; // U-Boot or a tool left ZIGGY running
    busy.glass.reads_since_run = busy.glass.boot_reads;
    var c = try start(busy, "", false);
    defer done(&c);
    try std.testing.expectEqual(splash.Why.running, c.why);
    const broken = try card(false);
    defer broken.deinit();
    try broken.tmp.dir.writeFile(io, .{ .sub_path = splash.DISK, .data = "not a disk" });
    var d = try start(broken, "", false);
    defer done(&d);
    try std.testing.expectEqual(splash.Why.failed, d.why);
    try onDesktop(broken, &d.app);
}

test "a key, the cap and a trap each end the splash; the key never reaches the cart" {
    const r = try card(true);
    defer r.deinit();
    var b = try start(r, "", false);
    defer done(&b);
    const pushed = r.glass.key_len;
    rig.press(&b.app, 57); // Space
    try onDesktop(r, &b.app);
    try std.testing.expectEqual(pushed, r.glass.key_len); // neither the press nor its release
    rig.press(&b.app, 57);
    try std.testing.expectEqual(pushed + 2, r.glass.key_len); // the next one is KOS's
    const late = try card(true);
    defer late.deinit();
    var c = try start(late, "", false);
    defer done(&c);
    now += splash.CAP_MS - 1;
    c.app.tick();
    try std.testing.expect(c.app.splash.disk != null);
    now += 2;
    c.app.tick();
    try onDesktop(late, &c.app);
    const trap = try card(true);
    defer trap.deinit();
    var t = try start(trap, "", false);
    defer done(&t);
    trap.glass.cart = .traps;
    t.app.tick();
    try std.testing.expect(t.app.splash.disk == null); // over; KOS's load then traps the same way
}

test "a load from elsewhere during the splash wins: no KOS over it" {
    const r = try card(true);
    defer r.deinit();
    var b = try start(r, "", false);
    defer done(&b);
    const a = &b.app;
    const asked = index(a, "a.zmd");
    drive.insertAndBoot(a, asked); // glass ctl load a.zmd
    a.tick();
    try std.testing.expect(a.splash.disk == null);
    try std.testing.expectEqual(@as(?usize, asked), a.current);
    try std.testing.expectEqual(@as(?usize, null), try r.loaded());
}
