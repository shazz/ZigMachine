// Native tests for hip_format.zig: `zig test` this file. Synthetic files; the
// real module is apps/supplex_fs2_headless.mjs's.
const std = @import("std");
const hip = @import("hip_format.zig");

// bra.s +2 / bra.s +$e, as shaolin_title.hip starts, then code, then the tag.
const HEAD = "\x60\x02\x60\x0e\x48\xe7\xff\xfe";

test "a jump table and a TFMX song: a Hippel module" {
    try std.testing.expect(hip.recognise(HEAD ++ "\x4e\x75" ++ "TFMX\x00\x15"));
}

test "the tag right at the end of the file is still found" {
    try std.testing.expect(hip.recognise(HEAD ++ "TFMX"));
}

test "no TFMX song: refused" {
    try std.testing.expect(!hip.recognise(HEAD ++ "\x4e\x75\x00\x00TFM"));
}

test "no bra jump table: refused (an SNDH, a MOD)" {
    try std.testing.expect(!hip.recognise("SNDHxxxxTFMX"));
    try std.testing.expect(!hip.recognise("\x60\x02\x4e\x75\x00\x00TFMX"));
}

test "shorter than a jump table: refused" {
    try std.testing.expect(!hip.recognise(""));
    try std.testing.expect(!hip.recognise("\x60\x02\x60"));
}

test "a tag past the search window is not the song's" {
    var file = [_]u8{0} ** (hip.TAG_SEARCH + 8);
    @memcpy(file[0..4], "\x60\x02\x60\x0e");
    @memcpy(file[hip.TAG_SEARCH .. hip.TAG_SEARCH + 4], "TFMX");
    try std.testing.expect(!hip.recognise(&file));
}
