// --------------------------------------------------------------------------
// GEMDOS's writes (docs/KOS_GEMDOS.md §7), methods of gemdos.Dos: Fcreate, Fwrite, and the write
// half of Fclose and Fseek. A cart never writes sectors: a save goes to the host whole, through
// env.kosFileOp (kfs_abi.zig), which writes a temporary file and renames it over the real one at
// Fclose. Fwrite buffers DATA_MAX (32 KB) in the cart, one buffer for every handle (the handle that
// last wrote owns it), so a picture is ONE request (~0.5 ms on the board + the card's own time).
// Fcreate checks what it can locally (the folder exists, the name is free or a plain file) and sends
// nothing: the file appears at the first request (a full buffer or Fclose), whole at Fclose.
// --------------------------------------------------------------------------
const std = @import("std");
const gemdos = @import("gemdos.zig");
const abi = @import("kfs_abi.zig");
const err = @import("gemdos_err.zig");
const wops = @import("gemdos_wops.zig");
const Dos = gemdos.Dos;

const SETTABLE: i32 = 0x27; // read-only, hidden, system, archive

/// A file being written: where it goes (its C: path, canonical), how far it got, what failed.
pub const WFile = struct {
    path: [abi.PATH_MAX + 1]u8 = undefined,
    path_len: u8 = 0,
    attr: u32 = 0,
    pos: u32 = 0,
    size: u32 = 0,
    boff: u32 = 0, // the buffer holds bytes boff .. boff + blen (when this handle owns it)
    blen: u32 = 0,
    sent: bool = false, // the temp file exists at the host (FIRST went)
    failed: i32 = 0, // the first error a request answered: every later call answers it
};

/// A new file (or an old one to be replaced) at `path`, open for writing: a handle.
pub fn Fcreate(dos: *Dos, path: []const u8, attr: i32) i32 {
    if (attr & ~SETTABLE != 0) return err.EACCDN; // no labels, no folders (Dcreate makes those)
    var t: wops.Target = undefined;
    wops.resolve(dos, path, &t) catch |x| return err.code(x);
    if (t.entry) |e| if (e.isDir() or e.attr & 0x01 != 0) return err.EACCDN;
    for (&dos.files, 0..) |*f, i| if (!f.used) {
        f.* = .{ .used = true, .drive = t.letter, .writing = true };
        const w = &dos.wfiles[i];
        w.* = .{ .attr = @intCast(attr), .path_len = @intCast(t.len) };
        @memcpy(w.path[0..t.len], t.path[0..t.len]);
        return gemdos.FIRST_HANDLE + @as(i32, @intCast(i));
    };
    return err.ENHNDL;
}

/// `count` bytes of `buf` at the position: the count (buffered; an earlier request's error if one failed).
pub fn Fwrite(dos: *Dos, h: i32, count: i32, buf: [*]const u8) i32 {
    const i = slot(dos, h) orelse return err.EIHNDL;
    if (!dos.files[i].writing) return err.EACCDN; // a file opened for reading
    if (count < 0) return err.ERANGE;
    const w = &dos.wfiles[i];
    var done: u32 = 0;
    while (done < count and w.failed == 0) {
        if (dos.wowner != i or w.pos < w.boff or w.pos > w.boff + w.blen or w.pos - w.boff == abi.DATA_MAX) {
            take(dos, i);
            w.boff = w.pos;
        }
        const at = w.pos - w.boff;
        const n = @min(@as(u32, @intCast(count)) - done, abi.DATA_MAX - at);
        @memcpy(dos.wbuf[at..][0..n], buf[done..][0..n]);
        w.blen = @max(w.blen, at + n);
        w.pos += n;
        w.size = @max(w.size, w.pos);
        done += n;
    }
    return if (w.failed != 0) w.failed else @intCast(done);
}

/// Handle `i` owns the buffer, empty: the owner's bytes (if another's, or its own) sent first.
fn take(dos: *Dos, i: usize) void {
    if (dos.wowner >= 0) flush(dos, @intCast(dos.wowner), false);
    dos.wowner = @intCast(i);
}

/// Handle `i`'s buffered bytes sent (and, `last`, the file committed). Its error kept.
fn flush(dos: *Dos, i: usize, last: bool) void {
    const w = &dos.wfiles[i];
    const owns = dos.wowner == i;
    const len = if (owns) w.blen else 0;
    if (w.failed != 0 or (len == 0 and !last)) return;
    var req = abi.Req{
        .op = @intFromEnum(abi.Op.write),
        .flags = (if (w.sent) 0 else abi.FIRST) | (if (last) abi.LAST else 0),
        .slot = @intCast(i),
        .attr = w.attr,
        .offset = if (owns) w.boff else w.size,
        .len = len,
    };
    const r = wops.send(dos, dos.files[i].drive, &req, w.path[0..w.path_len], "", dos.wbuf[0..len]);
    if (r < 0) w.failed = r else w.sent = true;
    if (owns) w.blen = 0;
}

/// The write half of Fclose: the rest sent and the file committed, or the half-written temp dropped.
pub fn close(dos: *Dos, i: usize) i32 {
    const w = &dos.wfiles[i];
    flush(dos, i, true);
    if (dos.wowner == i) dos.wowner = -1;
    if (w.failed != 0 and w.sent) {
        var req = abi.Req{ .op = @intFromEnum(abi.Op.abort), .slot = @intCast(i) };
        _ = wops.send(dos, dos.files[i].drive, &req, w.path[0..w.path_len], "", "");
    }
    return w.failed;
}

/// The write half of Fseek: anywhere in 0 .. the size written so far.
pub fn seek(dos: *Dos, i: usize, offset: i32, mode: i32) i32 {
    const w = &dos.wfiles[i];
    const base: i64 = switch (mode) {
        0 => 0,
        1 => w.pos,
        2 => w.size,
        else => return err.EINVFN,
    };
    const to = base + offset;
    if (to < 0 or to > w.size) return err.ERANGE;
    w.pos = @intCast(to);
    return @intCast(to);
}

fn slot(dos: *Dos, h: i32) ?usize {
    if (h < gemdos.FIRST_HANDLE or h >= gemdos.FIRST_HANDLE + gemdos.MAX_FILES) return null;
    const i: usize = @intCast(h - gemdos.FIRST_HANDLE);
    return if (dos.files[i].used) i else null;
}

comptime {
    std.debug.assert(gemdos.MAX_FILES == abi.SLOTS);
}
