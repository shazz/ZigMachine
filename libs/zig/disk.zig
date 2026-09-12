// --------------------------------------------------------------------------
// Disk — the MACHINE's own view of the mounted floppy. The host is a drive: it
// hands over one 512-byte block when asked (zigos.readBlock) and knows nothing
// else. Finding a file and reading it is done here, in wasm, so a program loads
// from disc the way it would on real hardware instead of having the page fetch
// and decode things on its behalf.
//
// Layouts (docs/FLOPPY_DISK.md), both detected by the "ZMDISK" magic:
//   v1  descriptor at $000  ·  file count $2E4  ·  FAT $300
//   v2  descriptor at $400  ·  file count $4F4  ·  FAT $800   (boot sector at $0)
// A FAT entry is 32 bytes: name[16], start u32, len u32, type u8 — `start` is a
// BYTE offset into the image, not a block number.
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos.zig");

pub const BLOCK: u32 = 512;
pub const ENTRY: u32 = 32;
const MAGIC = "ZMDISK";

pub const Entry = struct { start: u32, len: u32, kind: u8 };

// Where this disk keeps its file table.
pub const Layout = struct { count: u16, fat: u32 };

const V1 = struct { desc: u32 = 0x000, count: u32 = 0x2e4, fat: u32 = 0x300 };
const V2 = struct { desc: u32 = 0x400, count: u32 = 0x4f4, fat: u32 = 0x800 };

var scratch: [BLOCK]u8 = undefined;

// Read the 512-byte block containing `off` into the scratch buffer and return the
// slice starting at that offset (empty if the drive has nothing there).
fn at(off: u32) []const u8 {
    const n = zg.readBlock(off / BLOCK, &scratch);
    if (n <= 0) return &.{};
    const within = off % BLOCK;
    const got: u32 = @intCast(n);
    if (within >= got) return &.{};
    return scratch[within..got];
}

fn magicAt(off: u32) bool {
    const s = at(off);
    return s.len >= MAGIC.len and std.mem.eql(u8, s[0..MAGIC.len], MAGIC);
}

// Identify the mounted disk. Probes v2 first: a v2 image starts with an
// executable boot sector, so only its descriptor at $400 carries the magic.
pub fn mount() ?Layout {
    const v2 = V2{};
    if (magicAt(v2.desc)) return .{ .count = u16At(v2.count), .fat = v2.fat };
    const v1 = V1{};
    if (magicAt(v1.desc)) return .{ .count = u16At(v1.count), .fat = v1.fat };
    return null; // no disk in the drive, or not a ZigMachine disk
}

fn u16At(off: u32) u16 {
    const s = at(off);
    if (s.len < 2) return 0;
    return std.mem.readInt(u16, s[0..2], .little);
}

// The FAT entry `i`, read straight off the disk.
pub fn entryAt(lay: Layout, i: u16) ?struct { name: [16]u8, e: Entry } {
    if (i >= lay.count) return null;
    const s = at(lay.fat + @as(u32, i) * ENTRY);
    if (s.len < ENTRY) return null;
    var name: [16]u8 = undefined;
    @memcpy(&name, s[0..16]);
    return .{ .name = name, .e = .{
        .start = std.mem.readInt(u32, s[0x10..0x14], .little),
        .len = std.mem.readInt(u32, s[0x14..0x18], .little),
        .kind = s[0x18],
    } };
}

// Look a file up by name (NUL-padded in the FAT, compared case-sensitively as
// the images are written upper-case).
pub fn find(lay: Layout, name: []const u8) ?Entry {
    var i: u16 = 0;
    while (i < lay.count) : (i += 1) {
        const ent = entryAt(lay, i) orelse continue;
        if (std.mem.eql(u8, trimName(&ent.name), name)) return ent.e;
    }
    return null;
}

fn trimName(raw: []const u8) []const u8 {
    const end = std.mem.indexOfScalar(u8, raw, 0) orelse raw.len;
    return raw[0..end];
}

// Stream a file into `dst`, one block at a time — the machine never holds the
// disk. Returns how many bytes landed (capped by dst). Handles a file whose
// start is not block-aligned, so nothing here assumes the writer's padding.
pub fn read(e: Entry, dst: []u8) usize {
    const want: usize = @min(@as(usize, e.len), dst.len);
    var done: usize = 0;
    while (done < want) {
        const off: u32 = e.start + @as(u32, @intCast(done));
        const s = at(off);
        if (s.len == 0) break; // drive ran out before the file did
        const n = @min(s.len, want - done);
        @memcpy(dst[done .. done + n], s[0..n]);
        done += n;
    }
    return done;
}

// --- native tests over the pure layout maths ------------------------------
test "a FAT entry is 32 bytes with start/len/type after the name" {
    var e: [ENTRY]u8 = [_]u8{0} ** ENTRY;
    @memcpy(e[0..10], "SAMPLE.RAW");
    std.mem.writeInt(u32, e[0x10..0x14], 3072, .little);
    std.mem.writeInt(u32, e[0x14..0x18], 40000, .little);
    e[0x18] = 1;
    try std.testing.expectEqualStrings("SAMPLE.RAW", trimName(e[0..16]));
    try std.testing.expectEqual(@as(u32, 3072), std.mem.readInt(u32, e[0x10..0x14], .little));
    try std.testing.expectEqual(@as(u32, 40000), std.mem.readInt(u32, e[0x14..0x18], .little));
}

test "a name shorter than the field stops at its NUL padding" {
    const raw = [16]u8{ 'A', '.', 'R', 'A', 'W', 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 };
    try std.testing.expectEqualStrings("A.RAW", trimName(&raw));
}

test "a name filling the field keeps every character" {
    const raw = "0123456789ABCDEF".*;
    try std.testing.expectEqualStrings("0123456789ABCDEF", trimName(&raw));
}
