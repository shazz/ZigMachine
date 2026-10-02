// Tiny Stuff (.TNY) pictures, decoded the way DUNE.PRG's own routine does it
// ($3D6A): control bytes over a stream of words, the words laid down a COLUMN
// at a time -- every line of plane 0's first 16-pixel group, then the next
// group, ..., then plane 1 -- straight into chunky palette indices.
const std = @import("std");

pub const W = 320;
pub const H = 200;

pub const Picture = struct {
    palette: [16]u16,
    px: [W * H]u8, // palette index of every pixel
};

/// Walks the screen in Tiny's order: line, then 16-pixel group, then plane.
const Cursor = struct {
    y: usize = 0,
    group: usize = 0,
    plane: u3 = 0,

    fn put(c: *Cursor, px: *[W * H]u8, word: u16) void {
        if (c.plane < 4) {
            const base = c.y * W + c.group * 16;
            for (0..16) |i| {
                const bit: u8 = @intCast((word >> @intCast(15 - i)) & 1);
                px[base + i] |= bit << c.plane;
            }
        }
        c.y += 1;
        if (c.y < H) return;
        c.y = 0;
        c.group += 1;
        if (c.group < W / 16) return;
        c.group = 0;
        c.plane +|= 1;
    }
};

fn be16(b: []const u8, at: usize) u16 {
    return std.mem.readInt(u16, b[at..][0..2], .big);
}

/// Decode `file` into `out`. False on a file too short for its own header or
/// a stream that runs past its end.
pub fn decode(file: []const u8, out: *Picture) bool {
    if (file.len < 1) return false;
    const head: usize = if (file[0] > 2) 5 else 1; // colour-cycling info
    if (file.len < head + 36) return false;
    for (&out.palette, 0..) |*c, i| c.* = be16(file, head + 2 * i);
    const nctl = be16(file, head + 32);
    const nwords = be16(file, head + 34);
    if (file.len < head + 36 + nctl) return false;
    const ctl = file[head + 36 ..][0..nctl];
    const words = file[head + 36 + nctl ..];
    if (words.len < 2 * @as(usize, nwords)) return false;
    @memset(&out.px, 0);
    return runs(ctl, words, nwords, &out.px);
}

/// The control bytes: 0 a repeated word, 1 literal words, each with a count
/// word after it; any other byte its own signed count (> 0 repeated).
fn runs(ctl: []const u8, words: []const u8, nwords: usize, px: *[W * H]u8) bool {
    var cur: Cursor = .{};
    var wi: usize = 0;
    var i: usize = 0;
    while (i < ctl.len) {
        const c = ctl[i];
        var n: usize = undefined;
        var repeat: bool = undefined;
        if (c <= 1) {
            if (i + 3 > ctl.len) return false;
            n = be16(ctl, i + 1);
            repeat = c == 0;
            i += 3;
        } else {
            const s: i8 = @bitCast(c);
            repeat = s > 0;
            n = @abs(s);
            i += 1;
        }
        if (!emit(&cur, px, words, &wi, nwords, n, repeat)) return false;
    }
    return true;
}

fn emit(cur: *Cursor, px: *[W * H]u8, words: []const u8, wi: *usize, nwords: usize, n: usize, repeat: bool) bool {
    for (0..n) |_| {
        if (wi.* >= nwords) return false;
        cur.put(px, be16(words, 2 * wi.*));
        if (!repeat) wi.* += 1;
    }
    if (repeat) wi.* += 1;
    return true;
}

test "a Tiny file shorter than its header does not decode" {
    var pic: Picture = undefined;
    try std.testing.expect(!decode(&[_]u8{}, &pic));
    try std.testing.expect(!decode(&([_]u8{0} ** 20), &pic));
    // header says 9 control bytes, the file holds none
    var f = [_]u8{0} ** (1 + 36);
    f[1 + 32 + 1] = 9;
    try std.testing.expect(!decode(&f, &pic));
}

test "a Tiny literal run lands a column at a time" {
    var pic: Picture = undefined;
    // palette zeroes, 1 control byte (-2: two literal words), 2 words
    var f = [_]u8{0} ** (1 + 32 + 4 + 1 + 4);
    f[1 + 32 + 1] = 1; // 1 control byte
    f[1 + 32 + 3] = 2; // 2 words
    f[37] = 0xFE;
    f[38] = 0x80; // word 0 = $8000: pixel (0, 0)
    f[40] = 0x80; // word 1 = $8000: pixel (0, 1)
    try std.testing.expect(decode(&f, &pic));
    try std.testing.expectEqual(@as(u8, 1), pic.px[0]);
    try std.testing.expectEqual(@as(u8, 1), pic.px[W]);
    try std.testing.expectEqual(@as(u8, 0), pic.px[1]);
}
