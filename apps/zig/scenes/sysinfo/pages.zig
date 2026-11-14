// --------------------------------------------------------------------------
// SysInfo — the pages. HWAM's SysInfo 8.34 is a full-screen page of
// "LABEL : value" lines in two columns under underlined headings, the program
// line on top with the page number at the right, and the prompt for its menu
// at the bottom. One page per panel of the ST original, translated to this
// machine; each page file fills the grid between the top and bottom lines.
//
// What a cart cannot read shows "n/a" (N_A): never a constant standing in for
// a value the machine did not give.
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const grid = @import("grid.zig");
const probe = @import("probe.zig");
const diskinfo = @import("diskinfo.zig");
const Bench = @import("bench.zig").Bench;
const sound_list = @import("sound_list.zig");
const ident = @import("ident.zig");

pub const N_A = "n/a";
pub const VERSION = "2.0";
/// The newest system-table entry this cart imports: guiSetscreen (table 1.25, the resolution
/// key). The board refuses a cart whose table is newer than its own, so a cart that runs there
/// proves at least this much; keep it in step with the imports.
pub const TABLE_MIN = "1.25";

pub const Page = enum(u8) { system, video, sound, disk, speed };
pub const COUNT = @typeInfo(Page).@"enum".fields.len;

pub const File = struct { name: [16]u8, len: u32, kind: u8 };
pub const MAX_FILES: usize = 24; // a ZMDISK FAT holds 24 entries

/// Everything a page reads, gathered by the app: the machine is asked live
/// (probe.zig) and the slow facts (disk, blitter test) once, at start.
pub const Ctx = struct {
    os: *const zg.ZigOS,
    bench: *const Bench,
    blit: probe.Blit,
    disk: ?diskinfo.Info,
    files: []const File,
    snd: *const sound_list.List, // the SOUND page's files: which is selected, which plays
    gem_ok: bool, // the ROM handed out a GEM context
    dialog_ok: bool, // ... and a dialog
    frame_us: u32, // measured frame period (hostMicros), 0 = no clock
    id: *const ident.Ident, // what the machine is, asked once at start
    ref: u8, // the speed tests' reference machine (refs.REFS)
};

pub fn compose(g: *grid.Grid, page: Page, c: *const Ctx) void {
    g.clear();
    frame(g, page, c);
    switch (page) {
        .system => @import("page_sys.zig").fill(g, c),
        .video => @import("page_video.zig").fill(g, c),
        .sound => @import("page_sound.zig").sound(g, c),
        .disk => @import("page_disk.zig").fill(g, c),
        .speed => @import("page_bench.zig").fill(g, c),
    }
}

/// The program line on top and the prompt at the bottom, on every page.
fn frame(g: *grid.Grid, page: Page, c: *const Ctx) void {
    g.put(0, 1, "SYSINFO FOR ZIGMACHINE, VERSION " ++ VERSION ++ "  (AFTER HWAM SYSINFO 8.34)", .small);
    var n = "PAGE 0".*;
    n[5] = '1' + @intFromEnum(page);
    g.put(0, 73, &n, .small);
    g.put(24, 1, "PRESS SPACE OR CLICK FOR MENU !", .small);
    const clock = if (c.bench.clocked or c.frame_us != 0) "HOST CLOCK: YES" else "HOST CLOCK: NONE";
    g.put(24, grid.COLS - 1 - clock.len, clock, .small);
}

/// A section heading: underlined, as HWAM's.
pub fn heading(g: *grid.Grid, row: usize, col: usize, s: []const u8) void {
    g.put(row, col, s, .under);
}

/// "$1A2B3C", the way SysInfo shows addresses.
pub fn hexField(g: *grid.Grid, row: usize, col: usize, label: []const u8, v: u32) void {
    g.fieldf(row, col, label, "${X:0>6}", .{v});
}

/// A byte count right-aligned in Kbytes, HWAM's unit.
pub fn kbField(g: *grid.Grid, row: usize, col: usize, label: []const u8, bytes: u32) void {
    g.fieldf(row, col, label, "{d:>9} Kbytes", .{bytes / 1024});
}

pub fn bytesField(g: *grid.Grid, row: usize, col: usize, label: []const u8, bytes: u32) void {
    g.fieldf(row, col, label, "{d:>9} Bytes", .{bytes});
}

/// One decimal of a x10 integer: "12.3".
pub fn tenths(buf: []u8, v10: u64) []const u8 {
    return std.fmt.bufPrint(buf, "{d}.{d}", .{ v10 / 10, v10 % 10 }) catch "?";
}

/// A YYYYMMDD stamp as YYYY-MM-DD; 0 = never stamped.
pub fn date(buf: []u8, d: u32) []const u8 {
    if (d == 0) return N_A;
    return std.fmt.bufPrint(buf, "{d}-{d:0>2}-{d:0>2}", .{ d / 10000, d / 100 % 100, d % 100 }) catch "?";
}
