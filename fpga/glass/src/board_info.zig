// What Linux knows about the board, for the debug page: the Zynq's die
// temperature from the XADC (the kernel's xilinx-xadc iio driver) and memory
// from /proc/meminfo. Everything is read under `root` ("/" on the board, a
// directory of fake files in the tests); what is not there is shown as "n/a".
const std = @import("std");

pub const Info = struct {
    temp_mc: ?i64 = null, // milli-degrees Celsius
    mem_total_kb: ?u64 = null,
    mem_avail_kb: ?u64 = null,
};

pub fn read(io: std.Io, root: []const u8) Info {
    var info = Info{};
    var buf: [4096]u8 = undefined;
    if (readAt(io, root, "proc/meminfo", &buf)) |text| {
        info.mem_total_kb = meminfo(text, "MemTotal:");
        info.mem_avail_kb = meminfo(text, "MemAvailable:");
    }
    var dev: u8 = 0;
    while (dev < 4) : (dev += 1) if (xadcTemp(io, root, dev)) |t| {
        info.temp_mc = t;
        break;
    };
    return info;
}

fn readAt(io: std.Io, root: []const u8, rel: []const u8, buf: []u8) ?[]const u8 {
    var path_buf: [256]u8 = undefined;
    const path = std.fmt.bufPrint(&path_buf, "{s}/{s}", .{ root, rel }) catch return null;
    return std.Io.Dir.cwd().readFile(io, path, buf) catch null;
}

pub fn meminfo(text: []const u8, key: []const u8) ?u64 {
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |line| {
        if (!std.mem.startsWith(u8, line, key)) continue;
        var it = std.mem.tokenizeAny(u8, line[key.len..], " \tkB");
        return std.fmt.parseInt(u64, it.next() orelse return null, 10) catch null;
    }
    return null;
}

// in_temp0_raw, _offset and _scale: temperature (m°C) = (raw + offset) * scale.
fn xadcTemp(io: std.Io, root: []const u8, dev: u8) ?i64 {
    var rel: [96]u8 = undefined;
    var buf: [64]u8 = undefined;
    const base = std.fmt.bufPrint(&rel, "sys/bus/iio/devices/iio:device{d}/", .{dev}) catch return null;
    const name = readAt(io, root, cat(&rel, base.len, "name"), &buf) orelse return null;
    if (!std.mem.startsWith(u8, name, "xadc")) return null;
    const raw = number(io, root, cat(&rel, base.len, "in_temp0_raw")) orelse return null;
    const offset = number(io, root, cat(&rel, base.len, "in_temp0_offset")) orelse return null;
    const scale = number(io, root, cat(&rel, base.len, "in_temp0_scale")) orelse return null;
    return @intFromFloat((raw + offset) * scale);
}

fn cat(rel: *[96]u8, at: usize, leaf: []const u8) []const u8 {
    @memcpy(rel[at..][0..leaf.len], leaf);
    return rel[0 .. at + leaf.len];
}

fn number(io: std.Io, root: []const u8, rel: []const u8) ?f64 {
    var buf: [64]u8 = undefined;
    const text = readAt(io, root, rel, &buf) orelse return null;
    return std.fmt.parseFloat(f64, std.mem.trim(u8, text, " \n")) catch null;
}

test "the XADC temperature and memory are read when present, n/a when not" {
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var root_buf: [128]u8 = undefined;
    const root = try std.fmt.bufPrint(&root_buf, ".zig-cache/tmp/{s}", .{tmp.sub_path});
    try std.testing.expectEqual(Info{}, read(io, root));
    try tmp.dir.createDirPath(io, "proc");
    try tmp.dir.writeFile(io, .{ .sub_path = "proc/meminfo", .data = "MemTotal:   491520 kB\nMemFree: 1 kB\nMemAvailable:  400000 kB\n" });
    const d = "sys/bus/iio/devices/iio:device1/";
    try tmp.dir.createDirPath(io, d);
    try tmp.dir.writeFile(io, .{ .sub_path = d ++ "name", .data = "xadc\n" });
    try tmp.dir.writeFile(io, .{ .sub_path = d ++ "in_temp0_raw", .data = "2600\n" });
    try tmp.dir.writeFile(io, .{ .sub_path = d ++ "in_temp0_offset", .data = "-2219\n" });
    try tmp.dir.writeFile(io, .{ .sub_path = d ++ "in_temp0_scale", .data = "123.040771484\n" });
    const info = read(io, root);
    try std.testing.expectEqual(@as(?u64, 491520), info.mem_total_kb);
    try std.testing.expectEqual(@as(?u64, 400000), info.mem_avail_kb);
    try std.testing.expectEqual(@as(?i64, 46878), info.temp_mc); // (2600 - 2219) * 123.04 = 46.9 C
}
