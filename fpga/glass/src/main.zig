// glass: the ZigMachine console's ARM-side program (docs/FPGA_GLASS.md).
//
//   glass run [--no-wait] [SHELF_DIR]
//                                   the board: /dev/mem windows, evdev input, the OSD menu;
//                                   --no-wait: do not wait for the firmware's RUNNING
//                                   (for a firmware that does not report CART_STATE yet)
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

const DEFAULT_SHELF = "/mnt/sd/zigmachine";

pub fn main(init: std.process.Init) !u8 {
    var args = init.minimal.args.iterate();
    _ = args.next();
    const cmd = args.next() orelse return usage();
    if (std.mem.eql(u8, cmd, "run")) {
        var wait = true;
        var dir: []const u8 = DEFAULT_SHELF;
        while (args.next()) |a| {
            if (std.mem.eql(u8, a, "--no-wait")) wait = false else dir = a;
        }
        return run(init, dir, wait);
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
    std.debug.print("usage: glass run [--no-wait] [SHELF_DIR] | sim-load DISK OUT [WINDOW] | sim-menu SHELF_DIR\n", .{});
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

fn run(init: std.process.Init, dir: []const u8, wait: bool) !u8 {
    const board = try devmem.open();
    var app = try App.init(init.gpa, init.io, board.regs(), board.ddr(), dir);
    defer app.deinit();
    app.opt.idle = devmem.napMs;
    app.opt.wait_boot = wait;
    var inputs = evdev.Inputs{};
    defer inputs.closeAll();
    var buf: [64]evdev.Raw = undefined;
    var ticks: u32 = 0;
    while (true) : (ticks += 1) {
        if (ticks % 20 == 0) inputs.rescan(); // every ~2 s: a pad plugged in later
        const n = inputs.poll(100, &buf);
        for (buf[0..n]) |r| dispatch(&app, &inputs, r);
        app.watch();
    }
}

fn dispatch(app: *App, inputs: *evdev.Inputs, r: evdev.Raw) void {
    const d = inputs.devs[r.dev];
    // A gamepad's buttons are EV_KEY too, numbered from 0x100 (BTN_MISC) up.
    if (r.type == pad.EV_ABS or (r.type == pad.EV_KEY and r.code >= 0x100)) {
        app.padEvent(r.type, r.code, r.value, d.x, d.y);
    } else if (r.type == pad.EV_KEY) {
        app.key(r.code, r.value);
    }
}
