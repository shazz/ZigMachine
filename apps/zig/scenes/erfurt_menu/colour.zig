// --------------------------------------------------------------------------
// The menu's colour words. It runs as an STE screen: words like $0DF2 carry the
// STE's fourth bit, which is the LOW bit of a channel (level = (n & 7) << 1 | n >> 3).
// The exit fade ($1165C) works on the raw word: it takes $100/$10/$1 off each
// channel whose low three bits are not zero, seven times, one step every 3 VBLs.
// --------------------------------------------------------------------------

inline fn level(n: u16) u32 {
    return ((n & 7) << 1) | (n >> 3);
}

/// An STE $0RGB word as the machine's RGBA (4 bits to 8 by * 17).
pub inline fn rgba(w: u16) u32 {
    const r = level((w >> 8) & 15) * 17;
    const g = level((w >> 4) & 15) * 17;
    const b = level(w & 15) * 17;
    return 0xFF00_0000 | (b << 16) | (g << 8) | r;
}

/// $1165C, once.
pub fn fadeStep(c: u16) u16 {
    var v = c;
    if (v & 0x700 != 0) v -%= 0x100;
    if (v & 0x070 != 0) v -%= 0x010;
    if (v & 0x007 != 0) v -%= 0x001;
    return v;
}

/// $1165C applied `n` times: what the fade has left of a colour after n steps.
pub fn faded(c: u16, n: u8) u16 {
    var v = c;
    for (0..n) |_| v = fadeStep(v);
    return v;
}

/// The colour as the screen shows it under fade level `n`.
pub inline fn show(c: u16, n: u8) u32 {
    return rgba(if (n == 0) c else faded(c, n));
}
