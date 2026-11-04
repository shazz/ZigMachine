// --------------------------------------------------------------------------
// The show's script: the 164 `8xx` commands of COMFORT.MOD ("MSX 4 Damo's Demo", MSG), as
// (row, value). Damo sequenced the intro in ProTracker: the replay hands the 8xx parameter to the
// demo system, which loads that value's routine triple (prototypes/falcon_ays_re/ANALYSIS.md §0).
// The song runs at speed 7, 125 BPM, with no pattern break: a row is 7 ticks of 50 Hz (0.14 s)
// and row = pattern * 64 + line. Extracted from the MOD (prototypes/falcon_ays_re/
// sync_timeline.txt): sync data, not the music; the MOD itself is a local file, never in git.
// --------------------------------------------------------------------------
const std = @import("std");

pub const Cmd = struct { u16, u8 };

pub const COMMANDS = [_]Cmd{
    .{ 0, 0x07 }, .{ 1, 0x04 }, .{ 64, 0x1D }, .{ 96, 0x1E }, .{ 122, 0x07 }, .{ 124, 0x05 }, .{ 128, 0x0B },
    .{ 140, 0x1B }, .{ 144, 0x0B }, .{ 156, 0x13 }, .{ 160, 0x0D }, .{ 172, 0x1B }, .{ 176, 0x0D },
    .{ 188, 0x22 }, .{ 192, 0x10 }, .{ 204, 0x13 }, .{ 208, 0x10 }, .{ 220, 0x23 }, .{ 221, 0x10 },
    .{ 224, 0x0F }, .{ 240, 0x22 }, .{ 254, 0x23 }, .{ 255, 0x04 }, .{ 256, 0x20 }, .{ 288, 0x25 },
    .{ 299, 0x25 }, .{ 304, 0x26 }, .{ 314, 0x07 }, .{ 315, 0x09 }, .{ 320, 0x14 }, .{ 321, 0x15 },
    .{ 322, 0x14 }, .{ 324, 0x15 }, .{ 326, 0x14 }, .{ 331, 0x2B }, .{ 336, 0x15 }, .{ 337, 0x14 },
    .{ 338, 0x15 }, .{ 340, 0x14 }, .{ 342, 0x15 }, .{ 347, 0x2C }, .{ 352, 0x14 }, .{ 353, 0x15 },
    .{ 354, 0x14 }, .{ 356, 0x15 }, .{ 358, 0x14 }, .{ 363, 0x32 }, .{ 368, 0x15 }, .{ 369, 0x14 },
    .{ 370, 0x15 }, .{ 372, 0x14 }, .{ 374, 0x15 }, .{ 383, 0x07 }, .{ 384, 0x0E }, .{ 396, 0x13 },
    .{ 400, 0x0E }, .{ 412, 0x13 }, .{ 416, 0x0E }, .{ 417, 0x11 }, .{ 428, 0x13 }, .{ 432, 0x0E },
    .{ 433, 0x11 }, .{ 444, 0x13 }, .{ 448, 0x0B }, .{ 460, 0x21 }, .{ 464, 0x0D }, .{ 476, 0x21 },
    .{ 480, 0x0B }, .{ 484, 0x11 }, .{ 492, 0x21 }, .{ 496, 0x36 }, .{ 509, 0x1B }, .{ 512, 0x2D },
    .{ 518, 0x33 }, .{ 540, 0x1A }, .{ 544, 0x2E }, .{ 572, 0x37 }, .{ 576, 0x2F }, .{ 582, 0x33 },
    .{ 604, 0x1A }, .{ 607, 0x05 }, .{ 608, 0x0D }, .{ 612, 0x23 }, .{ 613, 0x0D }, .{ 620, 0x23 },
    .{ 621, 0x0D }, .{ 624, 0x11 }, .{ 636, 0x13 }, .{ 639, 0x07 }, .{ 640, 0x30 }, .{ 646, 0x33 },
    .{ 668, 0x1A }, .{ 672, 0x10 }, .{ 684, 0x23 }, .{ 685, 0x10 }, .{ 688, 0x11 }, .{ 700, 0x1B },
    .{ 704, 0x31 }, .{ 710, 0x33 }, .{ 732, 0x38 }, .{ 736, 0x0E }, .{ 737, 0x11 }, .{ 748, 0x13 },
    .{ 752, 0x11 }, .{ 762, 0x36 }, .{ 767, 0x07 }, .{ 768, 0x08 }, .{ 828, 0x16 }, .{ 832, 0x08 },
    .{ 880, 0x16 }, .{ 892, 0x12 }, .{ 894, 0x07 }, .{ 895, 0x04 }, .{ 895, 0x04 }, .{ 896, 0x17 },
    .{ 908, 0x1A }, .{ 912, 0x17 }, .{ 924, 0x1A }, .{ 928, 0x17 }, .{ 940, 0x1A }, .{ 944, 0x17 },
    .{ 947, 0x24 }, .{ 948, 0x34 }, .{ 956, 0x19 }, .{ 960, 0x17 }, .{ 972, 0x1A }, .{ 976, 0x17 },
    .{ 988, 0x1A }, .{ 992, 0x17 }, .{ 1004, 0x1A }, .{ 1008, 0x17 }, .{ 1011, 0x24 }, .{ 1012, 0x34 },
    .{ 1020, 0x19 }, .{ 1024, 0x18 }, .{ 1036, 0x19 }, .{ 1040, 0x18 }, .{ 1052, 0x19 }, .{ 1056, 0x18 },
    .{ 1060, 0x24 }, .{ 1061, 0x18 }, .{ 1068, 0x19 }, .{ 1072, 0x18 }, .{ 1080, 0x17 }, .{ 1084, 0x1A },
    .{ 1088, 0x19 }, .{ 1120, 0x1C }, .{ 1151, 0x24 }, .{ 1152, 0x29 }, .{ 1184, 0x39 }, .{ 1248, 0x3A },
    .{ 1279, 0x07 }, .{ 1280, 0x2A }, .{ 1324, 0x1A }, .{ 1328, 0x3C }, .{ 1344, 0x3B }, .{ 1345, 0x3C },
    .{ 1408, 0x3B }, .{ 1409, 0x3C }, .{ 1472, 0x3B }, .{ 1473, 0x3C }, .{ 1500, 0x1A }, .{ 1504, 0x3C },
    .{ 1536, 0x3E },
};

/// The song's length in rows (26 patterns, 233 s); the show loops there.
pub const SONG_ROWS: u32 = 26 * 64;
/// 50 Hz ticks a row (speed 7).
pub const TICKS_PER_ROW: u32 = 7;

/// Song position at frame `f` of the 60 Hz machine, in 50 Hz ticks: f * 50 / 60, exact.
pub fn ticksAt(frame: u32) u32 {
    return frame * 5 / 6;
}

/// Walks the commands in order: `next` returns each command whose row has been reached, once.
pub const Cursor = struct {
    i: usize = 0,

    pub fn next(self: *Cursor, row: u32) ?u8 {
        if (self.i >= COMMANDS.len or COMMANDS[self.i][0] > row) return null;
        defer self.i += 1;
        return COMMANDS[self.i][1];
    }
};

test "the table is in row order and every value is one the demo's table defines" {
    var last: u16 = 0;
    for (COMMANDS) |c| {
        try std.testing.expect(c[0] >= last);
        try std.testing.expect(c[1] >= 4 and c[1] <= 0x3E);
        last = c[0];
    }
    try std.testing.expectEqual(@as(usize, 164), COMMANDS.len);
}

test "the cursor gives each command once, both commands of one row, none early" {
    var c = Cursor{};
    try std.testing.expectEqual(@as(?u8, 0x07), c.next(0));
    try std.testing.expectEqual(@as(?u8, null), c.next(0));
    try std.testing.expectEqual(@as(?u8, 0x04), c.next(63));
    try std.testing.expectEqual(@as(?u8, 0x1D), c.next(64)); // "in autumn 2003" at 8.96 s
    try std.testing.expectEqual(@as(?u8, null), c.next(64));
    var d = Cursor{ .i = 112 }; // row 895 holds two 804s (channels 0 and 1)
    try std.testing.expectEqual(@as(?u8, 0x04), d.next(895));
    try std.testing.expectEqual(@as(?u8, 0x04), d.next(895));
    try std.testing.expectEqual(@as(?u8, null), d.next(895));
}

test "60 Hz frames map to song rows: frame 538 is 8.97 s, past row 64 (8.96 s)" {
    try std.testing.expectEqual(@as(u32, 448), ticksAt(538));
    try std.testing.expectEqual(@as(u32, 64), ticksAt(538) / TICKS_PER_ROW);
}
