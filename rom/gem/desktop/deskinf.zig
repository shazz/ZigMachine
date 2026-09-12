// --------------------------------------------------------------------------
// DESKTOP.INF — what Options > Save Desktop writes to the boot disk. TOS stores
// the desktop's state as a short text file of tagged lines, and this is that
// file: one line per thing worth remembering, in TOS's own line prefixes.
//
//   #E <res> <rrggbb>          desktop: resolution (00 low / 01 medium) + colour
//   #W <sx> <sy> <x> <y> <w> <h> <v> <path>@   an open window (cells), v=0 icons
//   #M <col> <row> <drive> <label>@            the drive icon's grid cell
//   #T <col> <row> <label>@                    the trash icon's grid cell
//
// TOS packs more into its own #E/#W fields than we have state for; rather than
// emit bytes we would be inventing, each line carries only what the desktop
// actually knows. Pure text assembly — no GUI, so `zig test` covers the format.
// --------------------------------------------------------------------------
const std = @import("std");

pub const CellIcon = struct { col: i16, row: i16, label: []const u8 };
pub const Win = struct { x: i16, y: i16, w: i16, h: i16, text_view: bool, path: []const u8 };

pub const Config = struct {
    medium: bool,
    bg: [3]u8,
    drive: CellIcon,
    trash: CellIcon,
    wins: []const Win,
};

pub const NAME = "DESKTOP.INF";
pub const MAX_BYTES = 512;

// Render `c` into `buf` and return the written slice. A buffer too small for the
// whole desktop truncates at a line boundary rather than emitting a half line.
pub fn write(buf: []u8, c: Config) []const u8 {
    var w = Writer{ .buf = buf };
    w.line("#E {s} {x:0>2}{x:0>2}{x:0>2}", .{ if (c.medium) "01" else "00", c.bg[0], c.bg[1], c.bg[2] });
    for (c.wins) |win|
        w.line("#W 00 00 {d:0>2} {d:0>2} {d:0>2} {d:0>2} {s} {s}@", .{
            cells(win.x), cells(win.y), cells(win.w), cells(win.h),
            if (win.text_view) "01" else "00",
            win.path,
        });
    w.line("#M {d:0>2} {d:0>2} A {s}@", .{ nn(c.drive.col), nn(c.drive.row), c.drive.label });
    w.line("#T {d:0>2} {d:0>2} {s}@", .{ nn(c.trash.col), nn(c.trash.row), c.trash.label });
    return w.written();
}

// TOS records window geometry in character cells, not pixels. Everything the
// file stores is a count, so it is written unsigned (a signed format verb would
// print a "+" into the field).
fn cells(px: i16) u16 {
    return nn(@divTrunc(px, 8));
}
fn nn(v: i16) u16 {
    return @intCast(@max(0, v));
}

const Writer = struct {
    buf: []u8,
    len: usize = 0,
    full: bool = false,

    // The first line that does not fit ENDS the file: skipping it and carrying on
    // would write a config that silently omits a window while still looking
    // complete. A short file is honest; a holed one is not.
    fn line(self: *Writer, comptime fmt: []const u8, args: anytype) void {
        if (self.full) return;
        const s = std.fmt.bufPrint(self.buf[self.len..], fmt ++ "\r\n", args) catch {
            self.full = true;
            return;
        };
        self.len += s.len;
    }
    fn written(self: *const Writer) []const u8 {
        return self.buf[0..self.len];
    }
};

// --- native format tests --------------------------------------------------
const test_cfg = Config{
    .medium = false,
    .bg = .{ 1, 160, 164 },
    .drive = .{ .col = 0, .row = 0, .label = "FLOPPY" },
    .trash = .{ .col = 0, .row = 3, .label = "TRASH" },
    .wins = &.{},
};

test "an empty desktop writes the config and both icons" {
    var buf: [MAX_BYTES]u8 = undefined;
    const out = write(&buf, test_cfg);
    try std.testing.expectEqualStrings(
        "#E 00 01a0a4\r\n" ++
            "#M 00 00 A FLOPPY@\r\n" ++
            "#T 00 03 TRASH@\r\n",
        out,
    );
}

test "each open window is a #W line in cells" {
    var cfg = test_cfg;
    cfg.medium = true;
    cfg.wins = &.{.{ .x = 16, .y = 24, .w = 240, .h = 96, .text_view = true, .path = "A:\\" }};
    var buf: [MAX_BYTES]u8 = undefined;
    const out = write(&buf, cfg);
    try std.testing.expect(std.mem.startsWith(u8, out, "#E 01 "));
    try std.testing.expect(std.mem.indexOf(u8, out, "#W 00 00 02 03 30 12 01 A:\\@\r\n") != null);
}

test "a full buffer truncates at a line boundary" {
    var cfg = test_cfg;
    cfg.wins = &.{
        .{ .x = 0, .y = 0, .w = 80, .h = 80, .text_view = false, .path = "A:\\ONE" },
        .{ .x = 0, .y = 0, .w = 80, .h = 80, .text_view = false, .path = "A:\\TWO" },
    };
    var buf: [40]u8 = undefined; // room for the #E line and nothing more
    const out = write(&buf, cfg);
    try std.testing.expectEqualStrings("#E 00 01a0a4\r\n", out);
}
