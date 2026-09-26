// --------------------------------------------------------------------------
// The keyboard as the polling code sees it (the model's d_keys.py). A key is
// external input with a TIME: the IKBD delivers it through an ACIA interrupt
// (make + break code: 2 x 250 cycles) and the TOS buffer holds it until
// Bconin takes it. Here the pacer services a key when its time comes (as the
// harness's TOS does), and Bconstat / Bconin -- the only places the program
// looks at the buffer -- first bring the clock up to date.
// --------------------------------------------------------------------------
const State = @import("state.zig");
const St = State.St;

pub const TRAP: i64 = 300; // bios/xbios shim cost

/// ST scancodes of the keys a player may type (hardware facts, as TOS delivers them).
pub fn scancode(ch: u8) u32 {
    const c = if (ch >= 'A' and ch <= 'Z') ch + 32 else ch;
    const rows = [_][]const u8{ "1234567890", "qwertyuiop", "asdfghjkl", "zxcvbnm" };
    const base = [_]u32{ 2, 16, 30, 44 };
    for (rows, base) |row, b| {
        for (row, 0..) |r, i| if (r == c) return b + @as(u32, @intCast(i));
    }
    return switch (c) {
        ' ' => 57,
        '\r' => 28,
        3 => 46,
        0x1B => 1,
        8 => 14,
        else => 0,
    };
}

/// A key as the TOS buffer holds it: scancode << 16 | ASCII.
pub fn code(ch: u8) u32 {
    return (scancode(ch) << 16) | ch;
}

/// At an instruction boundary: bring the clock up to date (keys due by now
/// arrive, with their ACIA cost).
fn deliver(st: *St, cy: anytype) void {
    cy.flush();
    st.pacer.run(st, 0);
}

pub fn bconstat(st: *St, cy: anytype) i64 {
    deliver(st, cy);
    cy.add(TRAP);
    return if (st.key_n != 0) State.M32 else 0;
}

pub fn bconin(st: *St, cy: anytype) i64 {
    deliver(st, cy);
    cy.add(TRAP);
    // the harness alerts and returns 0 on an empty buffer (a real ST would block)
    const c = st.keyPop() orelse return 0;
    return c;
}
