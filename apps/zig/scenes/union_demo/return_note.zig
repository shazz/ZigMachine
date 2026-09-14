// --------------------------------------------------------------------------
// The note the Union Demo hub leaves in the ROM's scratch bytes when a door
// launches a screen, so the hub it returns to starts where it left: Charly's
// position (the remake's jsApp.entityPos, entities.js:199 -> MainEntity.init
// :39-42) and the scroller's next character (jsApp.mainscrollerPos, main.js:488
// -> scrolltext init offset, main.js:467). A cart swap replaces the whole cart,
// so only the ROM's statics can carry it (rom/rom_main.zig romScratchPtr).
//
// Record (little-endian), the ROM scratch convention:
//   0 "UNI1" owner tag (program + layout version)   4 u8 payload length
//   5 u8 XOR of the payload bytes                    6 payload:
//     door u8, flags u8 (none yet), x f32, y f32, scroll u32
//
// No ZigOS or ROM import: it works on a plain byte slice, so it tests natively
// (apps/zig/scene_tests.zig).
// --------------------------------------------------------------------------
const std = @import("std");

const TAG = "UNI1".*;
const HEADER = 6;
const PAYLOAD = 14;

pub const Note = struct { door: u8, x: f32, y: f32, scroll: u32 };

/// Leave `n` in `buf` (too short: nothing is written). The tag goes in last.
pub fn write(buf: []u8, n: Note) void {
    if (buf.len < HEADER + PAYLOAD) return;
    const p = buf[HEADER..][0..PAYLOAD];
    p[0] = n.door;
    p[1] = 0;
    std.mem.writeInt(u32, p[2..6], @bitCast(n.x), .little);
    std.mem.writeInt(u32, p[6..10], @bitCast(n.y), .little);
    std.mem.writeInt(u32, p[10..14], n.scroll, .little);
    buf[4] = PAYLOAD;
    buf[5] = checksum(p);
    buf[0..4].* = TAG;
}

/// Read the note and spend it: the tag is zeroed whether or not the record
/// matched, so a note is used once at most. null when tag, length or checksum
/// do not match (no note, a stale or foreign record, or a buffer too short).
pub fn take(buf: []u8) ?Note {
    if (buf.len < HEADER + PAYLOAD) return null;
    const p = buf[HEADER..][0..PAYLOAD];
    const valid = std.mem.eql(u8, buf[0..4], &TAG) and buf[4] == PAYLOAD and buf[5] == checksum(p);
    @memset(buf[0..4], 0);
    if (!valid) return null;
    return .{
        .door = p[0],
        .x = @bitCast(std.mem.readInt(u32, p[2..6], .little)),
        .y = @bitCast(std.mem.readInt(u32, p[6..10], .little)),
        .scroll = std.mem.readInt(u32, p[10..14], .little),
    };
}

fn checksum(p: []const u8) u8 {
    var c: u8 = 0;
    for (p) |b| c ^= b;
    return c;
}

const expectEqual = std.testing.expectEqual;

test "a note comes back once, as written" {
    var buf = [_]u8{0} ** 64;
    write(&buf, .{ .door = 8, .x = 4236.5, .y = 127, .scroll = 57 });
    const n = take(&buf) orelse return error.TestExpectedNote;
    try expectEqual(@as(u8, 8), n.door);
    try expectEqual(@as(f32, 4236.5), n.x);
    try expectEqual(@as(f32, 127), n.y);
    try expectEqual(@as(u32, 57), n.scroll);
    try expectEqual(@as(?Note, null), take(&buf)); // spent
}

test "a zeroed scratch (power-on) holds no note" {
    var buf = [_]u8{0} ** 64;
    try expectEqual(@as(?Note, null), take(&buf));
}

test "a corrupted payload is refused, and the note is spent anyway" {
    var buf = [_]u8{0} ** 64;
    write(&buf, .{ .door = 0, .x = 686, .y = 127, .scroll = 12 });
    buf[HEADER + 3] ^= 0x40;
    try expectEqual(@as(?Note, null), take(&buf));
    buf[HEADER + 3] ^= 0x40; // repaired, but the tag is already gone
    try expectEqual(@as(?Note, null), take(&buf));
}

test "another program's record is never read as ours" {
    var buf = [_]u8{0} ** 64;
    write(&buf, .{ .door = 0, .x = 686, .y = 127, .scroll = 12 });
    buf[3] = '2'; // "UNI2": a later layout
    try expectEqual(@as(?Note, null), take(&buf));
}

test "a scratch too short for the record is left alone" {
    var buf = [_]u8{0xAA} ** (HEADER + PAYLOAD - 1);
    write(&buf, .{ .door = 0, .x = 686, .y = 127, .scroll = 12 });
    try expectEqual(@as(?Note, null), take(&buf));
    try expectEqual(@as(u8, 0xAA), buf[0]);
}
