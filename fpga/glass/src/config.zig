// The console's settings, kept on the SD card in glass.cfg next to the shelf
// (docs/FPGA_GLASS.md, "Settings"). Plain `key=value` lines, `#` comments:
//
//   volume=200      0..255, 255 = unity (REG_AUDIO_VOL)
//   mute=0          0 or 1
//
// A missing file means "never saved": the defaults, said nowhere because nothing
// is wrong. A line that does not parse is reported (the status line and the
// log) and its key keeps its default; an unknown key is reported and skipped, so
// a newer glass.cfg still loads. The card is mounted read-only: the board makes
// it writable only for the save itself (main.zig, sdWritable).
const std = @import("std");
const map = @import("map.zig");

pub const FILE = "glass.cfg";
const MAX_BYTES = 4096;

pub const Settings = struct {
    volume: u8 = @intCast(map.AUDIO_VOL_RESET),
    mute: bool = false,

    /// The REG_AUDIO_VOL word.
    pub fn audioWord(self: Settings) u32 {
        return @as(u32, self.volume) | (if (self.mute) map.AUDIO_MUTE else 0);
    }
};

/// What a load found: the settings, and the first line it could not use (0 = none).
pub const Loaded = struct { settings: Settings = .{}, bad_line: u32 = 0, missing: bool = false };

pub fn parse(text: []const u8) Loaded {
    var out = Loaded{};
    var lines = std.mem.splitScalar(u8, text, '\n');
    var n: u32 = 0;
    while (lines.next()) |raw| {
        n += 1;
        const line = std.mem.trim(u8, raw, " \t\r");
        if (line.len == 0 or line[0] == '#') continue;
        if (!apply(&out.settings, line) and out.bad_line == 0) out.bad_line = n;
    }
    return out;
}

fn apply(s: *Settings, line: []const u8) bool {
    const eq = std.mem.indexOfScalar(u8, line, '=') orelse return false;
    const key = std.mem.trim(u8, line[0..eq], " \t");
    const val = std.mem.trim(u8, line[eq + 1 ..], " \t");
    if (std.mem.eql(u8, key, "volume")) {
        s.volume = std.fmt.parseInt(u8, val, 10) catch return false;
    } else if (std.mem.eql(u8, key, "mute")) {
        if (val.len != 1 or (val[0] != '0' and val[0] != '1')) return false;
        s.mute = val[0] == '1';
    } else return false;
    return true;
}

pub fn format(s: Settings, buf: []u8) []const u8 {
    const fmt = "# glass.cfg: the console's settings, written by glass (docs/FPGA_GLASS.md)\nvolume={d}\nmute={d}\n";
    return std.fmt.bufPrint(buf, fmt, .{ s.volume, @intFromBool(s.mute) }) catch unreachable;
}

pub fn load(io: std.Io, dir: []const u8) Loaded {
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = std.fmt.bufPrint(&path_buf, "{s}/{s}", .{ dir, FILE }) catch return .{ .bad_line = 1 };
    var buf: [MAX_BYTES]u8 = undefined;
    const text = std.Io.Dir.cwd().readFile(io, path, &buf) catch |err| return switch (err) {
        error.FileNotFound => .{ .missing = true },
        else => .{ .bad_line = 1 },
    };
    return parse(text);
}

/// Written beside it and renamed over it, so a cut mid-write leaves the old file.
pub fn save(io: std.Io, dir: []const u8, s: Settings) !void {
    var buf: [256]u8 = undefined;
    const text = format(s, &buf);
    var d = try std.Io.Dir.cwd().openDir(io, dir, .{});
    defer d.close(io);
    try d.writeFile(io, .{ .sub_path = FILE ++ ".new", .data = text });
    try d.rename(FILE ++ ".new", d, FILE, io);
}

test "glass.cfg round-trips, and a bad line keeps its default" {
    var buf: [256]u8 = undefined;
    const s = Settings{ .volume = 77, .mute = true };
    try std.testing.expectEqual(Loaded{ .settings = s }, parse(format(s, &buf)));
    const bad = parse("volume=300\nmute=1\n");
    try std.testing.expectEqual(@as(u32, 1), bad.bad_line);
    try std.testing.expectEqual(Settings{ .volume = 255, .mute = true }, bad.settings);
    try std.testing.expectEqual(@as(u32, 2), parse("# hi\nshader=crt\nvolume=9").bad_line); // unknown key
    try std.testing.expectEqual(@as(u32, 0x100 | 9), (Settings{ .volume = 9, .mute = true }).audioWord());
}

test "glass.cfg is saved and loaded from the shelf directory; none is no error" {
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [128]u8 = undefined;
    const dir = try std.fmt.bufPrint(&dir_buf, ".zig-cache/tmp/{s}", .{tmp.sub_path});
    const none = load(io, dir);
    try std.testing.expect(none.missing and none.bad_line == 0);
    try save(io, dir, .{ .volume = 128 });
    try std.testing.expectEqual(Loaded{ .settings = .{ .volume = 128 } }, load(io, dir));
    try std.testing.expectError(error.FileNotFound, save(io, ".zig-cache/tmp/no/such/dir", .{}));
}
