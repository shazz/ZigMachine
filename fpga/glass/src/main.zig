// glass: the ZigMachine console's ARM-side program (docs/FPGA_GLASS.md).
//
//   glass run [--no-wait] [--mouse-scale=PCT] [SHELF_DIR]
//                                   the board: /dev/mem windows, evdev input, the OSD menu;
//                                   --no-wait: do not wait for the firmware's RUNNING
//                                   (for a firmware that does not report CART_STATE yet);
//                                   --mouse-scale: pointer speed, 100 = a pixel a count
//   glass sim-load DISK OUT [WIN]   desktop: load DISK into a simulated glass + fake DDR of
//                                   WIN bytes (default the board's), write the placed image
//                                   to OUT; exit 1 unless the rest of the window is zero
//   glass sim-menu SHELF_DIR        desktop: the menu the OSD would show, as text
const std = @import("std");
const map = @import("map.zig");
const bus = @import("bus.zig");
const sim = @import("sim.zig");
const loader = @import("loader.zig");
const osd = @import("osd.zig");
const App = @import("app.zig").App;
const devmem = @import("devmem.zig");
const evdev = @import("evdev.zig");
const pad = @import("pad.zig");
const mouse = @import("mouse.zig");

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
            } else opt.dir = a;
        }
        return run(init, opt);
    }
    if (std.mem.eql(u8, cmd, "sim-load")) {
        const disk = args.next() orelse return usage();
        const out = args.next() orelse return usage();
        const win = if (args.next()) |w| try std.fmt.parseInt(u32, w, 0) else map.DDR_CART_BYTES;
        return simLoad(init, disk, out, win);
    }
    if (std.mem.eql(u8, cmd, "sim-menu")) return simMenu(init, args.next() orelse return usage());
    return usage();
}

fn usage() u8 {
    std.debug.print("usage: glass run [--no-wait] [--mouse-scale=PCT] [SHELF_DIR] | sim-load DISK OUT [WINDOW] | sim-menu SHELF_DIR\n", .{});
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
    const placed = std.mem.sliceAsBytes(words)[0..rep.image_bytes];
    const tail = std.mem.sliceAsBytes(words)[std.mem.alignForward(usize, rep.image_bytes, 4)..];
    if (std.mem.indexOfNone(u8, tail, &.{0}) != null or glass.ctrl & map.CTRL_RUN == 0) {
        std.debug.print("sim-load {s}: window not clean after the image, or the cart is not running\n", .{disk_path});
        return 1;
    }
    try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = out_path, .data = placed });
    std.debug.print("{s}: {d} bytes ({d} packed) at 0x{X:0>8}, cart up after {d} polls\n", .{ disk_path, rep.image_bytes, rep.packed_bytes, glass.load_base, rep.polls });
    return 0;
}

fn simMenu(init: std.process.Init, dir: []const u8) !u8 {
    var glass = sim.Glass{};
    var words = [_]u32{0} ** 4;
    var app = try App.init(init.gpa, init.io, glass.regs(), .{ .words = &words }, dir);
    defer app.deinit();
    var text: [osd.ROWS * (osd.COLS + 1)]u8 = undefined;
    app.osd.dump(&text);
    std.debug.print("{s}", .{text});
    return 0;
}

const RunOptions = struct { dir: []const u8 = DEFAULT_SHELF, wait: bool = true, mouse_scale: i32 = mouse.SCALE_ONE };

fn run(init: std.process.Init, opt: RunOptions) !u8 {
    const board = try devmem.open();
    var app = try App.init(init.gpa, init.io, board.regs(), board.ddr(), opt.dir);
    defer app.deinit();
    app.opt.idle = devmem.napMs;
    app.opt.wait_boot = opt.wait;
    app.mouse.scale = @max(1, opt.mouse_scale);
    var inputs = evdev.Inputs{};
    defer inputs.closeAll();
    var buf: [64]evdev.Raw = undefined;
    // By the clock, not by poll: a moving mouse wakes poll() a thousand times a second.
    var next_scan: i64 = 0;
    var next_watch: i64 = 0;
    while (true) {
        const now = nowMs();
        if (now >= next_scan) { // every 2 s: a pad or a mouse plugged in later
            inputs.rescan();
            next_scan = now + 2000;
        }
        if (now >= next_watch) {
            app.watch();
            next_watch = now + 100;
        }
        const n = inputs.poll(100, &buf);
        for (buf[0..n]) |r| dispatch(&app, &inputs, r);
    }
}

fn nowMs() i64 {
    var ts: std.os.linux.timespec = undefined;
    _ = std.os.linux.clock_gettime(.MONOTONIC, &ts);
    return @as(i64, ts.sec) * 1000 + @divTrunc(@as(i64, ts.nsec), 1_000_000);
}

// By event, not by device: a combo receiver's one node is a keyboard AND a mouse.
fn dispatch(app: *App, inputs: *evdev.Inputs, r: evdev.Raw) void {
    const d = inputs.devs[r.dev];
    if (r.type == mouse.EV_SYN) {
        if (r.code == mouse.SYN_REPORT) app.sync();
    } else if (mouse.isMouse(r.type, r.code)) {
        app.mouseEvent(r.type, r.code, r.value, r.ms);
    } else if (r.type == pad.EV_ABS) {
        if (d.stick) app.padEvent(r.type, r.code, r.value, d.x, d.y);
    } else if (r.type == pad.EV_KEY and r.code >= 0x100) { // a pad's buttons: 0x100 (BTN_MISC) up
        app.padEvent(r.type, r.code, r.value, d.x, d.y);
    } else if (r.type == pad.EV_KEY) {
        app.key(r.code, r.value);
    }
}
