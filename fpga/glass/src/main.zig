// glass: the ZigMachine console's ARM-side program (docs/FPGA_GLASS.md).
//
//   glass run [--no-wait] [--mouse-scale=PCT] [--fw-opt=N] [SHELF_DIR]
//                                   the board: /dev/mem windows, evdev input, the OSD menu;
//                                   --no-wait: do not wait for the firmware's RUNNING
//                                   (for a firmware that does not report CART_STATE yet);
//                                   --mouse-scale: pointer speed, 100 = a pixel a count;
//                                   --fw-opt: the system's A/B switches (afi.zig) for every cart
//   glass ctl COMMAND...            the running glass's control channel (ctl.zig, `ctl help`)
//   glass sim-load DISK OUT [WIN]   desktop: load DISK into a simulated glass + fake DDR of
//                                   WIN bytes (default the board's), write the placed image
//                                   to OUT, the placed disk to OUT.disk and its descriptor
//                                   to OUT.desc; exit 1 unless
//                                   the window is image, disk, descriptor and zeros
//   glass sim-menu SHELF_DIR [PAGE] desktop: the menu the OSD would show, as text;
//                                   PAGE = shelf (default), console or debug
const std = @import("std");
const map = @import("map.zig");
const bus = @import("bus.zig");
const sim = @import("sim.zig");
const loader = @import("loader.zig");
const osd = @import("osd.zig");
const App = @import("app.zig").App;
const menu = @import("menu.zig");
const devmem = @import("devmem.zig");
const evdev = @import("evdev.zig");
const pad = @import("pad.zig");
const mouse = @import("mouse.zig");
const ctl_sock = @import("ctl_sock.zig");
const afi = @import("afi.zig");

const linux = std.os.linux;
const DEFAULT_SHELF = "/mnt/sd/zigmachine";

pub fn main(init: std.process.Init) !u8 {
    var args = init.minimal.args.iterate();
    _ = args.next();
    const cmd = args.next() orelse return usage();
    if (std.mem.eql(u8, cmd, "run")) {
        var opt = RunOptions{};
        while (args.next()) |a| {
            if (std.mem.eql(u8, a, "--no-wait")) {
                opt.wait = false;
            } else if (std.mem.startsWith(u8, a, "--mouse-scale=")) {
                const pct = std.fmt.parseInt(i32, a["--mouse-scale=".len..], 10) catch return usage();
                if (pct < 1 or pct > 10_000) return usage();
                opt.mouse_scale = @divTrunc(pct * mouse.SCALE_ONE, 100);
            } else if (std.mem.startsWith(u8, a, "--fw-opt=")) {
                opt.fw_opt = afi.parseOpt(a["--fw-opt=".len..]) orelse return usage();
            } else opt.dir = a;
        }
        return run(init, opt);
    }
    if (std.mem.eql(u8, cmd, "ctl")) {
        var words: [8][]const u8 = undefined;
        var n: usize = 0;
        while (args.next()) |a| : (n += 1) {
            if (n == words.len) return usage();
            words[n] = a;
        }
        return ctl_sock.client(words[0..n]);
    }
    if (std.mem.eql(u8, cmd, "sim-load")) {
        const disk = args.next() orelse return usage();
        const out = args.next() orelse return usage();
        const win = if (args.next()) |w| try std.fmt.parseInt(u32, w, 0) else map.DDR_CART_BYTES;
        return simLoad(init, disk, out, win);
    }
    if (std.mem.eql(u8, cmd, "sim-menu")) {
        const dir = args.next() orelse return usage();
        const page = std.meta.stringToEnum(menu.Page, args.next() orelse "shelf") orelse return usage();
        return simMenu(init, dir, page);
    }
    return usage();
}

fn usage() u8 {
    std.debug.print("usage: glass run [--no-wait] [--mouse-scale=PCT] [--fw-opt=N] [SHELF_DIR] | ctl COMMAND... | sim-load DISK OUT [WINDOW] | sim-menu SHELF_DIR [shelf|console|debug]\n", .{});
    return 2;
}

fn simLoad(init: std.process.Init, disk_path: []const u8, out_path: []const u8, window: u32) !u8 {
    const gpa = init.gpa;
    const disk = try std.Io.Dir.cwd().readFileAlloc(init.io, disk_path, gpa, .limited(16 << 20));
    defer gpa.free(disk);
    const words = try gpa.alloc(u32, window / 4);
    defer gpa.free(words);
    @memset(words, 0xDEAD_BEEF); // DDR is not zero at power-on; the loader must clear it
    var glass = sim.Glass{};
    const ddr = bus.Ddr{ .words = words };
    const rep = loader.load(gpa, glass.regs(), ddr, disk, .{}) catch |err| {
        std.debug.print("sim-load {s}: {t}\n", .{ disk_path, err });
        return 1;
    };
    // The window must be exactly the plan's parts and zeros; OUT gets the image as it
    // landed, OUT.disk the disk as the cart CPU will read it.
    var p = try loader.plan(gpa, disk, window);
    defer p.deinit(gpa);
    const parts = p.parts();
    if ((bus.Ddr{ .words = words }).verifyParts(&parts) != null or glass.ctrl & map.CTRL_RUN == 0) {
        std.debug.print("sim-load {s}: window is not image, disk, descriptor and zeros, or the cart is not running\n", .{disk_path});
        return 1;
    }
    const all = std.mem.sliceAsBytes(words);
    try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = out_path, .data = all[0..rep.image_bytes] });
    const disk_out = try std.fmt.allocPrint(gpa, "{s}.disk", .{out_path});
    defer gpa.free(disk_out);
    try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = disk_out, .data = all[rep.disk_at..][0..rep.disk_bytes] });
    const desc_out = try std.fmt.allocPrint(gpa, "{s}.desc", .{out_path});
    defer gpa.free(desc_out);
    try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = desc_out, .data = all[p.desc_at..][0 .. map.DISK_DESC_WORDS * 4] });
    std.debug.print("{s}: {d} bytes ({d} packed) at 0x{X:0>8}, disk {d} bytes at +0x{X}, cart up after {d} polls\n", .{ disk_path, rep.image_bytes, rep.packed_bytes, glass.load_base, rep.disk_bytes, rep.disk_at, rep.polls });
    return 0;
}

fn simMenu(init: std.process.Init, dir: []const u8, page: menu.Page) !u8 {
    var glass = sim.Glass{};
    var words = [_]u32{0} ** 4;
    var app = try App.init(init.gpa, init.io, glass.regs(), .{ .words = &words }, dir);
    defer app.deinit();
    app.menu.page = page;
    app.redraw();
    var text: [osd.ROWS * (osd.COLS + 1)]u8 = undefined;
    app.osd.dump(&text);
    std.debug.print("{s}", .{text});
    return 0;
}

const RunOptions = struct { dir: []const u8 = DEFAULT_SHELF, wait: bool = true, mouse_scale: i32 = mouse.SCALE_ONE, fw_opt: ?u32 = null };

fn run(init: std.process.Init, opt: RunOptions) !u8 {
    const board = try devmem.open();
    afi.forRun(board.regs(), board.afi(), opt.fw_opt, devmem.napSec) catch |err| {
        if (err == error.W64NeedsBoot) std.log.err("--fw-opt W64 needs HP1 64-bit since boot (boot.cmd 0xF00): reboot", .{});
        return err;
    };
    var app = try App.init(init.gpa, init.io, board.regs(), board.ddr(), opt.dir);
    defer app.deinit();
    app.opt.fw_opt = opt.fw_opt;
    app.opt.idle = devmem.napMs;
    app.opt.wait_boot = opt.wait;
    app.mouse.scale = @max(1, opt.mouse_scale);
    app.clock = nowMs;
    app.stats.start_ms = nowMs();
    app.sd_writable = sdWritable;
    var inputs = evdev.Inputs{};
    defer inputs.closeAll();
    inputs.extra = ctl_sock.listen(ctl_sock.PATH) catch |err| blk: {
        std.log.warn("control channel {s}: {t} (glass ctl will not answer)", .{ ctl_sock.PATH, err });
        break :blk -1;
    };
    var buf: [64]evdev.Raw = undefined;
    // By the clock, not by poll: a moving mouse wakes poll() a thousand times a second.
    var next_scan: i64 = 0;
    var next_watch: i64 = 0;
    while (true) {
        const now = nowMs();
        if (now >= next_scan) { // every 2 s: a pad or a mouse plugged in later
            inputs.rescan();
            app.inputs = inputs.n;
            next_scan = now + 2000;
        }
        if (now >= next_watch) {
            app.tick();
            next_watch = now + 100;
        }
        const n = inputs.poll(100, &buf);
        for (buf[0..n]) |r| dispatch(&app, &inputs, r);
        if (inputs.extra_ready) ctl_sock.serve(inputs.extra, &app, ctlLine);
    }
}

fn ctlLine(ctx: *anyopaque, line: []const u8, w: *std.Io.Writer) void {
    @import("app_ctl.zig").exec(@ptrCast(@alignCast(ctx)), line, w);
}

fn nowMs() i64 {
    var ts: std.os.linux.timespec = undefined;
    _ = std.os.linux.clock_gettime(.MONOTONIC, &ts);
    return @as(i64, ts.sec) * 1000 + @divTrunc(@as(i64, ts.nsec), 1_000_000);
}

// The SD card stays mounted read-only (S99glass) so a power cut cannot hurt it;
// a settings save remounts it read-write for the write and the rename only.
const SD_MOUNT = "/mnt/sd";

fn sdWritable(rw: bool) bool {
    const flags: u32 = if (rw) linux.MS.REMOUNT else linux.MS.REMOUNT | linux.MS.RDONLY;
    const rc = linux.mount(null, SD_MOUNT, null, flags, 0);
    if (linux.errno(rc) == .SUCCESS) return true;
    std.log.warn("remount {s} {s}: {t}", .{ SD_MOUNT, if (rw) "rw" else "ro", linux.errno(rc) });
    return false;
}

// By event, not by device: a combo receiver's one node is a keyboard AND a mouse.
fn dispatch(app: *App, inputs: *evdev.Inputs, r: evdev.Raw) void {
    const d = inputs.devs[r.dev];
    if (r.type == mouse.EV_SYN) {
        if (r.code == mouse.SYN_REPORT) app.sync();
    } else if (mouse.isMouse(r.type, r.code)) {
        app.mouseEvent(r.type, r.code, r.value, r.ms);
    } else if (r.type == pad.EV_ABS) {
        if (d.stick) app.padEvent(r.type, r.code, r.value, d.x, d.y, d.name());
    } else if (r.type == pad.EV_KEY and r.code >= 0x100) { // a pad's buttons: 0x100 (BTN_MISC) up
        app.padEvent(r.type, r.code, r.value, d.x, d.y, d.name());
    } else if (r.type == pad.EV_KEY) {
        app.key(r.code, r.value);
    }
}
