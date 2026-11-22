// --------------------------------------------------------------------------
// The two joysticks and the keyboard, as the game hears them.
//
//   Bub (1UP)  joystick port 1 ($3CA3): the arrows, fire = Space / Enter / 0
//   Bob (2UP)  joystick port 0 ($3CA2): W A S D, fire = Tab / left Ctrl / G
//              Fire on a stick also joins its player in (the game's $AFCA).
//   1, 2       Crawio, as the title reads them: one or two players
//   P          F1, the game's pause (press again to resume)
//   Escape     F10 in a game (the game's own quit to the title); on the
//              title it leaves the cart
// Each stick sends the IKBD event packet when it changes (bit 0 up, 1 down,
// 2 left, 3 right, 7 fire); a key sends its make code, a release its break
// code, as the ACIA byte the game's VBL reads ($FFFC02 -> $1048). The host's
// auto-repeat is not a key: a held key makes once.
// --------------------------------------------------------------------------
const io = @import("st/io.zig");
const tos = @import("st/tos.zig");
const frame = @import("st/frame.zig");

pub const K_ESC: u32 = 0xE012;
pub const K_TAB: u32 = 9;
pub const K_LCTRL: u32 = 0xE014;
const UP: u8 = 1;
const DOWN: u8 = 2;
const LEFT: u8 = 4;
const RIGHT: u8 = 8;
const FIRE: u8 = 0x80;
const SC_F1: u8 = 0x3B;
const SC_F10: u8 = 0x44;

pub const Pad = struct {
    stick: [2]u8 = .{ 0, 0 },
    held: u128 = 0,

    /// The host's arrows (0 up, 1 down, 2 left, 3 right, 5 the board's fire button): Bub.
    pub fn arrow(self: *Pad, dir: u8, down: bool) void {
        const b: u8 = switch (dir) {
            0 => UP,
            1 => DOWN,
            2 => LEFT,
            3 => RIGHT,
            5 => FIRE,
            else => 0,
        };
        self.set(1, b, down);
    }

    /// A key event; true for a FRESH press (not the host's auto-repeat).
    pub fn key(self: *Pad, cp: u32, down: bool) bool {
        const c: u32 = if (cp >= 'A' and cp <= 'Z') cp + 32 else cp;
        if (stickBit(c)) |s| {
            self.set(s.port, s.bit, down);
            return down;
        }
        const sc = scancode(c);
        if (sc == 0) return down;
        const bit = @as(u128, 1) << @intCast(sc);
        if (down) {
            if (self.held & bit != 0) return false;
            self.held |= bit;
            io.kbd_byte = sc;
            if (c == '1' or c == '2') tos.typeKey(@intCast(c));
            return true;
        }
        self.held &= ~bit;
        io.kbd_byte = sc | 0x80;
        return false;
    }

    fn set(self: *Pad, port: u1, b: u8, down: bool) void {
        if (down) self.stick[port] |= b else self.stick[port] &= ~b;
        frame.setJoystick(port, self.stick[port]);
    }
};

const StickBit = struct { port: u1, bit: u8 };

fn stickBit(c: u32) ?StickBit {
    return switch (c) {
        ' ', 13, '0' => .{ .port = 1, .bit = FIRE },
        'w' => .{ .port = 0, .bit = UP },
        's' => .{ .port = 0, .bit = DOWN },
        'a' => .{ .port = 0, .bit = LEFT },
        'd' => .{ .port = 0, .bit = RIGHT },
        K_TAB, K_LCTRL, 'g' => .{ .port = 0, .bit = FIRE },
        else => null,
    };
}

/// The ST scancode of the keys the game reads (0: a key it ignores).
fn scancode(c: u32) u8 {
    return switch (c) {
        '1' => 0x02,
        '2' => 0x03,
        'p' => SC_F1,
        K_ESC => SC_F10, // the game's own quit; on the title the scene leaves instead
        else => 0,
    };
}
