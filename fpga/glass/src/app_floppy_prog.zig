// A program off the real floppy in drive A (docs/KOS_FAT.md F3, Matt: .WSM on a real floppy
// launches). GEM asks for it by name (request 3); a program is wasm and the board runs native code,
// so glass finds its board image by what the program IS: it reads the file off the floppy image
// with KOS's own reader (rom/kos/fat.zig, breadth first, the desktop's listing order), depacks it if
// it is ZX0-packed, hashes the wasm (SHA-256) and loads zigmachine/progs/by-hash/<hex>.rv32
// (tools/glass_shelf.py writes one per cart it has an image of). The floppy goes back in DDR beside
// it with DISK_MAGIC_PROGRAM, as a data disk's program gets its disk. No image: the desktop keeps
// running and the status says so.
const std = @import("std");
const fat = @import("kos_fat");
const mc = @import("map_cart.zig");
const plan = @import("plan.zig");
const loader = @import("loader.zig");
const shelf = @import("shelf.zig");
const floppy = @import("app_floppy_a.zig");
const App = @import("app.zig").App;

pub const BY_HASH = "progs/by-hash";
pub const Error = error{ NoSuchFile, NoBoardImage };

fn read(ctx: *anyopaque, n: u32, dst: *[fat.SECTOR]u8) bool {
    const img: *const []const u8 = @ptrCast(@alignCast(ctx));
    const at = @as(usize, n) * fat.SECTOR;
    if (at + fat.SECTOR > img.len) return false;
    @memcpy(dst, img.*[at..][0..fat.SECTOR]);
    return true;
}

/// The bytes of the first file named `name` (8.3), breadth first; owned by the caller.
pub fn fileOf(gpa: std.mem.Allocator, img: []const u8, name: []const u8) ![]u8 {
    var src = img;
    var v = try fat.Volume.mount(read, @ptrCast(&src));
    var dirs: [16]fat.Dir = undefined;
    dirs[0] = v.root();
    var n_dirs: usize = 1;
    var q: usize = 0;
    var entries: [64]fat.Entry = undefined;
    while (q < n_dirs) : (q += 1) {
        const n = try v.list(dirs[q], &entries);
        for (entries[0..n]) |*e| {
            if (e.isDir()) {
                if (n_dirs < dirs.len) dirs[n_dirs] = .{ .cluster = e.cluster };
                n_dirs = @min(n_dirs + 1, dirs.len);
            } else if (std.mem.eql(u8, e.nameSlice(), name)) {
                const out = try gpa.alloc(u8, e.size);
                errdefer gpa.free(out);
                if (try v.read(e, 0, out) != e.size) return error.NoSuchFile;
                return out;
            }
        }
    }
    return error.NoSuchFile;
}

/// progs/by-hash/<sha256 of the program's wasm>.rv32 under the card's shelf directory.
pub fn imagePath(gpa: std.mem.Allocator, dir: []const u8, wasm: []const u8) ![]u8 {
    var sum: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(wasm, &sum, .{});
    const hex = std.fmt.bytesToHex(sum, .lower);
    const file = try std.fmt.allocPrint(gpa, "{s}.rv32", .{&hex});
    defer gpa.free(file);
    return std.fs.path.join(gpa, &.{ dir, BY_HASH, file });
}

/// Request 3 with the real floppy in drive A.
pub fn run(app: *App, name: []const u8) !void {
    if (!@import("app_request.zig").validName(name)) return error.BadProgramName;
    const img = try floppy.read(app);
    defer app.gpa.free(img);
    const file = try fileOf(app.gpa, img, name);
    defer app.gpa.free(file);
    const wasm = try plan.unpack(app.gpa, file, shelf.MAX_DISK); // a packed program is depacked first
    defer app.gpa.free(wasm);
    const path = try imagePath(app.gpa, app.shelf_dir, wasm);
    defer app.gpa.free(path);
    const board = std.Io.Dir.cwd().readFileAlloc(app.io, path, app.gpa, .limited(shelf.MAX_DISK)) catch |err|
        return if (err == error.FileNotFound) error.NoBoardImage else err;
    defer app.gpa.free(board);
    var p = try plan.planOver(app.gpa, board, img, app.ddr.bytes(), mc.DISK_MAGIC_PROGRAM, app.opt.system);
    defer p.deinit(app.gpa);
    var opt = app.opt;
    opt.disk_magic = mc.DISK_MAGIC_PROGRAM;
    const t0 = app.clock();
    const rep = try loader.start(app.regs, app.ddr, &p, opt);
    app.stats.loaded(app.clock() - t0, rep.fw);
    app.disk_from = rep.disk_from;
    app.menu.setStatus("{s} running", .{name});
}
