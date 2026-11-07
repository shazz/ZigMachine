// --------------------------------------------------------------------------
// part3.bin (tools/c64_transmission64_rip.py, ripped at part 3's entry $3808): a header of u32
// section offsets, then: bank 0's charsets ($2000-$3FFF), bank 3 ($C000-$FFFF), the zero page,
// the dot routines' index and their stores (3 bytes each: page step << 3 | 4 if the value is
// the A the routine was called with | 1 if ORed into memory; Y; the value).
// --------------------------------------------------------------------------
const le = @import("data.zig");

pub const Part3 = struct {
    b: []const u8,

    fn sec(self: Part3, i: usize) []const u8 {
        const at = le.le32(self.b[4 * i ..]);
        const end = if (i + 1 < 6) le.le32(self.b[4 * (i + 1) ..]) else self.b.len;
        return self.b[at..end];
    }

    /// $2000-$3FFF: bank 0's four charsets (the dots' first buffer).
    pub fn bank0(self: Part3) *const [0x2000]u8 {
        return self.sec(0)[0..0x2000];
    }
    /// $C000-$FFFF: the sines ($C000/$C200/$C400), the 10 shapes ($C600), the dot sprite
    /// ($C700), the dot counts ($C780), the screen ($C800), the panel's charset ($D000), codes
    /// ($D600) and colours ($FB00), the dots' colours ($DA00-$DDFF), the globe ($DE00), the
    /// second buffer's charsets ($E000) and the plot tables ($F808, $F900, $FA00).
    pub fn bank3(self: Part3) *const [0x4000]u8 {
        return self.sec(1)[0..0x4000];
    }
    /// The zero page as part 3 finds it: the generator never sets $15 (it stores $14 twice)
    /// and the dot lists read past what the init clears.
    pub fn zp(self: Part3) *const [256]u8 {
        return self.sec(2)[0..256];
    }
    /// The routine for depth page p (0..5 = $BA..$BF) and sub-position k (0..63): plot, or
    /// erase ($80 into the page).
    pub fn routine(self: Part3, p: usize, k: usize, erase: bool) []const u8 {
        const idx = self.sec(3);
        const id = le.le16(idx[2 * (128 * p + k + @as(usize, if (erase) 64 else 0)) ..]);
        const off = le.le16(idx[2 * 768 + 2 * @as(usize, id) ..]);
        const body = self.sec(4);
        const n = le.le16(body[off..]);
        return body[off + 2 ..][0 .. 3 * @as(usize, n)];
    }
    /// Shape change `j`: how far the main loop had generated the depth code when the IRQ ran
    /// it (measured in VICE for the first changes; it follows the tune's CPU time). Past the
    /// table, the table again.
    pub fn split(self: Part3, j: u32) @import("part3_dots.zig").Split {
        const s = self.sec(5);
        const n = s.len / 2;
        const e = s[2 * (j % n) ..][0..2];
        return .{ .k = e[0], .y = e[1] };
    }
};
