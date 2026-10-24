// --------------------------------------------------------------------------
// The demo's Amiga copper list, rebuilt at COMPILE time word for word as its
// $02C2 builds it in chip RAM (screen+$1900, 12,846 words, ending at $7D5C where
// the blitter's save row starts), then TRANSLATED into the machine's tables by
// walking it the way the copper does: WAIT = "from this line", MOVE = a register
// write. Pure (no zigos): amiga_copper_test.zig checks it natively.
//
//   [COLOR00 0][WAIT $2F0F] ... 17 pairs     the top bar's moves 1..16 ($025E fills them)
//   [COLOR00 0] + the 30-word template ($081A: DIW, DDF, BPLCON0-2, mods, BPLxPT,
//                COLOR09 $888, COLOR00 0)
//   192 x [WAIT line,$4F][32 x MOVE COLOR01]   lines $40..$FF, the text's colours
//   [WAIT $FFDD][WAIT $080D]                   past line 255 (PAL)
//   [COLOR00 0][WAIT $090F] ... 17 pairs     the bottom bar: moves 19..34
//   [WAIT $FFFF]                             the end
// --------------------------------------------------------------------------
const std = @import("std");

pub const TEMPLATE = @embedFile("../../assets/screens/hippel_musicdisk/copper.bin"); // $081A, 30 words
pub const TABLES = @embedFile("../../assets/screens/hippel_musicdisk/tables.bin"); // $0678..$0817

pub const COLOR00: u16 = 0x180; // the background, and the border: the bars
pub const COLOR01: u16 = 0x182; // playfield 1's one colour: the text
pub const COLOR09: u16 = 0x192; // playfield 2's one colour: the shadow
const DIWSTRT: u16 = 0x08E;

/// $0372's four 16-line blocks (first colour, step per line), made 3 times.
const BLOCKS = [4][2]u16{ .{ 0x000, 0x100 }, .{ 0xF00, 0x010 }, .{ 0xFF0, 0xFF00 }, .{ 0x0F0, 0xFFF0 } };
pub const TEXT_ROWS = 192; // copper rows of COLOR01 moves, lines $40..$FF
pub const COLUMNS = 32; // MOVEs a row: each lasts 4 colour clocks = 8 low-res pixels
pub const BAR_LINES = 16;
pub const LEN = 17 * 4 + 2 + TEMPLATE.len / 2 + TEXT_ROWS * (2 + 2 * COLUMNS) + 4 + 17 * 4 + 2;

const List = struct {
    w: [LEN]u16 = undefined,
    n: usize = 0,
    fn put(l: *List, a: u16, b: u16) void {
        l.w[l.n] = a;
        l.w[l.n + 1] = b;
        l.n += 2;
    }
};

fn be16(s: []const u8, i: usize) u16 {
    return @as(u16, s[i]) << 8 | s[i + 1];
}

/// 17 x [COLOR00 0][WAIT w]: a bar's moves ($025E fills them each frame).
fn barPairs(l: *List, first_wait: u16) void {
    var w = first_wait;
    for (0..17) |_| {
        l.put(COLOR00, 0);
        l.put(w, 0xFFFE);
        w += 0x100;
    }
}

/// $0372: 16 lines of [WAIT line,$4E][32 x COLOR01], base+0..15 then 15..0.
fn textBlock(l: *List, line: *u16, b: [2]u16) void {
    var c = b[0];
    for (0..16) |_| {
        line.* = (line.* & 0xFF00) | 0x4F; // move.b #$4f,d1: WAIT at hpos $4E
        l.put(line.*, 0xFFFE);
        for (0..16) |_| {
            l.put(COLOR01, c);
            c +%= 1;
        }
        for (0..16) |_| {
            c -%= 1;
            l.put(COLOR01, c);
        }
        c +%= b[1];
        line.* +%= 0x100;
    }
}

/// The list as $02C2 leaves it (the bar moves still 0, BPLxPT not yet patched).
pub fn build() [LEN]u16 {
    @setEvalBranchQuota(200_000);
    var l: List = .{};
    barPairs(&l, 0x2F0F);
    l.put(COLOR00, 0);
    for (0..TEMPLATE.len / 4) |i| l.put(be16(TEMPLATE, 4 * i), be16(TEMPLATE, 4 * i + 2));
    var line: u16 = 0x4000;
    for (0..3) |_| for (BLOCKS) |b| textBlock(&l, &line, b);
    l.put(0xFFDD, 0xFFFE);
    l.put(0x080D, 0xFFFE);
    barPairs(&l, 0x090F);
    l.put(0xFFFF, 0xFFFE);
    std.debug.assert(l.n == LEN);
    return l.w;
}

pub const AMIGA_LIST = build();

/// What the copper does with the list, per beam line (0..311).
pub const Walk = struct {
    move00_line: [40]u16 = @splat(0), // the line each COLOR00 move takes effect on
    move00_count: usize = 0,
    text: [TEXT_ROWS][COLUMNS]u16 = undefined, // COLOR01 per (line - $40, move)
    color09: u16 = 0,
    diw_line: u16 = 0,
};

/// A WAIT's vertical compare is 8 bits: past line 255 the beam's low byte wraps,
/// so a smaller VP means the next 256.
fn waitLine(at: u16, vp: u16) u16 {
    const c = (at & 0x100) | vp;
    return if (c < at) c + 0x100 else c;
}

/// One MOVE as the copper applies it on `line` (`col`: its place after the WAIT).
fn move(r: *Walk, line: u16, col: *usize, reg: u16, v: u16) void {
    switch (reg) {
        COLOR00 => {
            r.move00_line[r.move00_count] = line;
            r.move00_count += 1;
        },
        COLOR01 => {
            r.text[line - 0x40][col.*] = v;
            col.* += 1;
        },
        COLOR09 => r.color09 = v,
        DIWSTRT => r.diw_line = v >> 8,
        else => {},
    }
}

pub fn walk(list: []const u16) Walk {
    @setEvalBranchQuota(400_000);
    var r: Walk = .{};
    var line: u16 = 0;
    var col: usize = 0;
    var i: usize = 0;
    while (i < list.len) : (i += 2) {
        const a = list[i];
        if (a & 1 == 0) {
            move(&r, line, &col, a, list[i + 1]);
            continue;
        }
        if (a == 0xFFFF) break; // WAIT $FFFF,$FFFE: the end
        line = waitLine(line, a >> 8);
        col = 0;
    }
    return r;
}

pub const WALK = walk(&AMIGA_LIST);

/// $025E writes the top bar into COLOR00 moves 1..16 ($190A + 8j) and the bottom
/// one into moves 19..34 ($7CD2 + 8j).
pub const TOP_MOVE = 1;
pub const BOTTOM_MOVE = 19;

/// A 12-bit Amiga colour as the palette stores it (opaque RGBA, n * $11 a channel).
pub fn rgba(v: u16) u32 {
    const r: u32 = (v >> 8) & 15;
    const g: u32 = (v >> 4) & 15;
    const b: u32 = v & 15;
    return 0xFF00_0000 | (b * 0x11) << 16 | (g * 0x11) << 8 | r * 0x11;
}

pub const TEXT_RGBA: [TEXT_ROWS][COLUMNS]u32 = blk: {
    @setEvalBranchQuota(100_000);
    var t: [TEXT_ROWS][COLUMNS]u32 = undefined;
    for (0..TEXT_ROWS) |y| for (0..COLUMNS) |x| {
        t[y][x] = rgba(WALK.text[y][x]);
    };
    break :blk t;
};

fn word(i: usize) u16 {
    return be16(TABLES, 2 * i);
}

/// $025E: per channel, the bar table minus the grey shade ($0678), floored at 0.
fn shade(t: u16, g: u16) u16 {
    var v: u16 = 0;
    for ([_]u16{ 0xF00, 0x0F0, 0x00F }) |m| v |= if (t & m > g & m) (t & m) - (g & m) else 0;
    return v;
}

/// The bar a frame shows after `p` rotations: $0298 turns the top table LEFT,
/// $02AC the bottom one RIGHT. Their pattern (4 blue, 4 magenta) repeats every 8.
fn bars(comptime first: usize, comptime left: bool) [8][BAR_LINES]u32 {
    @setEvalBranchQuota(20_000);
    var t: [8][BAR_LINES]u32 = undefined;
    for (0..8) |p| for (0..BAR_LINES) |j| {
        const k = if (left) (j + p) % 16 else (j + 16 - p) % 16;
        t[p][j] = rgba(shade(word(first + k), word(j)));
    };
    return t;
}

pub const TOP_BAR = bars(16, true); // $0698
pub const BOTTOM_BAR = bars(32, false); // $06B8
