// F1 ($10A06, VBL $10AC8): the five BLACK letters (BLACK.DAT, 32x32, four
// planes, masked by the OR of their planes) chasing each other round the
// XYEAGLE path over Black Eagle's picture, until Space.
//
// Each letter has its own index into the path ($113E8: 20, 15, 10, 5, 0),
// stepped once a VBL and wrapped from 628 back to 1; the word there is
// x << 8 | y. They are drawn K first and B last, so B is on top. The indices
// are not reset when F1 is chosen again: the letters carry on.
//
// THE PICTURE. The part asks for "A:blackeag.tny", and the disk only has
// BLACKEAG.DAT -- a Tiny picture, byte for byte the right size and format --
// so on this disk the load fails and the letters fly over the menu picture
// left in the buffer, without its rasters. The cart shows the picture the code
// was written for; SHOW_DISK_BUG gives what the disk really does.
const std = @import("std");
const zg = @import("zigos");
const st = @import("st.zig");
const tny = @import("tny.zig");
const fade = @import("fade.zig");
const A = @import("assets.zig");

pub const SHOW_DISK_BUG = false;
const PATH_LEN = 628; // $274
const SIZE = 32;

/// BLACK.DAT as palette indices, decoded at compile time.
const LETTERS: [5][SIZE][SIZE]u8 = blk: {
    @setEvalBranchQuota(200_000);
    var out: [5][SIZE][SIZE]u8 = undefined;
    for (0..5) |k| for (0..SIZE) |l| for (0..2) |g| {
        const at = k * 512 + l * 16 + g * 8;
        for (0..16) |i| {
            var v: u8 = 0;
            for (0..4) |p| {
                const w = @as(u16, A.BLACK[at + 2 * p]) << 8 | A.BLACK[at + 2 * p + 1];
                v |= @as(u8, @intCast((w >> (15 - i)) & 1)) << p;
            }
            out[k][l][g * 16 + i] = v;
        }
    };
    break :blk out;
};

pub const Black = struct {
    n: u32, // VBLs since F1
    at: [5]u16, // $113E8, kept between visits
    palette: [16]u16,

    pub fn init(self: *Black) void {
        self.at = A.T.BLACK_POS;
    }

    pub fn enter(self: *Black, pic: *const tny.Picture) void {
        self.n = 0;
        self.palette = pic.palette;
    }

    pub fn vbl(self: *Black) void {
        self.n += 1;
        if (self.n <= fade.FRAMES) return;
        for (&self.at) |*c| c.* = if (c.* == PATH_LEN) 1 else c.* + 1;
    }

    pub fn render(self: *const Black, fb: *zg.LogicalFB, pic: *const tny.Picture) void {
        st.clear(fb);
        for (0..st.H) |y| @memcpy(st.row(fb, y), pic.px[y * tny.W ..][0..tny.W]);
        if (self.n <= fade.FRAMES) {
            const pal = fade.at(&self.palette, self.n);
            return st.setPalette(&pal);
        }
        var pal = self.palette;
        pal[0] = 0; // $10ACC
        st.setPalette(&pal);
        var k: usize = 5;
        while (k > 0) {
            k -= 1;
            const w = std.mem.readInt(u16, A.XYEAGLE[2 * @as(usize, self.at[k]) ..][0..2], .big);
            drawLetter(fb, k, w >> 8, w & 0xFF);
        }
    }
};

fn drawLetter(fb: *zg.LogicalFB, k: usize, x: usize, y: usize) void {
    for (LETTERS[k], 0..) |line, l| {
        if (y + l >= st.H) break;
        const px = st.row(fb, y + l);
        for (line, 0..) |v, i| {
            if (v != 0 and x + i < st.W) px[x + i] = v;
        }
    }
}
