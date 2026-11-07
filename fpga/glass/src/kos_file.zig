// KOS's C: writes on the board (docs/KOS_GEMDOS.md §7, env.kosFileOp): a cart never writes sectors; glass
// writes whole files under the card's /HD through Linux's FAT driver, so the card has one writer. The
// firmware (cycles/bkosfile.c) writes a request block at window end - KOS_FILE_FROM_TOP (map_cart.zig
// KOS_FILE_*); the C: thread (kos_drive.zig) polls it beside the sector block. A whole block (magic, check)
// not yet answered is COPIED out first, its paths and data too, and only the copy is checked and used
// (the cart may rewrite the window meanwhile). The path gate is KFS's (rom/kos/kfs_path.zig); the
// operations are kos_fs.zig's. Around each write the card is remounted read-write, synced, and remounted
// read-only; then the raw reader's cache is dropped and the C: generation word bumped.
const std = @import("std");
const linux = std.os.linux;
const mc = @import("map_cart.zig");
const kp = @import("kos_kfs_path");
const fs = @import("kos_fs.zig");

pub const Op = enum(u32) { gen = 0, write = 1, delete = 2, rename = 3, mkdir = 4, rmdir = 5, setattr = 6, abort = 7, _ };
const FIRST: u32 = 1;
const LAST: u32 = 2;
const SLOTS: u32 = 8;
const MAX_FOLDERS = kp.MAX_NAMES - 1;

/// Where the files go and what wraps a write: the board's /HD and remount, or a test's directory.
pub const Backend = struct {
    root: i32, // an fd on the folder C:\ is (/mnt/sd/HD)
    mount_point: ?[*:0]const u8 = null, // remounted rw for each write, ro after (null: a test's dir)
    after: ?*const fn () void = null, // a write done: the raw sector reader drops its cache
};

/// One request, copied out of the window.
pub const Req = struct {
    op: Op,
    flags: u32,
    slot: u32,
    attr: u32,
    offset: u32,
    path: []const u8,
    path2: []const u8,
    data: []const u8,
};

pub const Server = struct {
    words: []volatile u32, // the cart window, index 0 = CART_CPU_BASE
    be: Backend,
    gen: u32 = 0,
    served: u32 = 0,
    path: [mc.KOS_FILE_PATH_MAX]u8 = undefined,
    path2: [mc.KOS_FILE_PATH_MAX]u8 = undefined,
    data: [mc.KOS_FILE_DATA_MAX]u8 = undefined,

    fn at(self: *Server, from_top: u32) usize {
        return (self.words.len * 4 - from_top) / 4;
    }

    /// One look at the block: a whole request not yet answered is served. True if one was.
    pub fn poll(self: *Server) bool {
        const w = self.words[self.at(mc.KOS_FILE_FROM_TOP)..][0..mc.KOS_FILE_WORDS];
        if (w[mc.KF_MAGIC] != mc.KOS_FILE_MAGIC) return false;
        var s: [mc.KOS_FILE_WORDS]u32 = undefined;
        for (&s, 0..) |*x, i| x.* = w[i]; // the copy: everything below reads only it
        if (s[mc.KF_SEQ] == 0 or s[mc.KF_ACK] == s[mc.KF_SEQ]) return false;
        var check: u32 = mc.KOS_FILE_MAGIC;
        for (s[mc.KF_SEQ .. mc.KF_PATH2_LEN + 1]) |x| check ^= x;
        if (s[mc.KF_CHECK] != ~check) return false; // half-written
        w[mc.KF_TAKEN] = s[mc.KF_SEQ]; // the firmware now waits for the write itself
        w[mc.KF_DONE] = @bitCast(self.serve(&s));
        w[mc.KF_ACK] = s[mc.KF_SEQ];
        self.served +%= 1;
        return true;
    }

    fn serve(self: *Server, s: *const [mc.KOS_FILE_WORDS]u32) i32 {
        const op: Op = @enumFromInt(s[mc.KF_OP]);
        if (op == .gen) return @intCast(self.gen & 0x7FFF_FFFF);
        const r = Req{
            .op = op,
            .flags = s[mc.KF_FLAGS],
            .slot = s[mc.KF_SLOT],
            .attr = s[mc.KF_ATTR],
            .offset = s[mc.KF_OFFSET],
            .path = self.copy(s[mc.KF_PATH], s[mc.KF_PATH_LEN], &self.path) orelse return fs.ERANGE,
            .path2 = self.copy(s[mc.KF_PATH2], s[mc.KF_PATH2_LEN], &self.path2) orelse return fs.ERANGE,
            .data = self.copy(s[mc.KF_DATA], s[mc.KF_LEN], &self.data) orelse return fs.ERANGE,
        };
        if (kp.check(r.path) == null) return fs.EPTHNF; // refused before the card is touched at all
        if (self.be.mount_point) |m| if (!remount(m, true)) return fs.EWRITF;
        const res = run(self.be.root, &r) catch |e| fs.code(e);
        _ = linux.syncfs(self.be.root);
        if (self.be.mount_point) |m| if (!remount(m, false) and !remount(m, false)) std.log.warn("C: the card stays read-write", .{});
        if (self.be.after) |f| f();
        if (res >= 0) {
            self.gen +%= 1;
            self.words[self.at(mc.KOS_CGEN_FROM_TOP)] = self.gen;
        }
        return res;
    }

    /// `n` bytes at window offset `off` into `dst`, or null: too long, or not wholly below the top blocks.
    fn copy(self: *Server, off: u32, n: u32, dst: []u8) ?[]const u8 {
        if (n > dst.len or @as(u64, off) + n > self.words.len * 4 - mc.KOS_FILE_FROM_TOP) return null;
        for (dst[0..n], 0..) |*b, i| {
            const a = off + i;
            b.* = @truncate(self.words[a / 4] >> @intCast(8 * (a % 4)));
        }
        return dst[0..n];
    }
};

fn remount(m: [*:0]const u8, rw: bool) bool {
    const flags: u32 = if (rw) linux.MS.REMOUNT else linux.MS.REMOUNT | linux.MS.RDONLY;
    const rc = linux.mount(null, m, null, flags, 0);
    if (linux.errno(rc) == .SUCCESS) return true;
    std.log.warn("C: remount {s}: {t}", .{ if (rw) "rw" else "ro", linux.errno(rc) });
    return false;
}

/// The request, its path checked and its folder walked: TOS's answer (kfs_ops.zig's, over Linux).
pub fn run(root: i32, r: *const Req) fs.Fail!i32 {
    const p = kp.check(r.path) orelse return error.PathNotFound;
    const dir = try fs.walk(root, p.parent());
    defer _ = linux.close(dir);
    const name = p.last();
    switch (r.op) {
        .write => return save(dir, name, r),
        .abort => {
            if (r.slot >= SLOTS) return error.BadHandle;
            var t: [9]u8 = undefined;
            fs.unlink(dir, temp(r.slot, &t), false) catch {};
            return 0;
        },
        .delete => {
            const k = fs.kind(dir, name, null, null);
            if (k != .file) return if (k == .none or k == .dir) error.FileNotFound else error.AccessDenied;
            if (fs.readOnly(dir, name)) return error.AccessDenied;
            try fs.unlink(dir, name, false);
        },
        .rename => {
            const p2 = kp.check(r.path2) orelse return error.PathNotFound;
            const to = try fs.walk(root, p2.parent());
            defer _ = linux.close(to);
            const k = fs.kind(dir, name, null, null);
            if (k == .none) return error.FileNotFound;
            if (k == .other or fs.kind(to, p2.last(), null, null) != .none) return error.AccessDenied;
            if (k == .dir and kp.isPrefix(p.slice(), p2.parent())) return error.AccessDenied; // into itself
            try fs.rename(dir, name, to, p2.last());
            fs.syncDir(to);
        },
        .mkdir => {
            if (p.n > MAX_FOLDERS) return error.PathNotFound;
            if (fs.kind(dir, name, null, null) != .none) return error.AccessDenied;
            try fs.mkdir(dir, name);
        },
        .rmdir => {
            if (fs.kind(dir, name, null, null) != .dir) return error.PathNotFound;
            try fs.unlink(dir, name, true);
        },
        .setattr => {
            const k = fs.kind(dir, name, null, null);
            if (k == .none) return error.FileNotFound;
            if (k == .other or r.attr & ~@as(u32, 0x27) != 0) return error.AccessDenied;
            const a = try fs.setAttr(dir, name, r.attr);
            fs.syncDir(dir);
            return @intCast(a);
        },
        else => return error.Range,
    }
    fs.syncDir(dir);
    return 0;
}

fn temp(slot: u32, out: *[9]u8) []const u8 {
    out.* = "~KOS0.TMP".*;
    out[4] = '0' + @as(u8, @intCast(slot));
    return out;
}

/// A save's step, as KFS takes it: FIRST makes the temp file afresh, the data lands at `offset` (synced),
/// LAST renames it over the file (Linux replaces the old one) and sets its attributes.
fn save(dir: i32, name: []const u8, r: *const Req) fs.Fail!i32 {
    if (r.slot >= SLOTS) return error.BadHandle;
    const k = fs.kind(dir, name, null, null);
    if (k == .dir or k == .other or fs.readOnly(dir, name)) return error.AccessDenied;
    var t: [9]u8 = undefined;
    const tn = temp(r.slot, &t);
    try fs.writeAt(dir, tn, r.flags & FIRST != 0, r.offset, r.data);
    if (r.flags & LAST == 0) return 0;
    try fs.rename(dir, tn, dir, name);
    if (r.attr & 0x07 != 0) _ = try fs.setAttr(dir, name, r.attr);
    fs.syncDir(dir);
    return 0;
}
