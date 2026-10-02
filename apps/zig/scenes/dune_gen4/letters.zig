// The main part's bouncing "3615 GEN4" ($4194): eight 32x32 letters in plane 3
// (colour 8, which Timer B rewrites every line: the rainbow), each walking the
// BOUNCE table back and forth from its own start (bounce.zig), and each putting
// a 16-line grey bar into the COLOUR 0 table Timer B plays from line 100 --
// the bars are the background register, so they run through the borders.
const zg = @import("zigos");
const st = @import("st.zig");
const A = @import("assets.zig");
const bounce = @import("bounce.zig");

const T = A.T;
pub const TOP = 100; // Timer B's first line; BOUNCE heights are above it
pub const C0_LINES = 99; // $1CB8.., lines 100..198
const LINES = 32;

pub const Letters = struct {
    pos: [8]u16, // $163C: index into BOUNCE
    up: [8]bool, // $164C = 1
    y: [8]u16, // this VBL's line of each letter

    pub fn init(self: *Letters) void {
        self.pos = T.LETTER_POS;
        self.up = [_]bool{true} ** 8;
        self.y = [_]u16{TOP} ** 8;
    }

    /// One VBL: move every letter, and rebuild the colour-0 table (cleared,
    /// then each letter's bar from the line above its top -- $1CB6 is one word
    /// before line 100's -- later letters over earlier ones).
    pub fn vbl(self: *Letters, c0: *[C0_LINES]u16) void {
        @memset(c0, 0);
        for (0..8) |k| {
            self.y[k] = TOP + bounce.advance(&self.pos[k], &self.up[k]);
            const first = @as(i32, self.y[k]) - TOP - 1;
            for (T.BAR, 0..) |w, j| {
                const i = first + @as(i32, @intCast(j));
                if (i >= 0 and i < C0_LINES) c0[@intCast(i)] = w;
            }
        }
    }

    /// The letters' plane-3 bits, over lines top..199 cleared of plane 3.
    pub fn draw(self: *const Letters, fb: *zg.LogicalFB, top: usize) void {
        for (top..st.H) |y| {
            for (st.row(fb, y)) |*p| p.* &= 7;
        }
        for (0..8) |k| {
            const x: i32 = @intCast(T.LETTER_X[k] / 8 * 16);
            for (0..LINES) |l| {
                const y = self.y[k] + l;
                if (y >= st.H) break;
                const px = st.row(fb, y);
                st.orWord(px, x, T.LETTERS[k * 64 + 2 * l], 3);
                st.orWord(px, x + 16, T.LETTERS[k * 64 + 2 * l + 1], 3);
            }
        }
    }
};
