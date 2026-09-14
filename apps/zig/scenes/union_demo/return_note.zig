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

/// Read the note WITHOUT spending it: for the door screen the hub launched,
/// which starts its scroller where the hub's was (jsApp.mainscrollerPos). The
/// hub still take()s it on the way back. A reader must check `door` is its own
/// door (the note was left for this launch) and that `scroll` indexes the SAME
/// scrolltext.txt: it is the next character to enter the hub's scroller.
/// null when tag, length or checksum do not match, or the buffer is too short.
pub fn peek(buf: []const u8) ?Note {
    if (buf.len < HEADER + PAYLOAD) return null;
    const p = buf[HEADER..][0..PAYLOAD];
    if (!std.mem.eql(u8, buf[0..4], &TAG) or buf[4] != PAYLOAD or buf[5] != checksum(p)) return null;
    return .{
        .door = p[0],
        .x = @bitCast(std.mem.readInt(u32, p[2..6], .little)),
        .y = @bitCast(std.mem.readInt(u32, p[6..10], .little)),
        .scroll = std.mem.readInt(u32, p[10..14], .little),
    };
}

/// Read the note and spend it: the tag is zeroed whether or not the record
/// matched, so a note is used once at most. null as for peek().
pub fn take(buf: []u8) ?Note {
    const n = peek(buf);
    if (buf.len >= HEADER + PAYLOAD) @memset(buf[0..4], 0);
    return n;
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

test "a door screen can peek at the note, and the hub still takes it back" {
    var buf = [_]u8{0} ** 64;
    write(&buf, .{ .door = 3, .x = 1500, .y = 127, .scroll = 212 });
    const seen = peek(&buf) orelse return error.TestExpectedNote;
    try expectEqual(@as(u8, 3), seen.door);
    try expectEqual(@as(u32, 212), seen.scroll);
    try expectEqual(@as(u32, 212), (peek(&buf) orelse return error.TestExpectedNote).scroll); // not spent
    const back = take(&buf) orelse return error.TestExpectedNote;
    try expectEqual(@as(f32, 1500), back.x);
    try expectEqual(@as(?Note, null), peek(&buf)); // spent by the hub
}

test "peek refuses a corrupted note and leaves the bytes alone" {
    var buf = [_]u8{0} ** 64;
    write(&buf, .{ .door = 3, .x = 1500, .y = 127, .scroll = 212 });
    buf[HEADER + 10] ^= 0x01;
    const before = buf;
    try expectEqual(@as(?Note, null), peek(&buf));
    try std.testing.expectEqualSlices(u8, &before, &buf);
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
