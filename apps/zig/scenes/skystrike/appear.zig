// --------------------------------------------------------------------------
// APPEAR screen: STOS's dissolve (the sprite trap's function 43, RAM
// $3D70E), transcribed. With no effect number the runtime draws one,
// RND(70) + 1; its step s (the table at $3A5D8) walks the pixel index
// 0, s, 2s, ... modulo 64000 until it comes back to 0, copying each pixel's
// four plane bits from the source to the physical screen. Every step here is
// coprime with 64000, so the whole screen arrives. The loop costs 582 cycles
// a pixel on the ST (divu, two mulu, four plane words), 275 pixels a VBL:
// the dissolve takes ~4.6 seconds and runs pixel by pixel across the VBLs.
// --------------------------------------------------------------------------
const S = @import("stos.zig");
const scr = @import("scr.zig");
const clock = @import("clock.zig");

const STEPS = [71]u32{
    22223, 11,    89,    101,   121,  131,   159,   69,    13,   77,    103,   119,   133,   161,  43,    53,
    67,    107,   127,   137,   163,  119,   41,    47,    117,  129,   139,   3001,  16001, 1777, 3889,  30013,
    12003, 281,   12587, 31111, 20007, 2001, 3557,  20009, 20001, 3559, 12569, 99,    3269,  30001, 16001, 33,
    97,    32001, 9999,  777,   7777, 9997,  17777, 22777, 26777, 29057, 3023, 30099, 27777, 30057, 447,  657,
    30097, 30091, 30059, 327,   31857, 1487, 1489,
};
const TOTAL: u32 = 320 * 200;
pub const PIXEL_CYCLES: u64 = 582;

var src: scr.Id = .back;
var step: u32 = 1;
var at: u32 = 0;
var budget: u64 = 0;
pub var active: bool = false;

/// APPEAR s (no effect: a random one).
pub fn start(from: scr.Id) void {
    src = from;
    step = STEPS[@intCast(S.rnd(70))];
    at = 0;
    budget = 0;
    active = true;
}

/// One VBL of the dissolve; false when it has finished.
pub fn vbl() bool {
    if (!active) return false;
    const s = scr.get(src);
    const d = scr.get(.physic);
    budget += clock.VBL;
    while (budget >= PIXEL_CYCLES) {
        budget -= PIXEL_CYCLES;
        d[at] = s[at];
        at += step;
        if (at >= TOTAL) {
            at -= TOTAL;
            if (at == 0) {
                active = false;
                return false;
            }
        }
    }
    return true;
}
