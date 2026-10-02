// --------------------------------------------------------------------------
// $760: which distortion table the logo is drawn through next (a4). State 1
// holds the straight logo for $31030 frames; states 2 and 3 walk a table 8
// bytes (one line) a frame, restarting a set number of times; state 5 walks
// to $31BE0, state 6 holds it $64 frames; state $64 plays the list
// $35660..$3572C (pointer, frames) $F times, then $746 starts over. Every
// state change falls through into the next state's code in the same call.
// 'F' (freeze, $36204) stops every count and step. Transcribed from the
// 68000 and checked to 20000 frames (prototypes/naos_nitrowave_re/dam_main.py).
// --------------------------------------------------------------------------
const st = @import("st.zig");

const TAB: u32 = 0x35730;
const N: u32 = 0x31030;
const N2: u32 = 0x31032;
const STATE: u32 = 0x31034;
const LIST: u32 = 0x3572C;
const FREEZE: u32 = 0x36204;
const LIST_FIRST: u32 = 0x35660;
const LIST_END: u32 = 0x3572C;
const HOLD_LINE: u32 = 0x31BE0;

const Walk = struct { end: u32, restart: u32, next: u16, count: ?u16 };
const walk2 = Walk{ .end = 0x31628, .restart = 0x31280, .next = 3, .count = 0xC };
const walk3 = Walk{ .end = 0x31A30, .restart = 0x31888, .next = 5, .count = null };

fn frozen(r: *const st.Ram) bool {
    return r.w(FREEZE) != 0;
}

/// Count $31030 down; true when it reaches zero.
fn tick(r: *const st.Ram) bool {
    const n = r.w(N) -% 1;
    r.sw(N, n);
    return n == 0;
}

pub fn next(r: *const st.Ram) u32 {
    var guard: usize = 0;
    while (guard < 8) : (guard += 1) {
        switch (r.w(STATE)) {
            0x64 => return list(r),
            1 => {
                if (frozen(r) or !tick(r)) return r.l(TAB);
                r.sw(N, 0xA);
                r.sw(STATE, 2);
            },
            2, 3 => if (step(r, if (r.w(STATE) == 2) walk2 else walk3)) |a4| return a4,
            5 => {
                if (frozen(r)) return r.l(TAB);
                r.sl(TAB, r.l(TAB) + 8);
                if (r.l(TAB) != HOLD_LINE) return r.l(TAB);
                r.sw(N, 0x64);
                r.sw(STATE, 6);
                return hold(r);
            },
            else => return hold(r),
        }
    }
    return r.l(TAB);
}

/// A walk's frame: null when it moved on to the next state (handled by the caller).
fn step(r: *const st.Ram, w: Walk) ?u32 {
    if (frozen(r)) return r.l(TAB);
    r.sl(TAB, r.l(TAB) + 8);
    if (r.l(TAB) != w.end) return r.l(TAB);
    if (!tick(r)) {
        r.sl(TAB, w.restart);
        return r.l(TAB);
    }
    if (w.count) |c| r.sw(N, c);
    r.sw(STATE, w.next);
    return null;
}

/// $884.
fn hold(r: *const st.Ram) u32 {
    r.sl(TAB, HOLD_LINE);
    if (frozen(r) or !tick(r)) return r.l(TAB);
    r.sw(N, 0x12C);
    r.sw(STATE, 0x64);
    r.sw(N2, 0xF);
    return list(r); // $8BE runs on into $8C6
}

/// $8C6.
fn list(r: *const st.Ram) u32 {
    if (frozen(r) or !tick(r)) return r.l(r.l(LIST));
    var q = r.l(LIST) + 6;
    if (q == LIST_END) {
        q = LIST_FIRST;
        r.sl(LIST, q);
        const n2 = r.w(N2) -% 1;
        r.sw(N2, n2);
        if (n2 == 0) { // $746, then $760 again
            r.sl(TAB, 0x31038);
            r.sw(STATE, 1);
            r.sw(N, 0x12C);
            return next(r);
        }
    }
    r.sl(LIST, q);
    r.sw(N, r.w(q + 4));
    return r.l(q);
}
