// --------------------------------------------------------------------------
// KFS, the C: image writer (docs/KOS_GEMDOS.md §7): env.kosFileOp's host half where C: is an image,
// on the page (docs/kos-cfs.wasm, kfs_wasm.zig) and in the native host (the same wasm, wasm2c'd).
// On the board glass serves the same requests over Linux's own FAT driver (fpga/glass/src/
// kos_file.zig); both check the path with kfs_path.zig and answer the same TOS codes.
//
// It edits a FAT12/16/32 volume through a sector device, mounted afresh per request (the image may
// have been swapped; a mount is one sector). C:\ is the volume's HD folder. Files are saved through a
// temporary name and renamed over their own at the last write (kfs_abi.zig); deleting, renaming and
// folders are single requests. Every request that changed the disk bumps `gen`.
// --------------------------------------------------------------------------
const std = @import("std");
const fat = @import("fat.zig");
const abi = @import("kfs_abi.zig");
const kp = @import("kfs_path.zig");
const kf = @import("kfs_fat.zig");
const kd = @import("kfs_dir.zig");
const ops = @import("kfs_ops.zig");
const E = @import("gemdos_err.zig");

pub const Dev = kf.Dev;

/// What one request carries, the bytes already copied out of the cart (the host's own copy).
pub const Request = struct {
    op: abi.Op,
    flags: u32 = 0,
    slot: u32 = 0,
    attr: u32 = 0,
    offset: u32 = 0,
    path: []const u8 = "",
    path2: []const u8 = "",
    data: []const u8 = "",
};

pub const Server = struct {
    gen: u32 = 0,
    stamp: [2]u16 = .{ 0, (2026 - 1980) << 9 | 1 << 5 | 1 }, // DOS time, date: 1 Jan 2026 (deterministic)
    root_name: []const u8 = "HD",

    /// A TOS code: >= 0 done (setattr: the attributes, gen: the generation), < 0 a GEMDOS error.
    pub fn serve(srv: *Server, dev: Dev, r: *const Request) i32 {
        if (r.op == .gen) return @intCast(srv.gen & 0x7FFF_FFFF);
        var d = kf.Disk.mount(dev) catch return E.EDRIVE;
        const top = srv.topOf(&d) orelse return E.EDRIVE;
        const res = srv.run(&d, top, r) catch |x| return code(x);
        if (res >= 0) srv.gen +%= 1;
        return res;
    }

    fn topOf(srv: *Server, d: *kf.Disk) ?fat.Dir {
        const name = kd.nameOf(srv.root_name);
        const s = (kd.find(d, d.v.root(), &name) catch return null) orelse return null;
        if (!s.isDir() or s.cluster() < 2) return null;
        return .{ .cluster = s.cluster() };
    }

    fn run(srv: *Server, d: *kf.Disk, top: fat.Dir, r: *const Request) Fail!i32 {
        const p = kp.check(r.path) orelse return error.PathNotFound;
        const parent = try folder(d, top, p.parent());
        var c = ops.Ctx{ .d = d, .top = top, .stamp = srv.stamp, .parent = parent, .p = &p };
        try d.forgetFsinfo();
        return switch (r.op) {
            .write => ops.write(&c, r.flags, r.slot, r.attr, r.offset, r.data),
            .abort => ops.abort(&c, r.slot),
            .delete => ops.delete(&c),
            .rename => blk: {
                const p2 = kp.check(r.path2) orelse return error.PathNotFound;
                break :blk ops.rename(&c, &p2, try folder(d, top, p2.parent()));
            },
            .mkdir => ops.mkdir(&c),
            .rmdir => ops.rmdir(&c),
            .setattr => ops.setattr(&c, r.attr),
            else => error.InvalidFunction,
        };
    }
};

pub const Fail = ops.Fail;

/// The folder `names` lead to from `top`, or PathNotFound.
pub fn folder(d: *kf.Disk, top: fat.Dir, names: []const []const u8) Fail!fat.Dir {
    var at = top;
    for (names) |n| {
        const name = kd.nameOf(n);
        const s = (try kd.find(d, at, &name)) orelse return error.PathNotFound;
        if (!s.isDir() or s.cluster() < 2) return error.PathNotFound;
        at = .{ .cluster = s.cluster() };
    }
    return at;
}

fn code(x: Fail) i32 {
    return switch (x) {
        error.PathNotFound => E.EPTHNF,
        error.FileNotFound => E.EFILNF,
        error.AccessDenied => E.EACCDN,
        error.BadHandle => E.EIHNDL,
        error.Range => E.ERANGE,
        error.InvalidFunction => E.EINVFN,
        error.Full, error.Io => E.EWRITF,
        error.Corrupt, error.Unsupported => E.EREADF,
    };
}
