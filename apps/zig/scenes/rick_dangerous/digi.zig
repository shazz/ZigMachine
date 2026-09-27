// --------------------------------------------------------------------------
// The Timer A digi clock, live (FINAL.md 6: "a port needs a sample clock").
//
// The sound driver starts a digi at the VBL tick ($348EA: TACR/TADR from
// $34A82/3, digi_ptr = digi_next); the Timer A handler $34AA4 then takes one
// sample byte per interrupt: a 0 byte ends the sample -- snd_loop set: again
// from digi_next; else Timer A stops and snd_mode = 0, which is what the drop
// rule reads. The sound itself is played by rick_dangerous.sndh (the same
// handler on the SNDH player's MFP); here only the game's RAM advances: one
// VBL's worth of samples at every VBL, before the tick, as the harness's
// Timer A bytes are replayed (io.irq).
// --------------------------------------------------------------------------
const m = @import("ram.zig");
const F = @import("fields.zig");

const MFP_HZ: f64 = 2457600.0;
/// 160256 cycles of 8021247 Hz: one PAL VBL.
const VBL_S: f64 = 160256.0 / 8021247.0;
const PRESCALE = [8]f64{ 0, 4, 10, 16, 50, 64, 100, 200 };

var on: bool = false;
var per_vbl: f64 = 0;
var acc: f64 = 0;

/// A write to TACR / TADR ($FFFA19 / $FFFA1F): 0 stops the timer.
pub fn timerA(tacr: i64, tadr: i64) void {
    const c: usize = @intCast(tacr & 7);
    on = c != 0;
    acc = 0;
    if (!on) return;
    const d: f64 = @floatFromInt(if (tadr & 0xFF == 0) 256 else tadr & 0xFF);
    per_vbl = MFP_HZ / (PRESCALE[c] * d) * VBL_S;
}

pub fn reset() void {
    on = false;
    acc = 0;
}

/// One VBL of Timer A interrupts ($34AA4 each).
pub fn vbl() void {
    if (!on) return;
    acc += per_vbl;
    while (on and acc >= 1.0) : (acc -= 1.0) sample();
}

fn sample() void {
    const p = m.rl(F.DIGI_PTR) & 0xFFFFFF;
    if (m.rb(p) != 0) {
        m.wl(F.DIGI_PTR, p + 1);
        return;
    }
    if (m.rb(F.SND_LOOP) != 0) {
        m.wl(F.DIGI_PTR, m.rl(F.DIGI_NEXT));
        return;
    }
    on = false; // clr.b $FFFA19
    m.wb(F.SND_MODE, 0);
}
