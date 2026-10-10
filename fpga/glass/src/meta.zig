// What the shelf says about each cart beyond its file name: shelf.txt, next to
// the .zmd disks on the SD card, written by fpga/tools/shelf_meta.py from
// apps/zig/scenes/catalog.zig, the cart matrix in build.zig and each scene's
// header comment. One line a disk, tab-separated, `#` comments:
//
//   FILE <TAB> TITLE <TAB> GROUP <TAB> YEAR <TAB> TYPE <TAB> DESCRIPTION
//
// Any field but FILE and TITLE may be empty. A side file, not a block inside the
// .zmd: the disk format and the browser loader stay as they are, and the text is
// fixable without repacking a disk.
//
// Optional: with no shelf.txt the menu shows each disk's own title and says so.
// A line with too few fields is counted, reported, and skipped.
const std = @import("std");

pub const FILE = "shelf.txt";
pub const MAX_BYTES = 256 << 10;

pub const Meta = struct {
    title: []const u8,
    group: []const u8 = "",
    year: []const u8 = "",
    kind: []const u8 = "",
    desc: []const u8 = "",
};

pub const Entry = struct { file: []const u8, meta: Meta };

pub const Table = struct {
    entries: []Entry = &.{},
    bad_lines: u32 = 0,
    first_bad: u32 = 0,
    missing: bool = false,

    pub fn find(self: *const Table, file: []const u8) ?Meta {
        for (self.entries) |e| if (std.ascii.eqlIgnoreCase(e.file, file)) return e.meta;
        return null;
    }
};

/// Parse `text` into records allocated from `a` (an arena: they live as long as the shelf).
pub fn parse(a: std.mem.Allocator, text: []const u8) !Table {
    var list: std.ArrayList(Entry) = .empty;
    var t = Table{};
    var lines = std.mem.splitScalar(u8, text, '\n');
    var n: u32 = 0;
    while (lines.next()) |raw| {
        n += 1;
        const line = std.mem.trimEnd(u8, raw, "\r");
        if (std.mem.trim(u8, line, " \t").len == 0 or line[0] == '#') continue;
        const e = entry(line) orelse {
            if (t.bad_lines == 0) t.first_bad = n;
            t.bad_lines += 1;
            continue;
        };
        try list.append(a, .{ .file = try a.dupe(u8, e.file), .meta = try dupeMeta(a, e.meta) });
    }
    t.entries = list.items;
    return t;
}

fn entry(line: []const u8) ?Entry {
    var f: [6][]const u8 = .{""} ** 6;
    var it = std.mem.splitScalar(u8, line, '\t');
    var i: usize = 0;
    while (it.next()) |field| : (i += 1) {
        if (i == f.len) return null;
        f[i] = field;
    }
    if (i < 2 or f[0].len == 0 or f[1].len == 0) return null;
    return .{ .file = f[0], .meta = .{ .title = f[1], .group = f[2], .year = f[3], .kind = f[4], .desc = f[5] } };
}

fn dupeMeta(a: std.mem.Allocator, m: Meta) !Meta {
    return .{
        .title = try a.dupe(u8, m.title),
        .group = try a.dupe(u8, m.group),
        .year = try a.dupe(u8, m.year),
        .kind = try a.dupe(u8, m.kind),
        .desc = try a.dupe(u8, m.desc),
    };
}

pub fn load(a: std.mem.Allocator, io: std.Io, dir: std.Io.Dir) !Table {
    const text = dir.readFileAlloc(io, FILE, a, .limited(MAX_BYTES)) catch |err| switch (err) {
        error.FileNotFound => return .{ .missing = true },
        else => return err,
    };
    return parse(a, text);
}

test "shelf.txt lines become records; short lines are counted, not kept" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const text = "# shelf.txt\ndemo-stniccc.zmd\tOXYGENE STNICCC 2000\tOxygene\t2000\tatari st\tThe flight.\r\n" ++
        "lonely.zmd\n\ndemo-x.zmd\tX\n";
    const t = try parse(arena.allocator(), text);
    try std.testing.expectEqual(@as(usize, 2), t.entries.len);
    try std.testing.expectEqual(@as(u32, 1), t.bad_lines);
    try std.testing.expectEqual(@as(u32, 3), t.first_bad);
    const m = t.find("DEMO-STNICCC.zmd").?;
    try std.testing.expectEqualStrings("Oxygene", m.group);
    try std.testing.expectEqualStrings("The flight.", m.desc);
    try std.testing.expectEqualStrings("", t.find("demo-x.zmd").?.year);
    try std.testing.expectEqual(@as(?Meta, null), t.find("demo-unknown.zmd"));
}
