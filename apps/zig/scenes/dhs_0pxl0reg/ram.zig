// --------------------------------------------------------------------------
// The cart's large working buffers, from the machine's RAM arena (zg.mem,
// zeroed). As module-scope statics they were zero data segments (the cart
// imports its memory): ~290 KB of cart binary and of the window before boot.
//
//   out.list   71,680 B  every line's beam writes, read by the global HBL:
//                         taken once per cart load, before the HBL is installed
//   one part   <= 71,176 B  (P3's ribbon + fade tables; P14 70,400; P10 26,400;
//                         P9 33,288; P1 8,640; P2 8,192)
//
// The parts run one after another on the sequencer and never overlap: each
// part's init hook is the only main hook of an entry whose kernel, vbl and post
// are nop, so nothing of the previous part runs once it is called. Every part
// with a big buffer takes it in its init through part(), which first frees the
// previous part's, so the whole demo needs the largest part, not the sum.
// A freshly allocated block is zeroed, which is what the statics started as.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const out = @import("out.zig");

var booted = false;
var part_base: zg.mem.Mark = 0;

/// Once per cart load, before the global HBL is installed. A re-init of the same
/// instance keeps out.list and frees whichever part held the rest.
pub fn init() void {
    if (booted) return zg.mem.release(part_base);
    booted = true;
    out.list = zg.mem.mustAlloc([out.SLOTS]u32, out.LINES)[0..out.LINES];
    part_base = zg.mem.mark();
}

/// A part's buffers, zeroed; the previous part's are freed first.
pub fn part(comptime T: type) *T {
    zg.mem.release(part_base);
    return &zg.mem.mustAlloc(T, 1)[0];
}
