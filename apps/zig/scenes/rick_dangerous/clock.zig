// --------------------------------------------------------------------------
// The VBL clock of the long calls (the model's a_clock.py + d_clock.py +
// d_long.py's plumbing). A normal frame keeps no cycle clock; calls 6/7/8/17
// (redraws, scrolls, the level end) and 19-21 (GAME OVER, hall of fame,
// title, select, intro) do: `pos` = cycles since the last VBL, advanced by
// what each piece of the original's work costs (stretched by TOS's Timer C,
// +200 cycles per 40,064), taking a VBL whenever it passes 160,256. So the
// VBLs they take, visible and in the state (the counter, the music), are the
// original's. `t` counts the cycles since the call started: the stick and
// key changes of the call arrive on it (io.pollJoy / pollKey).
// --------------------------------------------------------------------------
const m = @import("ram.zig");
const F = @import("fields.zig");
const game = @import("game.zig");
const io = @import("io.zig");

pub const VBL: i64 = 160256;
pub const AFTER_WAIT: i64 = 60;
const TIMERC_PERIOD: i64 = 40064;
const TIMERC_COST: i64 = 200;

// package A's measured costs (a_measure.py)
pub const BUILD: i64 = 14676;
pub const DRAW_ROWS_24: i64 = 521756;
pub const DRAW_ROW: i64 = 21920;
pub const COPY: i64 = 128360;
pub const CHECKPOINT: i64 = 184;
pub const PASS_BASE: i64 = 1196;
pub const PASS_SLOT: i64 = 180;
pub const PASS_SHIFT: i64 = 116;

// package D's measured costs (d_measure.py)
pub const CLEAR_BOTH: i64 = 344276;
pub const CLEAR_HUD_EXTRA: i64 = 34628;
pub const BANNER: i64 = 66696;
pub const TITLE_PICTURE: i64 = 176204;
pub const PRINT_BASE: i64 = 388;
pub const PRINT_CHAR: i64 = 1344;
pub const PRINT1_BASE: i64 = 162;
pub const PRINT1_CHAR: i64 = 718;
pub const FADE_OUT_ENTRY: i64 = 96;
pub const FADE_OUT_STEP: i64 = 1716;
pub const FADE_OUT_END: i64 = 76;
pub const FADE_IN_ENTRY: i64 = 136;
pub const FADE_IN_STEP: i64 = 2068;
pub const FADE_IN_END: i64 = 172;
const AFTER_CALL: i64 = 200;

pub var pos: i64 = 0;
pub var t: i64 = 0;
var has_pos: bool = false;
/// Call 20 ran: call 21 continues its clock (d_long's d_chain).
var chain: bool = false;

pub fn reset() void {
    pos = 0;
    t = 0;
    has_pos = false;
    chain = false;
}

/// Power-on: the clock starts at the entry's phase in its VBL.
pub fn startAt(p: i64) void {
    pos = p;
    t = 0;
    has_pos = true;
}

/// The VBL interrupt's own length, by the sound driver's state.
pub fn irqCost() i64 {
    const md = m.rb(F.SND_MODE);
    if (md == 0xFF) return 610;
    if (md == 1) return if (m.rb(F.MUSIC_BUSY) == 0xFF) 3100 else 2300;
    return 1800;
}

/// a_clock.begin: calls 6, 7, 8 and 17 start (the work since the last wait).
pub fn beginWorld(call: i64) void {
    const entry: i64 = switch (call) {
        6 => 2200,
        7, 8 => 600,
        else => 1900,
    };
    pos = entry + irqCost();
    t = 0;
    has_pos = true;
}

/// d_long.long_call's clock: call 19 starts fresh, 20 continues the running
/// clock, 21 continues it after 20, else (Esc) starts fresh.
pub fn beginLong(k: i64) void {
    const keep = k == 20 or (k == 21 and chain);
    chain = false;
    if (!(keep and has_pos)) pos = irqCost() + AFTER_WAIT + @as(i64, if (k == 19) 700 else 300);
    pos += AFTER_CALL;
    t = 0;
    has_pos = true;
}

/// Call 20 ended: call 21 continues its clock.
pub fn chained() void {
    chain = true;
}

/// `cycles` of the original's work (+ TOS's Timer C); take the VBLs it crosses.
pub fn work(cycles_: i64) void {
    const cycles = cycles_ + @divFloor(cycles_ * TIMERC_COST, TIMERC_PERIOD);
    pos += cycles;
    t += cycles;
    while (pos >= VBL) {
        pos -= VBL;
        const n = irqCost();
        game.vblIrq();
        pos += n;
        t += n;
    }
}

/// A wait for the next VBL returned.
pub fn waited() void {
    const n = irqCost() + AFTER_WAIT;
    t += VBL - pos + n;
    pos = n;
}

/// a_clock.poll_input: the stick bytes that arrived by now.
pub fn pollJoy() void {
    io.pollJoy(t);
}

/// d_clock.poll: the stick and key bytes that arrived by now.
pub fn poll() void {
    io.pollJoy(t);
    io.pollKey(t);
}
