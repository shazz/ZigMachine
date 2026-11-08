// --------------------------------------------------------------------------
// Colour groups: the plane's palette entries the expanded blocks draw with (vic_cache.zig).
//
// A sprite pixel is code 1 ($D025), 2 (the sprite's colour) or 3 ($D026). Instead of baking the
// colours into each expanded block, a block is expanded once per GROUP, pixel = FIRST + 4 * group
// + code, and the group's three entries hold the frame's colours. Each frame hands each run a
// group whose colours are the run's: first the one of its kind (hires or multicolour, X-expanded
// or not: the logo, the scrollers, the cubes each keep theirs), else any group already holding
// those colours, else a free one. The whole plane is redrawn every C64 frame, so the entries
// only ever colour this frame's pixels: the picture is the same as with the colours baked in
// (the colour is the C64's, entry for entry), and a fade step costs three palette writes
// instead of 72 blocks expanded again.
// --------------------------------------------------------------------------
const cache = @import("vic_cache.zig");

pub const GROUPS = cache.GROUPS;

pub const Groups = struct {
    colours: [GROUPS][3]u8 = undefined, // C64 colours of codes 1, 2, 3
    used: u16 = 0,

    pub fn reset(self: *Groups) void {
        self.used = 0;
    }

    /// The group for a run of this kind and these C64 colours (hires runs use code 2 only).
    pub fn assign(self: *Groups, mcol: bool, xe2: bool, c: [3]u8) u8 {
        const want: [3]u8 = if (mcol) c else .{ 0, c[1], 0 };
        const kind: u8 = 2 * @as(u8, @intFromBool(mcol)) + @intFromBool(xe2);
        if (self.fits(kind, want)) return kind;
        var g: u8 = 4;
        while (g < GROUPS) : (g += 1) {
            if (self.fits(g, want)) return g;
        }
        @panic("c64_1988: more colour sets in a frame than groups"); // show_test runs the loop
    }

    fn fits(self: *Groups, g: u8, want: [3]u8) bool {
        const bit = @as(u16, 1) << @intCast(g);
        if (self.used & bit == 0) {
            self.used |= bit;
            self.colours[g] = want;
            return true;
        }
        const have = self.colours[g];
        return have[0] == want[0] and have[1] == want[1] and have[2] == want[2];
    }
};
