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
/// One main-loop pass (lines 50-149), with the sprite VBL interrupt's share:
/// 2.8 VBLs (the ST's z2 runs 3, 3, 3, 2 ... taking off and flying over
/// the home airfield: 2.76-2.86 a pass).
pub const PASS: u64 = 2 * VBL + VBL * 4 / 5;
/// A screen drawn afresh (line 1000): the pass that crosses into a new
/// sector takes 24 VBLs on the ST, 21 more than a plain one.
pub const REDRAW: u64 = 21 * VBL;

var pos: u64 = 0;
var crossed: u16 = 0;

pub fn reset() void {
    pos = 0;
    crossed = 0;
}

/// The clock as it stands, for ZIG's off-screen draws (zig_sandbox.zig).
pub const State = struct { pos: u64, crossed: u16 };
pub fn save() State {
    return .{ .pos = pos, .crossed = crossed };
}
pub fn load(s: State) void {
    pos = s.pos;
    crossed = s.crossed;
}

pub fn spend(c: u64) void {
    pos += c;
    while (pos >= VBL) {
        pos -= VBL;
        crossed += 1;
    }
}

/// WAIT VBL: to the start of the next VBL. The program is not running
/// while it waits, the VBL interrupt is: its sprite redraw (STOS's sprites
/// are on automatic UPDATE; the listing never turns it off) happens NOW,
/// before the next line. Line 1950 relies on it: OFF, then 993's WAIT VBL
/// takes the sprites off the physic screen before 1956's SCREEN COPY LOGIC
/// TO BACK; without it the plane was copied into the back screen, a ghost
/// left where a bomb burst. TIMER, the fades and MOVE still run when the
/// pass waits out the VBLs it crossed (loop.zig's l102).
pub fn waitVbl() void {
    pos = 0;
    crossed += 1;
    @import("sprite.zig").update();
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
