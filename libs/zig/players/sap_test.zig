// Native tests for the SAP header and blocks (sap.zig): `zig test` this file.
// Synthetic files only; the real tunes (prototypes/sap_asma, not in the repo)
// are fpga/tests/test_sap.py's, skipped when absent.
const std = @import("std");
const sap = @import("sap.zig");

const BIN = "\xFF\xFF\x00\x30\x02\x30\xA9\x01\x60" ++ "\x00\x40\x00\x40\x60"; // two blocks, the 2nd without $FFFF

fn ok(file: []const u8) !sap.Info {
    return switch (sap.parse(file)) {
        .ok => |i| i,
        .refused => |r| {
            std.debug.print("refused: {s}\n", .{@tagName(r)});
            return error.Refused;
        },
    };
}

fn refused(file: []const u8) sap.Refusal {
    return switch (sap.parse(file)) {
        .ok => .none,
        .refused => |r| r,
    };
}

test "a type B header: addresses, songs, the PAL default of 312 lines" {
    const i = try ok("SAP\r\nAUTHOR \"Someone\"\r\nNAME \"X\"\r\nSONGS 3\r\nDEFSONG 1\r\nTYPE B\r\nINIT 3000\r\nPLAYER 4000\r\nTIME 01:02.000 LOOP\r\n" ++ BIN);
    try std.testing.expectEqual(sap.Type.b, i.type);
    try std.testing.expectEqual(@as(u16, 0x3000), i.init);
    try std.testing.expectEqual(@as(u16, 0x4000), i.player);
    try std.testing.expectEqual(@as(u8, 3), i.songs);
    try std.testing.expectEqual(@as(u8, 1), i.defsong);
    try std.testing.expectEqual(@as(u16, 312), i.fastplay);
    try std.testing.expect(!i.ntsc);
}

test "NTSC defaults to 262 lines, FASTPLAY overrides; a type C needs MUSIC and PLAYER" {
    const n = try ok("SAP\r\nNTSC\r\nTYPE B\r\nINIT 3000\r\nPLAYER 4000\r\n" ++ BIN);
    try std.testing.expect(n.ntsc);
    try std.testing.expectEqual(@as(u16, 262), n.fastplay);
    const c = try ok("SAP\r\nTYPE C\r\nFASTPLAY 156\r\nMUSIC 3000\r\nPLAYER 4000\r\n" ++ BIN);
    try std.testing.expectEqual(sap.Type.c, c.type);
    try std.testing.expectEqual(@as(u16, 156), c.fastplay);
    try std.testing.expectEqual(sap.Refusal.missing_address, refused("SAP\r\nTYPE C\r\nPLAYER 4000\r\n" ++ BIN));
}

test "the blocks load where they say, with or without $FFFF before each" {
    var ram = [_]u8{0} ** 65536;
    try std.testing.expectEqual(@as(?usize, 4), sap.blocks(BIN, &ram));
    try std.testing.expectEqualSlices(u8, "\xA9\x01\x60", ram[0x3000..0x3003]);
    try std.testing.expectEqual(@as(u8, 0x60), ram[0x4000]);
}

test "refusals say why: magic, data, type, stereo, a bad tag, a bad block" {
    const T = "TYPE B\r\nINIT 3000\r\nPLAYER 4000\r\n";
    try std.testing.expectEqual(sap.Refusal.not_sap, refused("SAQ\r\n" ++ T ++ BIN));
    try std.testing.expectEqual(sap.Refusal.no_data, refused("SAP\r\n" ++ T));
    try std.testing.expectEqual(sap.Refusal.unsupported_type, refused("SAP\r\nTYPE D\r\nINIT 3000\r\nPLAYER 4000\r\n" ++ BIN));
    try std.testing.expectEqual(sap.Refusal.unsupported_type, refused("SAP\r\nINIT 3000\r\nPLAYER 4000\r\n" ++ BIN));
    try std.testing.expectEqual(sap.Refusal.stereo, refused("SAP\r\nSTEREO\r\n" ++ T ++ BIN));
    try std.testing.expectEqual(sap.Refusal.bad_tag, refused("SAP\r\nTYPE B\r\nINIT 30G0\r\nPLAYER 4000\r\n" ++ BIN));
    try std.testing.expectEqual(sap.Refusal.bad_block, refused("SAP\r\n" ++ T ++ "\xFF\xFF\x02\x30\x00\x30\x00"));
    try std.testing.expectEqual(sap.Refusal.bad_block, refused("SAP\r\n" ++ T ++ "\xFF\xFF\x00\x30\x09\x30\x00"));
}
