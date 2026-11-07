// --------------------------------------------------------------------------
// The original's data that is not a formula, as tools/c64_1988_rip.py lays it out in
// apps/zig/assets/screens/c64_1988/ (ripped from 1988.prg running in VICE at $1E00).
// No @embedFile here, so the native tests can hand in the same files read from disk;
// assets.zig embeds them for the cart.
// --------------------------------------------------------------------------
pub const RIPPED_LEN = 1010;

pub const Data = struct {
    bank3: *const [16384]u8, // VIC bank 3, $C000-$FFFF: the logo (blocks 0-71), the font (72-)
    bank0: *const [2048]u8, // VIC bank 0, $2000-$27FF: part 3's cubes and balls (blocks $80-$9F)
    rip: *const [RIPPED_LEN]u8,

    /// Text k (0..2) as stored at $619C/$622D/$62BE: codes ASCII - 32, index 0 unused.
    pub fn text(self: Data, k: usize) *const [146]u8 {
        return self.rip[146 * k ..][0..146];
    }

    /// $634F: how many bytes part 1's copy loop takes from text k (145 for all three).
    pub fn textLen(self: Data, k: usize) u8 {
        return self.rip[1007 + k];
    }

    /// $6358: per glyph code, how many 4-pixel steps the NEXT glyph moves in (proportional).
    pub fn glyphCut(self: Data) *const [256]u8 {
        return self.rip[438..694];
    }

    /// $608F/$6095/$609B: part 1's logo fade, 6 steps each of $D025, $D026, $D027.
    pub fn logoFade(self: Data) *const [18]u8 {
        return self.rip[694..712];
    }

    /// $4E6F: part 3 variant A (cubes), each column's bounce over 12 x 18 frames.
    pub fn bounceA(self: Data) *const [216]u8 {
        return self.rip[712..928];
    }

    /// $4C9D/$4CA5/$4CAD/$4CB5: part 3's end fade, 8 steps each of $D025, $D026, $D027, border.
    pub fn gridFade(self: Data) *const [32]u8 {
        return self.rip[928..960];
    }

    /// $D000-$D02E when the intro starts (BASIC's state).
    pub fn vicInit(self: Data) [0x2F]u8 {
        return self.rip[960..1007].*;
    }
};
