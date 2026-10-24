// --------------------------------------------------------------------------
// The per-line palettes as copper lists (HW 1.9.0, machine/copper.zig;
// fpga/review/MPP_COPPER.md): the machine loads each line's palette run itself,
// so the CPU makes no palette store a frame. On the board the HBL handler's
// stores (up to 305 a line, ~30 cycles each) were the whole frame: 53 fps
// PER-LINE, 27 fps 4 PLANES.
//
// The picture's decoded palette is copied once a switch into a VRAM table (one
// CHISEL copy), and each enabled plane gets a static list: a line with a record
// is HEAD + PALREF(first, count) naming its run in the table. PALREF's count is 8
// bits, so a 256-entry record (GLOBAL, PER-LINE) is two ops: 255 + the last one.
// Every record is applied, also one equal to the line above (which the handler
// skipped): the palette then holds the same words, so the picture is the same.
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const blob = @import("blob.zig");

const H = blob.H;
const PLANES = blob.PLANES;
// A line: HEAD, PALREF + offset, and a second PALREF + offset for a 256-entry record.
const WORDS = H * 5 + 1;
const HEAD: u32 = 0xF000_0000;
const PALREF: u32 = 0x4000_0000;
const COPY_W: usize = 1024; // the table copy's row: CHISEL boxes, 1 KB a row
// A list names RASTER lines: a normal plane's line y is raster line TOP + y (machine/copper.zig).
const TOP: u32 = zg.VERTICAL_BORDERS_HEIGHT;

var table: zg.VramWords = .{ .words = &.{}, .off = 0 };

/// A table of `colours` words and a list buffer on every plane; false (the HBL handler
/// stays) on a machine without lists or with no VRAM left.
pub fn install(os: *zg.ZigOS, colours: usize) bool {
    table = zg.vramWords(colours) orelse return false;
    for (&os.lfbs) |*fb| if (fb.copperList(WORDS) == null) return false;
    for (&os.lfbs) |*fb| fb.clearFrameBufferHBLHandler();
    return true;
}

/// This picture's palette into the table and each plane's list (enabled: its records;
/// the others: empty). Once a switch: the lists are static until the next one.
pub fn load(os: *zg.ZigOS, view: blob.View, planes: usize) void {
    copyTable(view.pal);
    for (&os.lfbs, 0..) |*fb, p| {
        const l = fb.copperBuffer() orelse continue;
        var w: usize = 0;
        if (p < planes) for (view.map[p * H ..][0..H], 0..) |r, y| record(l, &w, r, y);
        l[w] = HEAD | 511 << 19;
    }
}

fn record(l: []u32, w: *usize, r: blob.Rec, y: usize) void {
    const first: u32 = r.span & 0xffff;
    const n: u32 = r.span >> 16;
    if (n == 0) return;
    const k: u32 = @min(n, 255);
    const src = table.off + r.off;
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

// The palette is built in cart RAM (blob.load); CHISEL copies it in 1 KB rows, the CPU the
// tail and the whole of it where CHISEL cannot (no machine, as in the native tests).
fn copyTable(pal: []const u32) void {
    const src = std.mem.sliceAsBytes(pal);
    const dst = std.mem.sliceAsBytes(table.words)[0..src.len];
    const rows = src.len / COPY_W;
    const done = if (rows > 0 and chiselCopy(dst.ptr, src.ptr, rows)) rows * COPY_W else 0;
    @memcpy(dst[done..], src[done..]);
}

fn chiselCopy(dst: [*]u8, src: [*]const u8, rows: usize) bool {
    const copy = zg.blit.chisel.copy orelse return false;
    return copy(dst, COPY_W, src, COPY_W, COPY_W, rows, null);
}

