// --------------------------------------------------------------------------
// SysInfo — the SOUND page's file list: the sound files on the mounted disk,
// which one is selected, which one plays. A file is a sound by its name, as a
// TOS file selector filters by extension; before it plays its bytes must look
// like what the name says (sysinfo/sound_play.zig asks imageOk), since a disk
// is not trusted to hold what its FAT claims.
//
//   *.SND / *.SNDH   an SNDH: 68000 code driving the YM ("SNDH" at 12, or Pack-Ice packed)
//   *.SAP            an Atari 8-bit SAP: 6502 code on the POKEY ("SAP" + CR LF at 0)
//   *.RAW            signed 8-bit PCM, as ST Replay's SAMPLE.RAW
//   *.XM             a FastTracker 2 module ("Extended Module: " at 0), mixed onto Paula
//   *.HIP            a Jochen Hippel Amiga module: its own 68000 replay (bra, bra at 0)
//                    and a "TFMX" song, on Paula
//
// An SNDH, XM or HIP may be stored ZX0-packed (the "ZX0!" container): the header is
// checked on the bytes it depacks to (sysinfo/sound_play.zig).
//
// Pure: no machine. Tested natively (apps/zig/scene_tests.zig).
// --------------------------------------------------------------------------
const std = @import("std");

pub const Kind = enum(u8) { sndh, sap, pcm, xm, hip };
pub const MAX: usize = 6; // the page's rows for files

pub const Entry = struct { name: [16]u8, len: u32, kind: Kind };

/// What the page says under the list.
pub const Status = enum(u8) { idle, playing, stopped, not_found, too_big, bad_image, refused };

/// The kind a file name says, or null: not a sound file.
pub fn kindOf(name: []const u8) ?Kind {
    const dot = std.mem.lastIndexOfScalar(u8, name, '.') orelse return null;
    const ext = name[dot + 1 ..];
    if (eqlUpper(ext, "SND") or eqlUpper(ext, "SNDH")) return .sndh;
    if (eqlUpper(ext, "SAP")) return .sap;
    if (eqlUpper(ext, "RAW")) return .pcm;
    if (eqlUpper(ext, "XM")) return .xm;
    if (eqlUpper(ext, "HIP")) return .hip;
    return null;
}

fn eqlUpper(s: []const u8, upper: []const u8) bool {
    if (s.len != upper.len) return false;
    for (s, upper) |a, b| if (std.ascii.toUpper(a) != b) return false;
    return true;
}

/// The bytes read off the disk are the kind the name says (PCM has no header).
pub fn imageOk(kind: Kind, bytes: []const u8) bool {
    return switch (kind) {
        .sndh => (bytes.len >= 16 and std.mem.eql(u8, bytes[12..16], "SNDH")) or
            (bytes.len >= 12 and std.mem.eql(u8, bytes[0..4], "ICE!")),
        .sap => bytes.len >= 5 and std.mem.eql(u8, bytes[0..5], "SAP\r\n"),
        .pcm => bytes.len > 0,
        .xm => std.mem.startsWith(u8, bytes, "Extended Module: "),
        .hip => bytes.len >= 4 and bytes[0] == 0x60 and bytes[2] == 0x60 and
            std.mem.indexOf(u8, bytes[0..@min(bytes.len, HIP_TFMX_WITHIN)], "TFMX") != null,
    };
}

/// How far into a Hippel module its "TFMX" song may start (players/hip_format.zig's bound).
const HIP_TFMX_WITHIN: usize = 16 * 1024;

pub const List = struct {
    items: [MAX]Entry = undefined,
    n: u8 = 0,
    sel: u8 = 0,
    playing: ?u8 = null,
    status: Status = .idle,

    /// The sound files among the FAT's (anything with `.name: [16]u8` and
    /// `.len: u32`: pages.File), in FAT order, MAX at most.
    pub fn scan(self: *List, files: anytype) void {
        self.* = .{};
        for (files) |f| {
            if (self.n == MAX) break;
            const k = kindOf(std.mem.sliceTo(&f.name, 0)) orelse continue;
            self.items[self.n] = .{ .name = f.name, .len = f.len, .kind = k };
            self.n += 1;
        }
    }

    /// Up (-1) / Down (+1), wrapping, as a file selector's list does.
    pub fn move(self: *List, step: i8) void {
        if (self.n == 0) return;
        const n: i16 = self.n;
        self.sel = @intCast(@mod(@as(i16, self.sel) + step, n));
    }

    pub fn selected(self: *const List) ?*const Entry {
        return if (self.sel < self.n) &self.items[self.sel] else null;
    }

    pub fn nameOf(e: *const Entry) []const u8 {
        return std.mem.sliceTo(&e.name, 0);
    }
};

// --- native tests ------------------------------------------------------------
const F = struct { name: [16]u8, len: u32 };
fn nm(s: []const u8, len: u32) F {
    var b = [_]u8{0} ** 16;
    @memcpy(b[0..s.len], s);
    return .{ .name = b, .len = len };
}

test "the sound files are picked out of the FAT by extension, in order" {
    var l: List = .{};
    l.scan(&[_]F{ nm("BOOT.WSM", 9000), nm("JINKS.SND", 4024), nm("GAUNTLET.SAP", 1953), nm("SAMPLE.RAW", 12500), nm("README.TXT", 10) });
    try std.testing.expectEqual(@as(u8, 3), l.n);
    try std.testing.expectEqualStrings("JINKS.SND", List.nameOf(&l.items[0]));
    try std.testing.expectEqual(Kind.sap, l.items[1].kind);
    try std.testing.expectEqual(Kind.pcm, l.items[2].kind);
    try std.testing.expectEqual(@as(u32, 12500), l.items[2].len);
}

test "a disk with no sound file lists none and selects nothing" {
    var l: List = .{};
    l.scan(&[_]F{nm("BOOT.WSM", 9000)});
    try std.testing.expectEqual(@as(u8, 0), l.n);
    l.move(1);
    try std.testing.expectEqual(@as(?*const Entry, null), l.selected());
}

test "the selection wraps both ways" {
    var l: List = .{};
    l.scan(&[_]F{ nm("A.SND", 1), nm("B.SAP", 1) });
    l.move(-1);
    try std.testing.expectEqual(@as(u8, 1), l.sel);
    l.move(1);
    try std.testing.expectEqual(@as(u8, 0), l.sel);
}

test "a name without a sound extension is not a sound; case does not matter" {
    try std.testing.expectEqual(@as(?Kind, null), kindOf("SNDH"));
    try std.testing.expectEqual(@as(?Kind, null), kindOf("X.MOD"));
    try std.testing.expectEqual(@as(?Kind, .sndh), kindOf("x.sndh"));
    try std.testing.expectEqual(@as(?Kind, .xm), kindOf("KEYGEN.XM"));
    try std.testing.expectEqual(@as(?Kind, .hip), kindOf("thalion.hip"));
}

test "an XM must say Extended Module, a HIP carry a bra pair and a TFMX song" {
    try std.testing.expect(imageOk(.xm, "Extended Module: Keygen 9000"));
    try std.testing.expect(!imageOk(.xm, "ZX0!\x01\x00"));
    try std.testing.expect(imageOk(.hip, "\x60\x02\x60\x0e\x48\xe7TFMX"));
    try std.testing.expect(!imageOk(.hip, "\x60\x02\x60\x0e\x48\xe7"));
    try std.testing.expect(!imageOk(.hip, "SNDH\x60\x00\x60\x00TFMX"));
}

test "an image must carry its kind's header before it plays" {
    var sndh = [_]u8{0} ** 16;
    @memcpy(sndh[12..16], "SNDH");
    try std.testing.expect(imageOk(.sndh, &sndh));
    try std.testing.expect(!imageOk(.sndh, "SAP\r\nAUTHOR"));
    try std.testing.expect(imageOk(.sap, "SAP\r\nAUTHOR"));
    try std.testing.expect(!imageOk(.sap, &sndh));
    try std.testing.expect(!imageOk(.pcm, ""));
}
