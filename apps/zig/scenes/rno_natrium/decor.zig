// --------------------------------------------------------------------------
// The static set the chunky box sits in, drawn once into the BACK buffer and
// brought on screen by the zoom-in:
//   $E828 / $E980  blue background bands, the cleared box, its white outline
//                  (the two routines differ only in the box's x)
//   $C722          a 48x100 crop of a girl picture, pixel-doubled to 96x200,
//                  with a 1-px pen-15 border OR'd down both sides
// --------------------------------------------------------------------------
const A = @import("assets.zig");
const st = @import("st.zig");
const Screen = st.Screen;

/// $EAF0 fills a whole line with 20 x (move.l d1, move.l d2), d2 = 0; the
/// seven bands run (lines, plane-0/1 long) top to bottom.
const BANDS = [_]struct { lines: usize, planes01: u32 }{
    .{ .lines = 0x23, .planes01 = 0x0000FFFF }, // pen 2
    .{ .lines = 0x05, .planes01 = 0xFFFF0000 }, // pen 1
    .{ .lines = 0x0A, .planes01 = 0x0000FFFF },
    .{ .lines = 0x64, .planes01 = 0xFFFF0000 },
    .{ .lines = 0x0A, .planes01 = 0x0000FFFF },
    .{ .lines = 0x05, .planes01 = 0xFFFF0000 },
    .{ .lines = 0x23, .planes01 = 0x0000FFFF },
};

inline fn setL(s: *Screen, off: usize, v: u32) void {
    st.setW(s, off, @truncate(v >> 16));
    st.setW(s, off + 2, @truncate(v));
}

inline fn orL(s: *Screen, off: usize, v: u32) void {
    st.orW(s, off, @truncate(v >> 16));
    st.orW(s, off + 2, @truncate(v));
}

/// $E828 (box_group 1, x = 16) or $E980 (box_group 9, x = 144).
pub fn decoration(s: *Screen, box_group: usize) void {
    var line: usize = 0;
    for (BANDS) |b| {
        for (0..b.lines) |_| {
            for (0..20) |g| {
                setL(s, line * st.LINE + g * 8, b.planes01);
                setL(s, line * st.LINE + g * 8 + 4, 0);
            }
            line += 1;
        }
    }
    // Box interior, lines 20..179, ten groups, all four planes cleared.
    for (20..180) |y| @memset(s[y * st.LINE + box_group * 8 ..][0..80], 0);
    // Lines 19 and 180 over the box width: planes 0,1 set, 2,3 clear = pen 3.
    for ([_]usize{ 19, 180 }) |y| {
        for (0..10) |g| {
            const o = y * st.LINE + (box_group + g) * 8;
            setL(s, o, 0xFFFFFFFF);
            setL(s, o + 4, 0);
        }
    }
    // The verticals: bit 0 of the group left of the box, bit 15 of the group
    // right of it, planes 0+1, 162 lines from 19.
    for (19..19 + 0xA2) |y| {
        orL(s, y * st.LINE + (box_group - 1) * 8, 0x00010001);
        orL(s, y * st.LINE + (box_group - 1) * 8 + 0x58, 0x80008000);
    }
}

/// $C722: 6 source bytes (48 px) x 100 rows from an ILBM body at `src_off`,
/// each byte bit-doubled to a group, each row written to two lines, from
/// group `g` (the border group) on line 0.
pub fn panel(s: *Screen, body: []const u8, src_off: usize, g: usize) void {
    for (0..100) |r| {
        const src = body[src_off + r * st.LINE ..];
        for (0..2) |dy| {
            const o = (2 * r + dy) * st.LINE + g * 8;
            orL(s, o, 0x00010001); // bit 0 of all four planes: x = 16g + 15
            orL(s, o + 4, 0x00010001);
            for (0..6) |b| {
                const q = o + (1 + b) * 8;
                for (0..4) |p| st.setW(s, q + 2 * p, A.pix_double[src[b + p * 0x28]]);
            }
            orL(s, o + 56, 0x80008000); // bit 15, all planes, the group after
            orL(s, o + 60, 0x80008000);
        }
    }
}
