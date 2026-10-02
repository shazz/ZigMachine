// F2's starfield ($6466 erase, $6632 draw): 75 stars, each a run of 51
// precomputed positions in DUNE.PRG ($904C, 306 bytes a star: a word, the
// byte offset in the screen, then a long ORed into planes 0 and 1 there). All
// stars step together, one position a VBL, and start over after the 51st.
// The erase list is the one drawn two VBLs ago: the screen being drawn on.
const std = @import("std");
const ram = @import("ram.zig");

const DATA = @embedFile("../../../assets/screens/dune_gen4/hades_stars.bin");
pub const STARS = 75;
pub const FRAMES = 51; // $778E
const STAR_BYTES = FRAMES * 6; // $132

pub const Stars = struct {
    frame: u8, // ($778A - $904C) / 6
    erase: [STARS]u16, // $8FAC: what this screen was drawn with
    drawn: [STARS]u16, // $8F0C: what the other screen was drawn with

    pub fn init(self: *Stars) void {
        self.frame = 0; // $6452
        @memset(&self.erase, 0); // the lists are zero in the program
        @memset(&self.drawn, 0);
    }

    /// $6466: clear planes 0 and 1 under last time's stars on this screen.
    pub fn clear(self: *Stars, s: *ram.Screen) void {
        for (self.erase) |at| if (@as(usize, at) + 4 <= s.len) @memset(s[at..][0..4], 0);
        self.erase = self.drawn;
    }

    /// $6632: OR this position of every star in, then step.
    pub fn draw(self: *Stars, s: *ram.Screen) void {
        for (&self.drawn, 0..) |*d, i| {
            const rec = DATA[i * STAR_BYTES + @as(usize, self.frame) * 6 ..][0..6];
            const at = std.mem.readInt(u16, rec[0..2], .big);
            d.* = at;
            if (@as(usize, at) + 4 > s.len) continue;
            for (0..4) |k| s[at + k] |= rec[2 + k];
        }
        self.frame = if (self.frame + 1 == FRAMES) 0 else self.frame + 1;
    }
};

comptime {
    if (DATA.len != STARS * STAR_BYTES) @compileError("75 stars of 51 positions of 6 bytes");
}

test "the stars start over after 51 positions and erase what this screen got" {
    const s = std.testing;
    var stars: Stars = undefined;
    stars.init();
    var scr: ram.Screen = undefined;
    @memset(&scr, 0);
    stars.draw(&scr);
    const first = stars.drawn;
    for (1..FRAMES) |_| stars.draw(&scr);
    try s.expectEqual(@as(u8, 0), stars.frame);
    stars.draw(&scr);
    try s.expectEqualSlices(u16, &first, &stars.drawn);
    stars.clear(&scr); // the list copied at the last clear: two draws ago
    try s.expectEqualSlices(u16, &first, &stars.erase);
}
