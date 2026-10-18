// A cart's request for a cart swap (docs/FPGA_GLASS.md, "Programs off a data disk"): what
// docs/sealed-loader.js swapCart does for requests 3 and 4, done by ZWINDOW. GEM over a
// data disk asks to run a program off it (REQ_RUN_PROGRAM, the FAT file's name in the
// request block); the program asks to go back (REQ_BACK_TO_OS). The firmware writes the
// block, then CART_STATE = CART_REQUEST | request << 8 (cycles/bdiskapp.c).
//
// A program is wasm on the disk and native code on the board, so its board image is built
// beforehand (tools/glass_shelf.py): a fat disk of the SAME data disk plus the program's
// image, at <shelf>/progs/<disk>/<NAME>.zmd, outside the shelf's scan. Loading it is a cold
// load like any other, with the descriptor's DISK_MAGIC_PROGRAM, so the disk is back in DDR
// and the program's firmware hands no listing. Going back reloads the shelf entry: GEM over
// its disk, which hands the listing again. A failed request leaves the cart running (the
// browser's failed swap) and is not retried until the cart is reloaded.
const std = @import("std");
const map = @import("map.zig");
const mc = @import("map_cart.zig");
const bus = @import("bus.zig");
const zmd = @import("zmd.zig");
const loader = @import("loader.zig");
const shelf = @import("shelf.zig");
const cart = @import("app_cart.zig");
const App = @import("app.zig").App;

pub const PROGS_DIR = "progs";
/// Polls of a request whose block does not check yet (its words still on their way).
pub const BLOCK_POLLS = 5;

pub const Request = struct { req: u32, name: []const u8 };
pub const Error = error{ BadRequestBlock, BadProgramName, UnknownRequest, NotAProgram };

/// The request block, if its check holds; `buf` holds the name.
pub fn readBlock(ddr: bus.Ddr, buf: *[mc.CART_REQ_NAME_MAX]u8) ?Request {
    const at = (ddr.bytes() - mc.CART_REQ_FROM_TOP) / 4;
    const w = ddr.words[at..][0 .. mc.CART_REQ_HEAD_WORDS + mc.CART_REQ_NAME_MAX / 4];
    if (w[0] != mc.CART_REQ_MAGIC or w[3] != ~(w[0] ^ w[1] ^ w[2]) or w[2] > mc.CART_REQ_NAME_MAX) return null;
    for (0..mc.CART_REQ_NAME_MAX / 4) |i| std.mem.writeInt(u32, buf[i * 4 ..][0..4], w[mc.CART_REQ_HEAD_WORDS + i], .little);
    return .{ .req = w[1], .name = buf[0..w[2]] };
}

/// A FAT name the glass may put in a path: 1..16 of [A-Za-z0-9._-], not starting with a dot.
/// The cart wrote it: never a path of its own (CWE-22).
pub fn validName(name: []const u8) bool {
    if (name.len == 0 or name.len > 16 or name[0] == '.') return false;
    for (name) |c| if (!(std.ascii.isAlphanumeric(c) or c == '.' or c == '_' or c == '-')) return false;
    return true;
}

/// <shelf>/progs/<disk without .zmd>/<NAME>.zmd
pub fn programPath(a: std.mem.Allocator, dir: []const u8, disk_file: []const u8, name: []const u8) ![]u8 {
    const stem = if (std.ascii.endsWithIgnoreCase(disk_file, ".zmd")) disk_file[0 .. disk_file.len - 4] else disk_file;
    const file = try std.fmt.allocPrint(a, "{s}.zmd", .{name});
    defer a.free(file);
    return std.fs.path.join(a, &.{ dir, PROGS_DIR, stem, file });
}

/// From the watchdog (app_cart.watch), while CART_STATE says CART_REQUEST.
pub fn poll(app: *App, state: u32) void {
    if (app.req_done) return;
    const i = app.current orelse return;
    var buf: [mc.CART_REQ_NAME_MAX]u8 = undefined;
    const r = readBlock(app.ddr, &buf) orelse {
        app.req_polls += 1;
        if (app.req_polls >= BLOCK_POLLS) failed(app, "request", error.BadRequestBlock);
        return;
    };
    app.req_done = true;
    if (r.req != state >> map.CART_ARG_SHIFT) return failed(app, "request", error.BadRequestBlock);
    switch (r.req) {
        mc.REQ_RUN_PROGRAM => runProgram(app, i, r.name) catch |err| failed(app, r.name, err),
        mc.REQ_BACK_TO_OS => cart.load(app, i),
        else => failed(app, "request", error.UnknownRequest),
    }
}

/// Program `name` off disk `i` (also the control channel's `load DISK PROGRAM`, app_ctl.zig).
pub fn runProgram(app: *App, i: usize, name: []const u8) !void {
    if (!validName(name)) return error.BadProgramName;
    const path = try programPath(app.gpa, app.shelf_dir, app.disks.disks[i].file, name);
    defer app.gpa.free(path);
    const disk = try std.Io.Dir.cwd().readFileAlloc(app.io, path, app.gpa, .limited(shelf.MAX_DISK));
    defer app.gpa.free(disk);
    try isProgram(disk, name);
    var opt = app.opt;
    opt.disk_magic = mc.DISK_MAGIC_PROGRAM;
    const t0 = app.clock();
    const rep = loader.load(app.gpa, app.regs, app.ddr, disk, opt) catch |err| {
        cart.failed(app, i, err);
        if (app.current == null) app.setOpen(true);
        return err;
    };
    app.stats.loaded(app.clock() - t0, rep.fw);
    app.menu.setStatus("{s} running", .{name});
    std.log.info("{s}: {s} off the disk, {d} bytes", .{ app.disks.disks[i].file, name, rep.image_bytes });
}

/// The program's fat disk carries a program (type 0) of that name: the browser runs only those.
fn isProgram(disk: []const u8, name: []const u8) !void {
    const d = try zmd.parse(disk);
    for (0..d.file_count) |k| {
        const f = try d.file(k);
        if (f.kind == map.ZMD_TYPE_WASM and std.mem.eql(u8, f.name, name)) return;
    }
    return error.NotAProgram;
}

fn failed(app: *App, what: []const u8, err: anyerror) void {
    app.req_done = true;
    app.menu.setStatus("{s}: {t}", .{ what, err });
    std.log.warn("cart request: {s}: {t}", .{ what, err });
    app.redraw();
}
