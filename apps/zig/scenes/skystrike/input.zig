// --------------------------------------------------------------------------
// The keyboard, joystick and mouse buttons as STOS reads them.
//
//   INKEY$ / SCANCODE / CLEAR KEY   the TOS key buffer: characters with their
//        scancodes; a key with no character (F1-F10) reads as CHR$(0), its
//        scancode 59-68 (the game's F-key shortcuts test SCANCODE)
//   JUP / JDOWN / JLEFT / JRIGHT / FIRE   joystick 1: the arrows and Space
//   MOUSE KEY   bit 1 (= 2) is the right button, which on the ST is wired to
//        the joystick's fire (the difficulty menu's FIRE and the game's
//        "mouse key = 2" gun are the same button): Space here too
// --------------------------------------------------------------------------
pub const UP: u8 = 1;
pub const DOWN: u8 = 2;
pub const LEFT: u8 = 4;
pub const RIGHT: u8 = 8;

pub var stick: u8 = 0;
pub var fire_down: bool = false;
/// ZIG's one-key weapons held (zig_keys.zig): each is FIRE, with the arrow
/// its chord needs. Never set in ORIGINAL.
pub const Weapon = struct { guns: bool = false, rocket: bool = false, bomb: bool = false };
pub var weapon: Weapon = .{};

fn firing() bool {
    return fire_down or weapon.guns or weapon.rocket or weapon.bomb;
}

const QN = 32;
var q_char: [QN]u8 = undefined;
var q_scan: [QN]u8 = undefined;
var q_head: usize = 0;
var q_len: usize = 0;
/// SCANCODE: the key INKEY$ last returned.
pub var last_scan: i32 = 0;

pub fn reset() void {
    stick = 0;
    fire_down = false;
    weapon = .{};
    q_len = 0;
    last_scan = 0;
}

pub fn push(c: u8, sc: u8) void {
    if (q_len == QN) return;
    const i = (q_head + q_len) % QN;
    q_char[i] = c;
    q_scan[i] = sc;
    q_len += 1;
}

/// INKEY$: the next character, or null for "".
pub fn inkey() ?u8 {
    if (q_len == 0) return null;
    const c = q_char[q_head];
    last_scan = q_scan[q_head];
    q_head = (q_head + 1) % QN;
    q_len -= 1;
    return c;
}

pub fn clearKey() void {
    q_len = 0;
}

/// STOS truth values: -1 true, 0 false.
fn t(b: bool) i32 {
    return if (b) -1 else 0;
}

pub fn jup() i32 {
    return t(stick & UP != 0);
}
pub fn jdown() i32 {
    return t(stick & DOWN != 0);
}
pub fn jleft() i32 {
    return t(stick & LEFT != 0 or weapon.bomb);
}
pub fn jright() i32 {
    return t(stick & RIGHT != 0 or weapon.rocket);
}
pub fn fire() i32 {
    return t(firing());
}
pub fn mouseKey() i32 {
    return if (firing()) 2 else 0;
}

/// The ST scancode of a character the host sends (0 when the game never
/// looks at it).
pub fn scancodeOf(c: u8) u8 {
    const rows = [_]struct { s: []const u8, base: u8 }{
        .{ .s = "1234567890", .base = 2 },
        .{ .s = "QWERTYUIOP", .base = 16 },
        .{ .s = "ASDFGHJKL", .base = 30 },
        .{ .s = "ZXCVBNM", .base = 44 },
    };
    const u = if (c >= 'a' and c <= 'z') c - 32 else c;
    for (rows) |r| for (r.s, 0..) |k, i| if (k == u) return r.base + @as(u8, @intCast(i));
    return switch (c) {
        27 => 1,
        8 => 14,
        13 => 28,
        ' ' => 57,
        else => 0,
    };
}
