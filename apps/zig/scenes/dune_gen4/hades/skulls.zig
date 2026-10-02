// F2's five skulls ($6F30 draw, $7410 erase): TETEDEAD.PRG (a 32x32 sprite,
// each 16-pixel group a mask word and four plane words) pre-shifted to 16
// copies 48 pixels wide ($7502), walking the same path as F1's BLACK letters
// (XYEAGLE, x << 8 | y), each from its own index ($8A16: 5, 10, 15, 20, 25,
// not reset between visits), the first index drawn first. Drawn masked --
// (screen AND mask) OR sprite, a long at a time -- and erased (48x32, all
// planes) from the list kept for that screen two VBLs ago.
//
// Copy 0's masks are the file's own; copies 1..15 get NOT (OR of the planes).
const std = @import("std");
const ram = @import("ram.zig");
const A = @import("../assets.zig");

const DATA = A.TETEDEAD;
const LINES = 32;
const PATH_LEN = 628; // $274
const COUNT = 5;

/// [shift][line]: three mask words (one a group), then 3 groups x 4 planes.
var shifted: [16][LINES][15]u16 = undefined;

pub const Skulls = struct {
    at: [COUNT]u16, // $8A16, kept between visits
    lists: [2][COUNT]?usize, // $89BE / $89E6, one a screen
    list: u1, // which one $8A0E names

    pub fn init(self: *Skulls) void {
        self.at = A.HADES.SKULL_POS;
        preshift();
    }

    /// The lists name the cleared screens of the last visit: nothing to erase.
    pub fn enter(self: *Skulls) void {
        self.lists = .{ [_]?usize{null} ** COUNT, [_]?usize{null} ** COUNT };
        self.list = 0;
    }

    /// $7410: clear under the skulls this screen got two VBLs ago.
    pub fn clear(self: *Skulls, s: *ram.Screen) void {
        for (self.lists[self.list]) |entry| {
            const at = entry orelse break;
            for (0..LINES) |l| @memset(s[at + l * ram.LINE ..][0..24], 0);
        }
        self.list ^= 1;
    }

    /// $6F30: step each skull along the path and draw it, into the other list.
    pub fn draw(self: *Skulls, s: *ram.Screen) void {
        const list = &self.lists[self.list ^ 1];
        for (&self.at, list) |*c, *entry| {
            c.* = if (c.* == PATH_LEN) 1 else c.* + 1;
            const w = std.mem.readInt(u16, A.XYEAGLE[2 * @as(usize, c.*) ..][0..2], .big);
            const x: usize = w >> 8;
            const at = ram.groupAt(x, w & 0xFF);
            entry.* = at;
            for (0..LINES) |l| line(s, at + l * ram.LINE, &shifted[x & 15][l]);
        }
    }
};

/// One line, three groups: each plane word ANDed with its group's mask, ORed.
fn line(s: *ram.Screen, at: usize, src: *const [15]u16) void {
    for (0..3) |g| {
        for (0..4) |p| {
            const o = at + g * 8 + p * 2;
            ram.w16(s, o, (ram.r16(s, o) & src[g]) | src[3 + g * 4 + p]);
        }
    }
}

fn preshift() void {
    for (&shifted[0], 0..) |*ln, l| {
        const at = l * 20;
        ln[0] = be16(at);
        ln[1] = be16(at + 10);
        ln[2] = 0xFFFF;
        for (0..4) |p| {
            ln[3 + p] = be16(at + 2 + 2 * p);
            ln[7 + p] = be16(at + 12 + 2 * p);
            ln[11 + p] = 0;
        }
    }
    for (1..16) |k| {
        for (&shifted[k], shifted[k - 1]) |*ln, prev| {
            for (0..4) |p| {
                var carry: u16 = 0;
                for (0..3) |g| {
                    const w = prev[3 + g * 4 + p];
                    ln[3 + g * 4 + p] = (w >> 1) | carry;
                    carry = (w & 1) << 15;
                }
            }
            for (0..3) |g| ln[g] = ~(ln[3 + g * 4] | ln[4 + g * 4] | ln[5 + g * 4] | ln[6 + g * 4]);
        }
    }
}

fn be16(at: usize) u16 {
    return std.mem.readInt(u16, DATA[at..][0..2], .big);
}

comptime {
    if (DATA.len != LINES * 20) @compileError("TETEDEAD is 32 lines of 2 x (mask + 4 planes)");
}

test "copy k's masks are NOT (OR of its planes), copy 0's the file's" {
    const s = std.testing;
    var sk: Skulls = undefined;
    sk.init();
    for (1..16) |k| for (shifted[k]) |ln| for (0..3) |g| {
        try s.expectEqual(~(ln[3 + g * 4] | ln[4 + g * 4] | ln[5 + g * 4] | ln[6 + g * 4]), ln[g]);
    };
    try s.expectEqual(be16(0), shifted[0][0][0]);
    try s.expectEqual(@as(u16, 0xFFFF), shifted[0][0][2]);
}

test "a skull line is (screen AND mask) OR sprite, a group at a time" {
    const s = std.testing;
    var sk: Skulls = undefined;
    sk.init();
    var scr: ram.Screen = undefined;
    @memset(&scr, 0xFF); // every pixel colour 15
    const ln = &shifted[7][9];
    line(&scr, ram.LINE, ln);
    for (0..3) |g| for (0..4) |p| {
        try s.expectEqual(ln[g] | ln[3 + g * 4 + p], ram.r16(&scr, ram.LINE + g * 8 + p * 2));
    };
    try s.expectEqual(@as(u16, 0xFFFF), ram.r16(&scr, ram.LINE + 24)); // the next group untouched
}
