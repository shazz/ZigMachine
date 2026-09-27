// --------------------------------------------------------------------------
// RND(n): the STOS runtime's (RAM $2CDB0): the smallest all-ones mask >= n,
// then XBIOS Random() (TOS: seed = seed * 3141592621 + 1, bits 8-31) ANDed
// with it until the value is <= n -- a uniform integer 0..n INCLUSIVE.
// RND(0) is 0; a negative n repeats the last value (never used here).
// The seed is the harness's to set; the ST seeded it from the 200 Hz clock.
// --------------------------------------------------------------------------
pub var seed: u32 = 0x1234567;
var last: i32 = 0;

fn random() u32 {
    seed = seed *% 3141592621 +% 1;
    return (seed >> 8) & 0xFFFFFF;
}

pub fn rnd(n: i32) i32 {
    if (n < 0) return last;
    if (n == 0) {
        last = 0;
        return 0;
    }
    var mask: u32 = 1;
    while (mask < @as(u32, @intCast(n))) mask = mask << 1 | 1;
    while (true) {
        const v = random() & mask;
        if (v <= @as(u32, @intCast(n))) {
            last = @intCast(v);
            return last;
        }
    }
}
