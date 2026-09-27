// --------------------------------------------------------------------------
// How long the compiled program takes, in 68000 cycles (8 MHz, 160256 a VBL).
//
// The main loop has no VBL wait of its own: a pass lasts as long as its code
// runs, and TIMER (z2) reads 3 VBLs a pass at the start of a game on the ST.
// A pass is charged PASS cycles; a WAIT VBL inside it (the engine-sound and
// sample routines 990-998, the screen redraw 1013) runs on to the next VBL.
// The pass then waits for the VBLs it crossed, so the sprites, fades and
// TIMER move on in between exactly as the ST's interrupts do.
// --------------------------------------------------------------------------
pub const VBL: u64 = 160256;
/// One main-loop pass (lines 50-149), with the sprite VBL interrupt's share.
pub const PASS: u64 = 2 * VBL + VBL / 2;

var pos: u64 = 0;
var crossed: u16 = 0;

pub fn reset() void {
    pos = 0;
    crossed = 0;
}

pub fn spend(c: u64) void {
    pos += c;
    while (pos >= VBL) {
        pos -= VBL;
        crossed += 1;
    }
}

/// WAIT VBL: to the start of the next VBL.
pub fn waitVbl() void {
    pos = 0;
    crossed += 1;
}

/// The VBLs crossed since the last take().
pub fn take() u16 {
    const c = crossed;
    crossed = 0;
    return c;
}

/// A step that ended on a WAIT restarts at the top of a VBL.
pub fn atVbl() void {
    pos = 0;
    crossed = 0;
}
