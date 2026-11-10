// --------------------------------------------------------------------------
// The desktop's file operations, the ROM <-> shell mailbox (docs/GEM5_PLAN.md P1.1). The ROM
// desktop decides an operation (a drag, the TRASH, Show Info, New Folder) but reaches no disk:
// rom.wasm imports only hwVideoBase and hwBlit. So, as Save Desktop does, it writes the request
// here and the shell cart (apps/zig/scenes/gem_fileop*.zig) carries it out through KOS GEMDOS,
// writing the counts and the answer back. One block in the ROM's memory (deskFileOp() is its
// address: the memory is shared), read by both sides; this file is the ONLY definition of it,
// imported by the ROM (rom/gem/desktop/fileop.zig) and by carts through rom_sdk.
//
// The phases, and who moves each one:
//   idle --ROM--> count   the shell walks the sources (Fsfirst/Fsnext): folders, files, bytes
//   count --shell--> counted   the ROM shows the confirm box with those counts
//   counted --ROM--> run       (OK; Cancel: back to idle) the shell works, a step a frame,
//                              counting folders_left / files_left down
//   run --shell--> conflict    a name exists where the item goes: `name` holds it
//   conflict --ROM--> answer   rename (`name` = the new one: the same one replaces), skip, stop
//   answer --shell--> run
//   run --shell--> done        `status` 0 or the GEMDOS error that stopped it; C: re-read
//   done --ROM--> idle         the ROM re-points its C: windows, raises an alert on an error
// mkdir and rename skip the count and the box: the ROM posts them at run.
// --------------------------------------------------------------------------
const std = @import("std");

pub const PATH_MAX = 128; // a GEMDOS path: "C:\A\B\" (KOS: 9 deep, 127 bytes)
pub const NAME_MAX = 14; // a DTA's name field: 8.3 + NUL
pub const MAX_ITEMS = 48; // the desktop's selection: MAX_FILES files + MAX_FOLDERS folders

pub const IDLE: u32 = 0;
pub const COUNT: u32 = 1;
pub const COUNTED: u32 = 2;
pub const RUN: u32 = 3;
pub const CONFLICT: u32 = 4;
pub const ANSWER: u32 = 5;
pub const DONE: u32 = 6;

/// deskKey(code | KEY_RELEASE): the key came up (the shell's keyUp; above glass's KEY_CODE_MASK).
pub const KEY_RELEASE: u32 = 0x8000_0000;

pub const Op = enum(u32) { none = 0, copy = 1, move = 2, delete = 3, mkdir = 4, rename = 5 };
pub const Answer = enum(u32) { none = 0, rename = 1, skip = 2, stop = 3 };

pub const Box = extern struct {
    phase: u32 = IDLE,
    op: u32 = 0, // Op
    status: i32 = 0, // done: 0, or the GEMDOS error that stopped the operation
    kept: u32 = 0, // done: a move's sources it could not delete (kept where they were)
    answer: u32 = 0, // Answer, at ANSWER
    seq: u32 = 0, // the shell bumps it at every change it makes: the ROM repaints
    folders: u32 = 0, // counted: the totals
    files: u32 = 0,
    bytes: u32 = 0,
    folders_left: u32 = 0, // run: what is still to do, counted down live
    files_left: u32 = 0,
    n_items: u32 = 0,
    src_len: u32 = 0,
    dst_len: u32 = 0,
    name_len: u32 = 0,
    src: [PATH_MAX]u8 = [_]u8{0} ** PATH_MAX, // copy/move/delete/rename: the items' folder, "C:\NET\"
    dst: [PATH_MAX]u8 = [_]u8{0} ** PATH_MAX, // copy/move: where they go; mkdir: the new folder's parent
    name: [16]u8 = [_]u8{0} ** 16, // rename: the new name; mkdir: the folder's; conflict: the clash
    items: [MAX_ITEMS][NAME_MAX]u8 = [_][NAME_MAX]u8{[_]u8{0} ** NAME_MAX} ** MAX_ITEMS, // NUL-terminated

    pub fn srcPath(b: *const Box) []const u8 {
        return b.src[0..@min(b.src_len, PATH_MAX)];
    }
    pub fn dstPath(b: *const Box) []const u8 {
        return b.dst[0..@min(b.dst_len, PATH_MAX)];
    }
    pub fn nameSlice(b: *const Box) []const u8 {
        return b.name[0..@min(b.name_len, b.name.len)];
    }
    pub fn item(b: *const Box, i: usize) []const u8 {
        const s = &b.items[i];
        return s[0 .. std.mem.indexOfScalar(u8, s, 0) orelse NAME_MAX];
    }
    pub fn setName(b: *Box, s: []const u8) void {
        const n = @min(s.len, b.name.len);
        @memcpy(b.name[0..n], s[0..n]);
        b.name_len = @intCast(n);
    }
    /// One more item (8.3 at most): false when the box is full or the name too long.
    pub fn addItem(b: *Box, s: []const u8) bool {
        if (b.n_items >= MAX_ITEMS or s.len >= NAME_MAX) return false;
        const slot = &b.items[b.n_items];
        @memset(slot, 0);
        @memcpy(slot[0..s.len], s);
        b.n_items += 1;
        return true;
    }
};

comptime {
    std.debug.assert(@offsetOf(Box, "src") == 60 and @sizeOf(Box) == 60 + 2 * PATH_MAX + 16 + MAX_ITEMS * NAME_MAX);
}
