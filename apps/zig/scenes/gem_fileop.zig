// --------------------------------------------------------------------------
// The desktop's file operations, the shell's half (docs/GEM5_PLAN.md P1.1). The ROM's desktop
// posts a copy, move, delete, rename or New Folder in its mailbox (rom/sdk/deskop.zig) and
// reaches no disk; the shell carries it out through KOS GEMDOS, ONE step a frame (an entry, a
// folder created or deleted, a 32 KB chunk), so on the board, where every write is a remount
// and a sync of the card (seconds), the desktop stays alive and its box counts down between
// them. First the count (gem_fileop_count.zig), then the walk (gem_fileop_walk.zig) and the
// copies (gem_fileop_copy.zig). A name that exists where an item goes is asked about (NAME
// CONFLICT); a move on one drive is a Frename of each item (one request, the source never at
// risk); a move to another drive copies, checks the copy, then deletes the source, and a
// source it cannot delete (drive A is write-protected) is kept and reported. At the end C: is
// read afresh (gem_fat.loadC): its listing changed.
// --------------------------------------------------------------------------
const std = @import("std");
const rom = @import("rom_sdk");
const gemdos = @import("kos_gemdos");
const op = rom.deskop;
const fp = @import("gem_fileop_path.zig");
const count = @import("gem_fileop_count.zig");
const walk = @import("gem_fileop_walk.zig");
const copy = @import("gem_fileop_copy.zig");
const ent = @import("gem_fileop_entry.zig");
const err = gemdos.err;

var running = false; // the walk was set up for the box's operation
var cur: ?fp.Entry = null; // the entry in hand (kept across a NAME CONFLICT)
var as_buf: [op.NAME_MAX]u8 = undefined; // the name it gets where it goes (the conflict's answer)
var as_len: usize = 0;
var replace = false; // the answer kept the clashing name: the item replaces what is there

/// Once a frame, after the desktop's: the phase the shell answers.
pub fn tick() void {
    const b = rom.Desktop.fileOp() orelse return;
    switch (b.phase) {
        op.COUNT => counted(b),
        op.RUN => step(b),
        op.ANSWER => answered(b),
        else => {}, // idle, counted, conflict, done: the ROM's move
    }
}

fn counted(b: *op.Box) void {
    running = false; // a new operation: its walk starts at its first item
    if (b.op != @intFromEnum(op.Op.copy) and b.op != @intFromEnum(op.Op.move) and b.op != @intFromEnum(op.Op.delete)) return finish(b, err.EINVFN);
    var c = count.Counts{};
    var p = fp.Path{};
    for (0..b.n_items) |i| {
        p.set(b.srcPath());
        if (p.push(b.item(i), false)) c.add(count.item(p.str()));
    }
    if (c.code < 0) return finish(b, c.code);
    b.folders = c.folders;
    b.files = c.files;
    b.bytes = c.bytes;
    b.folders_left = c.folders;
    b.files_left = c.files;
    b.phase = op.COUNTED;
    bump(b);
}

fn step(b: *op.Box) void {
    switch (b.op) {
        @intFromEnum(op.Op.mkdir) => return finish(b, mkdir(b)),
        @intFromEnum(op.Op.rename) => return finish(b, rename(b)),
        else => {},
    }
    if (!running) begin(b);
    if (copy.active()) return fileStep(b);
    if (cur == null) switch (walk.next(b, ent.folderDone)) {
        .got => |e| cur = e,
        .wait => return,
        .end => return finish(b, 0),
        .fail => |code| return finish(b, code),
    };
    entry(b, &cur.?);
}

fn begin(b: *op.Box) void {
    walk.reset(b);
    cur = null;
    as_len = 0;
    replace = false;
    running = true;
}

fn mkdir(b: *op.Box) i32 {
    var p = fp.Path{};
    p.set(b.dstPath());
    if (!p.push(b.nameSlice(), false)) return err.EPTHNF;
    return gemdos.dos().Dcreate(p.str());
}

fn rename(b: *op.Box) i32 {
    var from = fp.Path{};
    var to = fp.Path{};
    from.set(b.srcPath());
    to.set(b.srcPath());
    if (!from.push(b.item(0), false) or !to.push(b.nameSlice(), false)) return err.EPTHNF;
    return gemdos.dos().Frename(0, from.str(), to.str());
}

// One entry: deleted, created where it goes, copied, or (a move on one drive) renamed there.
fn entry(b: *op.Box, e: *const fp.Entry) void {
    const name = if (as_len > 0) as_buf[0..as_len] else e.slice();
    var to = walk.dst;
    var from = walk.src;
    if (!from.push(e.slice(), false)) return finish(b, err.EPTHNF);
    if (b.op != @intFromEnum(op.Op.delete) and !to.push(name, false)) return finish(b, err.EPTHNF);
    if (b.op != @intFromEnum(op.Op.delete) and !replace and fp.exists(to.str())) return conflict(b, name);
    const code = switch (b.op) {
        @intFromEnum(op.Op.delete) => ent.delete(b, e, from.str()),
        @intFromEnum(op.Op.move) => if (ent.sameDrive(b) and walk.atTop()) ent.rename(b, from.str(), to.str(), replace) else ent.copyTo(b, e, name, from.str(), to.str(), replace),
        else => ent.copyTo(b, e, name, from.str(), to.str(), replace),
    };
    cur = null;
    as_len = 0;
    replace = false;
    if (code < 0) finish(b, code) else bump(b);
}

// A file being copied: the next chunk; when it is whole, a move deletes its source.
fn fileStep(b: *op.Box) void {
    const r = copy.chunk();
    if (r == copy.MORE) return;
    if (r < 0) return finish(b, r);
    b.files_left -|= 1;
    if (b.op == @intFromEnum(op.Op.move)) {
        if (!copy.verified()) return finish(b, err.EWRITF);
        if (gemdos.dos().Fdelete(copy.src.str()) < 0) b.kept += 1;
    }
    bump(b);
}

fn conflict(b: *op.Box, name: []const u8) void {
    b.setName(name);
    b.phase = op.CONFLICT;
    bump(b);
}

// NAME CONFLICT answered: the entry in hand goes on under the name given (the same one: it
// replaces what is there), or is left out, or the operation stops.
fn answered(b: *op.Box) void {
    const e = cur orelse return finish(b, 0);
    switch (b.answer) {
        @intFromEnum(op.Answer.rename) => {
            const nm = b.nameSlice()[0..@min(b.name_len, op.NAME_MAX - 1)];
            const clash = if (as_len > 0) as_buf[0..as_len] else e.slice();
            replace = std.mem.eql(u8, nm, clash);
            @memcpy(as_buf[0..nm.len], nm);
            as_len = nm.len;
        },
        @intFromEnum(op.Answer.skip) => {
            var from = walk.src;
            if (from.push(e.slice(), false)) _ = ent.skip(b, &e, from.str());
            cur = null;
            as_len = 0;
        },
        else => return finish(b, 0),
    }
    b.phase = op.RUN;
    bump(b);
}

/// The operation is over (`code`: 0, or the GEMDOS error that stopped it): files closed, C:
/// read afresh for the desktop, the box told.
fn finish(b: *op.Box, code: i32) void {
    _ = copy.drop(0);
    running = false;
    cur = null;
    as_len = 0;
    _ = @import("gem_fat.zig").loadC();
    b.status = code;
    b.phase = op.DONE;
    bump(b);
}

fn bump(b: *op.Box) void {
    b.seq +%= 1;
}
