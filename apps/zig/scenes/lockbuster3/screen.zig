// --------------------------------------------------------------------------
// LOCKBUSTER 3 -- the plane side: two overscan PAGES and a screen-base flip.
//
// The Go double-buffers its 320x240 index canvas (buffers[0], buffers[1]) and
// the two buffers never converge: a panel frame drawn into one is not drawn
// into the other, so a single framebuffer showing them in turn would have to be
// rewritten wherever they differ (the old compose() stored all 76,800 bytes a
// frame, 94 % of them unchanged). Instead the plane holds one 400x280 overscan
// page PER buffer (a 400x560 overscan-scroll buffer) and shows the front one
// by moving the plane's read base -- the ST's own screen swap. Each page then
// only takes what its buffer changed since that page was last shown: the
// rectangles step() wrote (letters' restore + draw, the panel, the meters),
// recorded per buffer by mark(). The text band (rows 160..199) is recomposed
// whole on each new tick from the scroll clock's cells, a u32 at a time:
// (index & 0xFE) | text bit, the shader's LSB replacement.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const assets = @import("assets.zig");

pub const W: usize = 320;
pub const H: usize = 240;
pub const PHYS_W: usize = 400;
pub const PHYS_H: usize = 280;
pub const BORDER_X: usize = 40;
pub const BORDER_Y: usize = 40;
pub const TEXT_ROW: usize = 160;
pub const TEXT_END: usize = 200;
const PAGE_BYTES = PHYS_W * PHYS_H;
const MAX_RECTS = 48;

const Rect = struct { x: u16, y: u16, w: u16, h: u16 };

const Dirty = struct {
    n: usize = 0,
    full: bool = true,
    band: bool = true,
    r: [MAX_RECTS]Rect = undefined,
};

var dirty: [2]Dirty = .{ .{}, .{} };
var shown: u32 = 0xFFFF_FFFF; // the page FB_BASE points at (none yet)

/// Both pages are stale as a whole (init).
pub fn reset() void {
    dirty = .{ .{}, .{} };
    shown = 0xFFFF_FFFF;
}

/// step() wrote (x, y, w, h) of buffers[buf]: that page owes the rectangle.
pub fn mark(buf: usize, x: i32, y: i32, w: i32, h: i32) void {
    const x0 = @max(x, 0);
    const y0 = @max(y, 0);
    const x1 = @min(x + w, @as(i32, W));
    const y1 = @min(y + h, @as(i32, H));
    if (x1 <= x0 or y1 <= y0) return;
    const d = &dirty[buf];
    if (d.full) return;
    if (d.n == MAX_RECTS) {
        d.full = true;
        return;
    }
    d.r[d.n] = .{ .x = @intCast(x0), .y = @intCast(y0), .w = @intCast(x1 - x0), .h = @intCast(y1 - y0) };
    d.n += 1;
}

/// A tick moved the scroll clock: both pages' text bands are stale.
pub fn markTick() void {
    dirty[0].band = true;
    dirty[1].band = true;
}

fn copyRows(page: []u8, src: []const u8, r: Rect) void {
    for (r.y..@as(usize, r.y) + r.h) |gy| {
        if (gy >= TEXT_ROW and gy < TEXT_END) continue; // the band is recomposed whole
        const at = (BORDER_Y + gy) * PHYS_W + BORDER_X + r.x;
        @memcpy(page[at..][0..r.w], src[gy * W + r.x ..][0..r.w]);
    }
}

// A cell row's 8 text bits (MSB = leftmost pixel) as two little-endian words
// of 0/1 bytes, one nibble at a time.
const expand: [16]u32 = blk: {
    var t: [16]u32 = undefined;
    for (0..16) |n| t[n] = (n >> 3 & 1) | (n >> 2 & 1) << 8 | (n >> 1 & 1) << 16 | (n & 1) << 24;
    break :blk t;
};

// The Go's initialBit() packed per cell row: bit 0 of the artwork's rows 0..39
// (the text band's own picture before the scroller reaches a cell), built at
// compile time from the same background.bin.
const initial_bytes: [2][20][40]u8 = blk: {
    @setEvalBranchQuota(100_000);
    var t: [2][20][40]u8 = undefined;
    for (0..2) |lane| for (0..20) |dy| for (0..40) |slot| {
        var b: u8 = 0;
        for (0..8) |dx| b |= (assets.background[(lane * 20 + dy) * W + slot * 8 + dx] & 1) << (7 - dx);
        t[lane][dy][slot] = b;
    };
    break :blk t;
};

/// One cell row of the text layer: the Go's fontBit() for 8 dx at once (the
/// glyph column starts on a byte, x = glyph%16*32 + column*8).
fn cellByte(c: anytype, lane: usize, slot: usize, dy: usize) u8 {
    if (c.initial != 0) return initial_bytes[lane][dy][slot];
    const g: usize = c.glyph;
    return assets.fonts[c.font & 1][(g / 16 * 20 + dy) * 64 + g % 16 * 4 + c.column];
}

fn composeBand(page: []u8, src: []const u8, columns: anytype) void {
    for (TEXT_ROW..TEXT_END) |gy| {
        const lane = (gy - TEXT_ROW) / 20;
        const dy = (gy - TEXT_ROW) % 20;
        const d: [*]u32 = @ptrCast(@alignCast(page.ptr + (BORDER_Y + gy) * PHYS_W + BORDER_X));
        const s: [*]const u32 = @ptrCast(@alignCast(src.ptr + gy * W));
        for (0..40) |slot| {
            const b = cellByte(columns[lane][slot], lane, slot, dy);
            d[slot * 2] = (s[slot * 2] & 0xFEFE_FEFE) | expand[b >> 4];
            d[slot * 2 + 1] = (s[slot * 2 + 1] & 0xFEFE_FEFE) | expand[b & 15];
        }
    }
}

/// Bring buffers[front]'s page up to date and point the plane at it.
pub fn present(fb: *zg.LogicalFB, front: usize, src: []const u8, columns: anytype) void {
    const page = fb.fb[front * PAGE_BYTES ..][0..PAGE_BYTES];
    const d = &dirty[front];
    if (d.full) {
        copyRows(page, src, .{ .x = 0, .y = 0, .w = W, .h = H });
    } else {
        for (d.r[0..d.n]) |r| copyRows(page, src, r);
    }
    d.n = 0;
    d.full = false;
    if (d.band) composeBand(page, src, columns);
    d.band = false;
    if (shown != front) {
        fb.setScroll(0, @intCast(front * PHYS_H));
        shown = @intCast(front);
    }
}
