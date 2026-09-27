// --------------------------------------------------------------------------
// The BASIC program's control flow across VBLs.
//
// The program is straight-line STOS code between the points where it waits:
// WAIT n, a key loop, the end of a main-loop pass (whose length on the ST is
// the compiled code's own run time). Each such stretch is a STEP, named by a
// label (the listing's line number, and a letter when a line is resumed in
// the middle): the step runs at once and says where to go next -- another
// label, a GOSUB to a routine that itself waits (with its return label), a
// RETURN from one, or a WAIT of n VBLs before the next label. Routines that
// never wait are plain functions and are simply called.
// --------------------------------------------------------------------------
const std = @import("std");

pub const L = enum(u8) {
    boot,
    // the game (loop.zig)
    l25, l34, l34b, l40, l50, l56, l68, l88b, l90, l151a, l151b, l90b, l101b, l102,
    // a key, the endings, the error trap (endings.zig)
    l190a, l190b, l190c, l220, l225, l227b, l23, l2700, l2700b,
    // missions (mission.zig)
    l1660, l1660b, l1661b, l1690b, l1690c, l1697b, l1698b, l1699,
    // the title and the difficulty menu (title.zig), the title screen (tscreen.zig)
    l2000, l2000b, l2005, l2005b, l2006, l2010, l2120, l2123, l2124, l2126, l2126b, l2131,
    l2350, l2350a, l2350b, l2350c, l2350d,
    // the hall of fame (hiscore.zig)
    l2260, l2280, l2280b, l2280c, l2290, l2291, l2291b, l2281, l2281b,
    l2320, l2320b, l2310, l2311,
    count,
};

pub const Call = struct { to: L, ret: L };
pub const Wait = struct { vbls: u16, then: L };
pub const Act = union(enum) { go: L, call: Call, ret, wait: Wait };
pub const Entry = struct { l: L, f: *const fn () Act };

pub var pc: L = .boot;
var stack: [32]L = undefined;
var sp: usize = 0;
var wait_left: u32 = 0;
/// RETURNs with an empty stack and steps with no code (checked 0).
pub var faults: u32 = 0;
/// Steps run, and the passes of the main loop (its label l50).
pub var steps: u64 = 0;

var table: [@intFromEnum(L.count)]?*const fn () Act = [_]?*const fn () Act{null} ** @intFromEnum(L.count);

pub fn register(entries: []const Entry) void {
    for (entries) |e| table[@intFromEnum(e.l)] = e.f;
}

pub fn reset() void {
    pc = .boot;
    sp = 0;
    wait_left = 0;
    faults = 0;
    steps = 0;
}

/// POP: the innermost GOSUB forgotten (221: pop : goto 33).
pub fn pop() void {
    if (sp > 0) sp -= 1 else faults += 1;
}

fn apply(a: Act) bool {
    switch (a) {
        .go => |l| pc = l,
        .call => |c| {
            if (sp < stack.len) {
                stack[sp] = c.ret;
                sp += 1;
            } else faults += 1;
            pc = c.to;
        },
        .ret => {
            if (sp == 0) {
                faults += 1;
                pc = .l2000;
            } else {
                sp -= 1;
                pc = stack[sp];
            }
        },
        .wait => |w| {
            pc = w.then;
            wait_left = w.vbls;
            return w.vbls > 0;
        },
    }
    return false;
}

/// One VBL of the BASIC side: count down a wait, then run steps until the
/// program waits again.
pub fn vbl() void {
    if (wait_left > 0) {
        wait_left -= 1;
        if (wait_left > 0) return;
    }
    var guard: u32 = 0;
    while (guard < 4096) : (guard += 1) {
        const f = table[@intFromEnum(pc)] orelse {
            faults += 1;
            return;
        };
        steps += 1;
        if (apply(f())) return;
    }
    faults += 1;
}
