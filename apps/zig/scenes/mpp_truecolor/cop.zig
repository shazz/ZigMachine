// --------------------------------------------------------------------------
// The per-line palettes as copper lists (HW 1.9.0, machine/copper.zig;
// fpga/review/MPP_COPPER.md): the machine loads each line's palette run itself,
// so the CPU makes no palette store a frame. On the board the HBL handler's
// stores (up to 305 a line, ~30 cycles each) were the whole frame: 53 fps
// PER-LINE, 27 fps 4 PLANES.
//
// The picture's decoded palette is copied once a switch into a VRAM table (one
// CHISEL copy), and plane 0 (the only indexed plane since mode 3 became one
// true-colour plane, HW 1.15.0) gets a static list: a line with a record
// is HEAD + PALREF(first, count) naming its run in the table. PALREF's count is 8
// bits, so a 256-entry record (GLOBAL, PER-LINE) is two ops: 255 + the last one.
// Every record is applied, also one equal to the line above (which the handler
// skipped): the palette then holds the same words, so the picture is the same.
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const blob = @import("blob.zig");

const H = blob.H;
// A line: HEAD, PALREF + offset, and a second PALREF + offset for a 256-entry record.
const WORDS = H * 5 + 1;
const HEAD: u32 = 0xF000_0000;
const PALREF: u32 = 0x4000_0000;
const COPY_W: usize = 1024; // the table copy's row: CHISEL boxes, 1 KB a row
// A list names RASTER lines: a normal plane's line y is raster line TOP + y (machine/copper.zig).
const TOP: u32 = zg.VERTICAL_BORDERS_HEIGHT;

// Two tables when VRAM has room: the next picture's palette is copied into the one no list
// names while the current picture shows (mpp_truecolor/stage.zig), then `commit` points the
// lists at it in one frame. With one table the copy and the commit share the switch frame.
var tables: [2]zg.VramWords = .{ .{ .words = &.{}, .off = 0 }, .{ .words = &.{}, .off = 0 } };
var count: usize = 0;
var shown: usize = 0; // the table the lists name

/// The tables and plane 0's list buffer; false (the HBL handler stays) on a machine without
/// lists or with no VRAM left. The second table is optional (`spread`).
pub fn install(os: *zg.ZigOS, colours: usize) bool {
    tables[0] = zg.vramWords(colours) orelse return false;
    count = 1;
    if (os.lfbs[0].copperList(WORDS) == null) return false;
    os.lfbs[0].clearFrameBufferHBLHandler();
    if (zg.vramWords(colours)) |t| {
        tables[1] = t;
        count = 2;
    }
    return true;
}

/// Whether the next palette can be staged while the current one shows (two tables).
pub fn spread() bool {
    return count == 2;
}

fn spare() usize {
    return (shown + 1) % count;
}

/// Table rows this palette takes: 1 KB each, the last one partial.
pub fn tableRows(pal: []const u32) usize {
    return (pal.len * 4 + COPY_W - 1) / COPY_W;
}

/// Copy table rows [from, from + rows) of this palette into the spare table (CHISEL 1 KB
/// rows, the CPU the tail and the whole of it where CHISEL cannot, as in the native tests).
/// Returns the next row; done at tableRows(pal).
pub fn copyRows(pal: []const u32, from: usize, rows: usize) usize {
    const src = std.mem.sliceAsBytes(pal);
    const dst = std.mem.sliceAsBytes(tables[spare()].words)[0..src.len];
    const end = @min(tableRows(pal), from +| rows);
    const whole = @min(end, src.len / COPY_W);
    const done = if (whole > from and chiselCopy(dst[from * COPY_W ..].ptr, src[from * COPY_W ..].ptr, whole - from)) whole * COPY_W else from * COPY_W;
    const stop = @min(src.len, end * COPY_W);
    if (stop > done) @memcpy(dst[done..stop], src[done..stop]);
    return end;
}

/// Name the spare table (copied by copyRows) in plane 0's list: its records when `on` (an
/// indexed mode), else empty (the true-colour mode: no table is copied, none changes hands).
/// Once a switch: the list is static until the next one.
pub fn commit(os: *zg.ZigOS, view: blob.View, on: bool) void {
    const l = os.lfbs[0].copperBuffer() orelse return;
    var w: usize = 0;
    if (on) {
        shown = spare();
        for (view.map[0..H], 0..) |r, y| record(l, &w, r, y);
    }
    l[w] = HEAD | 511 << 19;
}

/// Copy and commit in one go (init, and the failure screen's empty list).
pub fn load(os: *zg.ZigOS, view: blob.View, on: bool) void {
    _ = copyRows(view.pal, 0, tableRows(view.pal));
    commit(os, view, on);
}

fn record(l: []u32, w: *usize, r: blob.Rec, y: usize) void {
    const first: u32 = r.span & 0xffff;
    const n: u32 = r.span >> 16;
    if (n == 0) return;
    const k: u32 = @min(n, 255);
    const src = tables[shown].off + r.off;
    const body: u32 = if (n > 255) 4 else 2;
    l[w.*] = HEAD | (TOP + @as(u32, @intCast(y))) << 19 | body;
    l[w.* + 1] = PALREF | first << 20 | k << 12;
    l[w.* + 2] = src;
    w.* += 3;
    if (n <= 255) return;
    l[w.*] = PALREF | (first + 255) << 20 | 1 << 12;
    l[w.* + 1] = src + 255 * 4;
    w.* += 2;
}

fn chiselCopy(dst: [*]u8, src: [*]const u8, rows: usize) bool {
    const copy = zg.blit.chisel.copy orelse return false;
    return copy(dst, COPY_W, src, COPY_W, COPY_W, rows, null);
}

