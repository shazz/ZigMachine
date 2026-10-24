// The copper list (HW 1.9.0, memmap REG_FB_COPPER; fpga/review/COPPER_LIST.md): a plane's per-line
// register writes, applied by the machine on each line the plane covers, after its HBL handler and
// before the line is composited. The board's compositor parses the same words
// (rtl/video/zm_video_copper.v), so every rule here is one the RTL keeps: a list that breaks one
// stops there (the rest of the frame applies nothing), on both machines.
//
// Words (u32, little-endian), line records in increasing raster line:
//   HEAD  0xF << 28 | line << 19 | n     the record of `line` has n body words, then the next HEAD
//                                         (line 511: the end of the list)
//   PAL   0x1 << 28 | first << 20 | k << 12, then k palette words: entries first..first+k-1
//   REG   0x2 << 28 | off << 20 | value   a u16 register of this plane: HSCROLL+2p only
//   FLICK 0x3 << 28                       this plane flickers the border on this line (RES_FLICKER untouched)
//   PALREF 0x4 << 28 | first << 20 | k << 12, then 1 word: the region offset (in VRAM, 4-aligned)
//                                         of k palette words for entries first..first+k-1 (a table
//                                         the cart keeps in VRAM: a scrolling per-row palette costs
//                                         one changed word a line, not k)
//   NOP   0
// Anything else, a PAL past entry 255 or past the record, a REG to another register, a record for
// a line already passed or one the plane does not cover, or a list leaving VRAM: the list stops.
const memmap = @import("sdk/memmap.zig");

pub const END_LINE: u16 = 511;
pub const OP_HEAD: u4 = 0xF;
pub const OP_PAL: u4 = 1;
pub const OP_REG: u4 = 2;
pub const OP_FLICK: u4 = 3;
pub const OP_PALREF: u4 = 4;

/// Where a plane's list stands during its frame: the next record's HEAD and where it sits.
pub const Cursor = struct {
    at: usize = 0, // region offset of the HEAD word
    head: u32 = 0,
    live: bool = false,
};

/// What one line's record does to its plane.
pub const Effects = struct {
    flick: bool = false,
    hscroll: ?u16 = null,
};

const VRAM_END: usize = memmap.OFF_VRAM + memmap.VRAM_BYTES;

fn word(region: []const u8, off: usize) u32 {
    return @as(u32, region[off]) | @as(u32, region[off + 1]) << 8 | @as(u32, region[off + 2]) << 16 |
        @as(u32, region[off + 3]) << 24;
}

fn inVram(off: usize, words: usize) bool {
    return off >= memmap.OFF_VRAM and off + words * 4 <= VRAM_END;
}

/// The cursor of a plane whose REG_FB_COPPER says `v` (0: no list), at its frame's start.
pub fn begin(region: []const u8, v: u16) Cursor {
    if (v == 0) return .{};
    const at = memmap.OFF_VRAM + @as(usize, v) * 16;
    if (!inVram(at, 1)) return .{};
    const head = word(region, at);
    return .{ .at = at, .head = head, .live = head >> 28 == OP_HEAD };
}

pub fn headLine(head: u32) u16 {
    return @intCast((head >> 19) & 0x1FF);
}

/// Raster line `py` of plane `plane`, which the plane covers: apply its record, if it has one.
/// `t.pal(index, rgba)` takes its palette words, in order; a word that breaks a rule stops the
/// list there, what came before it in the record standing (the RTL applies in the same order).
pub fn line(region: []const u8, cur: *Cursor, plane: usize, py: u16, t: anytype) Effects {
    var fx: Effects = .{};
    if (!cur.live) return fx;
    const at_line = headLine(cur.head);
    if (at_line == END_LINE or at_line > py) {
        cur.live = at_line != END_LINE;
        return fx;
    }
    if (at_line < py) return stop(cur, fx); // a record for a line passed or not covered
    const n: usize = cur.head & 0x3FF;
    const body = cur.at + 4;
    if (!inVram(body, n + 1)) return stop(cur, fx);
    var i: usize = 0;
    while (i < n) : (i += 1) {
        const w = word(region, body + i * 4);
        switch (@as(u4, @intCast(w >> 28))) {
            0 => {},
            OP_PAL => {
                const first: usize = (w >> 20) & 0xFF;
                const k: usize = (w >> 12) & 0xFF;
                if (k == 0 or first + k > 256 or i + k >= n) return stop(cur, fx);
                for (0..k) |j| t.pal(@intCast(first + j), word(region, body + (i + 1 + j) * 4));
                i += k;
            },
            OP_REG => {
                const off: usize = (w >> 20) & 0xFF;
                if (off != memmap.REG_HSCROLL + plane * 2) return stop(cur, fx);
                fx.hscroll = @truncate(w);
            },
            OP_FLICK => fx.flick = true,
            OP_PALREF => {
                const first: usize = (w >> 20) & 0xFF;
                const k: usize = (w >> 12) & 0xFF;
                if (k == 0 or first + k > 256 or i + 1 >= n) return stop(cur, fx);
                const src: usize = word(region, body + (i + 1) * 4);
                if (src % 4 != 0 or !inVram(src, k)) return stop(cur, fx);
                for (0..k) |j| t.pal(@intCast(first + j), word(region, src + j * 4));
                i += 1;
            },
            else => return stop(cur, fx),
        }
    }
    cur.at = body + n * 4;
    cur.head = word(region, cur.at);
    if (cur.head >> 28 != OP_HEAD) cur.live = false;
    return fx;
}

fn stop(cur: *Cursor, fx: Effects) Effects {
    cur.live = false;
    return fx;
}
