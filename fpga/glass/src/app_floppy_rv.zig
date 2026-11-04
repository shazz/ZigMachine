// A floppy program's own board image (KOS F3b, docs/KOS_FAT.md; Matt, 31 Oct: the floppy must not
// need the SD card). Beside NAME.WSM, NAME.RV carries the program's board image in a small
// container that says which program it was built from:
//
//   +0  "ZMRV"                  magic
//   +4  u32 LE  1               the container's version
//   +8  [32]u8                  SHA-256 of the program's wasm (unpacked: what a .WSM depacks to)
//   +40 ...                     the board image, as progs/by-hash holds it (ZX0-packed lean cart)
//
// The hash is checked here (a .RV left over from another build of the program is refused, never
// run against the wrong wasm); the image's ABI is checked where every board image's is
// (plan.planOver -> system.check: the cart header's version against the system's table).
// fpga/tools/kos_rv.py writes the container.
const std = @import("std");

pub const MAGIC = "ZMRV";
pub const VERSION: u32 = 1;
pub const HEAD = 40;
pub const Error = error{ NotABoardImage, RvVersion, RvForAnotherProgram };

/// The board image inside `rv`, if `rv` is a container built from `wasm`.
pub fn boardImage(rv: []const u8, wasm: []const u8) Error![]const u8 {
    if (rv.len <= HEAD or !std.mem.eql(u8, rv[0..4], MAGIC)) return error.NotABoardImage;
    if (std.mem.readInt(u32, rv[4..8], .little) != VERSION) return error.RvVersion;
    var sum: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(wasm, &sum, .{});
    if (!std.mem.eql(u8, rv[8..40], &sum)) return error.RvForAnotherProgram;
    return rv[HEAD..];
}

/// NAME.RV for NAME.WSM (any extension): the same 8.3 base.
pub fn rvName(buf: *[12]u8, wsm: []const u8) []const u8 {
    const base = wsm[0 .. std.mem.lastIndexOfScalar(u8, wsm, '.') orelse wsm.len];
    const n = @min(base.len, 8);
    @memcpy(buf[0..n], base[0..n]);
    @memcpy(buf[n..][0..3], ".RV");
    return buf[0 .. n + 3];
}

/// A container for `board` built from `wasm` (the tests' writer; kos_rv.py is the real one).
pub fn wrap(gpa: std.mem.Allocator, wasm: []const u8, board: []const u8) ![]u8 {
    const out = try gpa.alloc(u8, HEAD + board.len);
    @memcpy(out[0..4], MAGIC);
    std.mem.writeInt(u32, out[4..8], VERSION, .little);
    std.crypto.hash.sha2.Sha256.hash(wasm, out[8..40], .{});
    @memcpy(out[HEAD..], board);
    return out;
}

test "a container is opened only for the wasm it was built from, at its version" {
    const gpa = std.testing.allocator;
    const rv = try wrap(gpa, "the wasm", "the image");
    defer gpa.free(rv);
    try std.testing.expectEqualStrings("the image", try boardImage(rv, "the wasm"));
    try std.testing.expectError(error.RvForAnotherProgram, boardImage(rv, "another wasm"));
    rv[4] = 2;
    try std.testing.expectError(error.RvVersion, boardImage(rv, "the wasm"));
    rv[0] = 'X';
    try std.testing.expectError(error.NotABoardImage, boardImage(rv, "the wasm"));
    try std.testing.expectError(error.NotABoardImage, boardImage(rv[0..HEAD], "the wasm"));
    var buf: [12]u8 = undefined;
    try std.testing.expectEqualStrings("PROG.RV", rvName(&buf, "PROG.WSM"));
    try std.testing.expectEqualStrings("ABCDEFGH.RV", rvName(&buf, "ABCDEFGH.WSM"));
}
