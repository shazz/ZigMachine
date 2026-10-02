// F2's HADES logo ($6E96, $6B14, $6BBA): 128x50 in three planes, drawn 144
// pixels wide at x 80 with plane 3 set throughout -- an opaque block in colours
// 8..15 -- each line from one of 16 copies pre-shifted a pixel apart ($7502):
// line l takes the copy named by WOBBLE, 61 bytes rotated one byte a
// VBL, so the logo waves. Its line walks LOGO_Y back and forth like the main
// part's letters. It is erased (all four planes, 9 groups x 50 lines) where it
// was drawn one VBL ago -- the other screen -- before being drawn again.
//
// The shift table at $7790 holds 50 words copied from WOBBLE, but the draw
// reads index 50 too: the word after the table, the high half of the first
// pre-shift pointer ($00060000) -- so the logo's top line is always shifted 6.
const std = @import("std");
const ram = @import("ram.zig");
const H = @import("../assets.zig").HADES;

const DATA = @embedFile("../../../assets/screens/dune_gen4/hades_logo.bin");
const LINES = 50;
const GROUPS = 9; // 8 of the logo + 1 for the shift to run into
const X_BYTES = 0x28; // byte 40: pixel 80
const TURN = 0x118;
const TOP_SHIFT = 6; // $77F4's high word
/// $6F04 moves 60 bytes down one and puts the first after them: 61 rotate.
const ROTATED = 61;

/// [shift][line][group * 3 + plane]: 43 KB, so the caller's (zg.mem: a
/// module-scope array this big would be written into the cart as zeros).
pub const Shifts = [16][LINES][GROUPS * 3]u16;
var shifted: *Shifts = undefined;

pub const Logo = struct {
    pos: u16, // $7758
    up: bool, // $775A = 1
    wobble: [H.WOBBLE.len]u8, // $796C, rotating -- Timer B reads it too
    erase_at: ?usize, // $7762 (0: none)
    drawn_at: ?usize, // $775E (0 until the first draw)

    pub fn init(self: *Logo, buf: *Shifts) void {
        shifted = buf;
        self.pos = 0;
        self.up = true;
        self.wobble = H.WOBBLE;
        self.erase_at = null;
        self.drawn_at = null;
        preshift();
    }

    /// $6BBA: clear where the logo was drawn last VBL.
    pub fn clear(self: *Logo, s: *ram.Screen) void {
        if (self.erase_at) |at| {
            for (0..LINES) |l| @memset(s[at + l * ram.LINE ..][0 .. GROUPS * 8], 0);
        }
        self.erase_at = self.drawn_at;
    }

    /// $6E96: rotate the wobble, step the line, draw.
    pub fn draw(self: *Logo, s: *ram.Screen) void {
        std.mem.rotate(u8, self.wobble[0..ROTATED], 1);
        const y = walk(&self.pos, &self.up);
        const top = @as(usize, y) * ram.LINE + X_BYTES;
        self.drawn_at = top;
        for (0..LINES) |l| {
            const k = LINES - l; // d7, 50 down to 1
            const shift = if (k == LINES) TOP_SHIFT else self.wobble[k];
            const src = &shifted[shift & 15][l];
            const at = top + l * ram.LINE;
            for (0..GROUPS) |g| {
                for (0..3) |p| ram.w16(s, at + g * 8 + p * 2, src[g * 3 + p]);
                ram.w16(s, at + g * 8 + 6, 0xFFFF);
            }
        }
    }
};

/// $6EB2: LOGO_Y up to index $118, then back down to 1.
fn walk(pos: *u16, up: *bool) u16 {
    if (up.*) {
        if (pos.* != TURN) {
            defer pos.* += 1;
            return H.LOGO_Y[pos.*];
        }
        up.* = false;
    }
    if (pos.* == 1) {
        up.* = true;
        defer pos.* += 1;
        return H.LOGO_Y[pos.*];
    }
    defer pos.* -= 1;
    return H.LOGO_Y[pos.*];
}

/// $7502: copy 0 is the data (groups 0..3 from $7D9E, 4..7 from $824E, group
/// 8 empty), copy k is copy k-1 shifted right a pixel, plane by plane.
fn preshift() void {
    for (&shifted[0], 0..) |*line, l| {
        for (0..12) |w| {
            line[w] = be16(l * 24 + 2 * w);
            line[12 + w] = be16(LINES * 24 + l * 24 + 2 * w);
        }
        @memset(line[24..], 0);
    }
    for (1..16) |k| {
        for (&shifted[k], shifted[k - 1]) |*line, prev| {
            for (0..3) |p| {
                var carry: u16 = 0;
                for (0..GROUPS) |g| {
                    const w = prev[g * 3 + p];
                    line[g * 3 + p] = (w >> 1) | carry;
                    carry = (w & 1) << 15;
                }
            }
        }
    }
}

fn be16(at: usize) u16 {
    return std.mem.readInt(u16, DATA[at..][0..2], .big);
}

comptime {
    if (DATA.len != 2 * LINES * 24) @compileError("the logo is 50 lines of 24 + 24 bytes");
    if (H.LOGO_Y.len != TURN + 1) @compileError("LOGO_Y runs 0..$118");
}

test "copy k is the logo moved k pixels right, plane by plane" {
    const s = std.testing;
    var logo: Logo = undefined;
    var buf: Shifts = undefined;
    logo.init(&buf);
    for (0..LINES) |l| {
        for (0..3) |p| {
            var row0: u144 = 0;
            var row5: u144 = 0;
            for (0..GROUPS) |g| {
                row0 = row0 << 16 | shifted[0][l][g * 3 + p];
                row5 = row5 << 16 | shifted[5][l][g * 3 + p];
            }
            try s.expectEqual(row0 >> 5, row5);
        }
    }
}

test "the wobble rotates 61 bytes and the top line keeps shift 6" {
    const s = std.testing;
    var logo: Logo = undefined;
    var buf: Shifts = undefined;
    logo.init(&buf);
    var scr: ram.Screen = undefined;
    @memset(&scr, 0);
    logo.draw(&scr);
    try s.expectEqual(H.WOBBLE[1], logo.wobble[0]);
    try s.expectEqual(H.WOBBLE[0], logo.wobble[ROTATED - 1]);
    try s.expectEqual(H.WOBBLE[ROTATED], logo.wobble[ROTATED]); // not rotated
    const top = @as(usize, H.LOGO_Y[0]) * ram.LINE + X_BYTES;
    try s.expectEqual(@as(u16, 0xFFFF), ram.r16(&scr, top + 6)); // plane 3 set
    for (0..3) |p| try s.expectEqual(shifted[TOP_SHIFT][0][p], ram.r16(&scr, top + 2 * p));
}
