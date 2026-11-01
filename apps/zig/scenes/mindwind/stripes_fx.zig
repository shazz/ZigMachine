// --------------------------------------------------------------------------
// Part A: the 180 field lines (14..193) each pick a stripe row, the demo's six
// ways (TEXT-relative addresses of the depacked MINDWIND.TOS; "row table" =
// $42A4, 128 rows of the last pass, or $41A4, the 16 32-row zoom blocks):
//   flat   $3932  every line the same row, stepping 2 rows a frame
//   pulse  $3962  every line the same row, a sum of four sines
//   moire  $3A1C  (kernel $C10) a row per line: four sines + a phase, halved
//   blocks $3C0A  (kernel $E96) a zoom block per line, scrolling inside it
//   swirl  $3E18  (kernel $111C) as moire with other steps
//   bands  $4000  (kernel $13A2) a zoom block per line from two sines
// The last four run inside the demo's fullscreen kernel, two lines a loop, for
// the frame being shown; the phases they keep persist across the whole demo,
// as in the original (the second half replays them from where they stopped).
// Word arithmetic wraps as the 68000's does.
// --------------------------------------------------------------------------
const data = @import("data.zig");
const lines = @import("lines.zig");
const vram = @import("vram.zig");
const gen = @import("stripes_gen.zig");

pub const Kind = enum { flat, pulse, moire, blocks, swirl, bands };
const FIRST: usize = 14;
const N: usize = 180;

var flat_ctr: u16 = 0; // the self-modified immediate at $3948
var pulse: [4]u16 = .{ 0, 0, 0, 0 }; // $39B8
var moire_p: u16 = 0; // $3BA8
var moire: [4]u16 = .{ 0, 0, 0, 0 }; // $3BAA
var blocks_r: u16 = 0; // $3DB4
var blocks: [4]u16 = .{ 0xe6, 0xe6, 0xe6, 0xe6 }; // $3DB6
var swirl_p: u16 = 0; // $3FA6
var swirl: [4]u16 = .{ 0, 0, 0, 0 }; // $3FA8
var bands_r: u16 = 0; // $419A
var bands: [4]u16 = .{ 0xe6, 0xe6, 0xe6, 0xe6 }; // $419C

inline fn s208(off: u16) u16 {
    return data.be16(data.sin_208c, (off & 0x7ff) / 2);
}
inline fn s288(off: u16) u16 {
    return data.be16(data.tab_288c, (off & 0x7ff) / 2);
}
/// A row table entry (its byte offset into the table, as the demo indexes) to a line source.
inline fn row42(off: u16) u32 {
    return rowSrc(data.le16(data.lines_42a4, (off & 0x1fc) / 4), 0);
}
inline fn row41(off: u16, extra_bytes: u16) u32 {
    return rowSrc(data.le16(data.lines_41a4, (off & 0xfc) / 4), extra_bytes);
}
inline fn rowSrc(r: u16, extra_bytes: u16) u32 {
    // the tables point 8 bytes (16 px) into the row; a byte offset is 2 px
    return vram.stripes + @as(u32, r) * gen.ROW_PX + 16 + @as(u32, extra_bytes) * 2;
}

fn same(src: u32) void {
    lines.fill(FIRST, N, src, 0);
}

pub fn step(kind: Kind) void {
    switch (kind) {
        .flat => {
            flat_ctr +%= 8;
            same(row42(flat_ctr));
        },
        .pulse => {
            same(row42(s208(pulse[0]) +% s208(pulse[1]) +% s208(pulse[2]) +% s208(pulse[3])));
            for (&pulse) |*p| p.* +%= 8;
        },
        .moire => {
            moire_p +%= 8;
            var d = moire;
            for (0..N) |i| {
                const v = (s208(d[0]) +% s208(d[1]) +% s208(d[2]) +% s208(d[3]) +% moire_p) >> 1;
                lines.table[FIRST + i] = .{ .src = row42(v), .colour = 0 };
                d[0] +%= 4;
                d[1] +%= 2;
                d[2] +%= 6;
                d[3] +%= 4;
            }
            moire[3] +%= 0xe;
            moire[2] +%= 0xa;
            moire[1] +%= 6;
            moire[0] +%= 0xfff8;
        },
        .blocks => {
            blocks_r +%= 0xd0;
            if (blocks_r == 0x1a00) blocks_r = 0;
            var d4 = blocks[2];
            for (0..N) |i| {
                const v = (s288(d4) *% 4) >> 1;
                lines.table[FIRST + i] = .{ .src = row41(v, blocks_r), .colour = 0 };
                d4 +%= 8;
            }
        },
        .swirl => {
            swirl_p +%= 0x18;
            var d = swirl;
            for (0..N) |i| {
                const v = (s208(d[0]) +% s208(d[1]) +% s208(d[0]) +% s208(d[3]) +% swirl_p) >> 1;
                lines.table[FIRST + i] = .{ .src = row42(v), .colour = 0 };
                d[0] +%= 0xc;
                d[1] +%= 0x10;
                d[3] +%= 0x12;
            }
            swirl[3] +%= 0xc;
            swirl[2] +%= 0xe;
            swirl[1] +%= 0x1a;
            swirl[0] +%= 0x22;
        },
        .bands => {
            bands_r +%= 0xd0; // kept, never added ($4000 computes it and does not use it)
            if (bands_r == 0x1a00) bands_r = 0;
            var d2 = bands[0];
            var d4 = bands[2];
            for (0..N) |i| {
                const v = (s288(d2) *% 2 +% s288(d4) *% 2) >> 1;
                lines.table[FIRST + i] = .{ .src = row41(v, 0), .colour = 0 };
                d2 +%= 8;
                d4 +%= 8;
            }
            bands[3] +%= 0x10;
            bands[2] +%= 0x10;
            bands[1] -%= 0x10;
            bands[0] -%= 0x10;
        },
    }
}
