// --------------------------------------------------------------------------
// The IKBD as the game hears it: the joystick packet's byte ($38CAD: bit0 up,
// 1 down, 2 left, 3 right, 7 fire) whenever the stick changes, and each
// key's make / break code ($38CAE: Esc $01, P $19, Space $39; a release is
// the code | $80). The host's auto-repeat is not a key: a held key makes once.
// --------------------------------------------------------------------------
const io = @import("io.zig");

pub const K_ESC: u32 = 0xE012;
/// Left Ctrl / left Shift (docs/sealed-loader.js MOD_CODES): one-key shortcuts
/// for the two stick-plus-fire moves, so nobody has to chord them. Ctrl = up +
/// fire (the gun), Shift = down + fire (dynamite). They only set the same stick
/// bits a player would, so the game hears nothing it could not hear from the
/// joystick.
pub const K_LCTRL: u32 = 0xE014;
pub const K_LSHIFT: u32 = 0xE015;

const UP: u8 = 1;
const DOWN: u8 = 2;
const LEFT: u8 = 4;
const RIGHT: u8 = 8;
const FIRE: u8 = 0x80;

pub const Pad = struct {
    arrows: u8 = 0,
    wasd: u8 = 0,
    fire: bool = false,
    /// The bits held by the Ctrl / Shift shortcuts.
    macro: u8 = 0,
    /// The keys down now (the scancode's bit), so a repeat makes nothing.
    held: u128 = 0,

    pub fn arrow(self: *Pad, dir: u8, down: bool) void {
        const b: u8 = switch (dir) {
            0 => UP,
            1 => DOWN,
            2 => LEFT,
            3 => RIGHT,
            else => 0,
        };
        if (down) self.arrows |= b else self.arrows &= ~b;
        self.send();
    }

    /// A key event; true for a FRESH press (not the host's auto-repeat).
    pub fn key(self: *Pad, cp: u32, down: bool) bool {
        if (self.stick(cp, down)) {
            self.send();
            return down;
        }
        const sc = scancode(cp);
        if (sc == 0) return down;
        const bit = @as(u128, 1) << @intCast(sc);
        if (down) {
            if (self.held & bit != 0) return false; // the host's auto-repeat
            self.held |= bit;
            io.setKey(sc);
            return true;
        }
        self.held &= ~bit;
        io.setKey(sc | 0x80);
        return false;
    }

    /// W A S D, Enter, 0, and the Ctrl / Shift shortcuts: the joystick. True if
    /// it was one.
    fn stick(self: *Pad, cp: u32, down: bool) bool {
        const m: u8 = switch (cp) {
            K_LCTRL => UP | FIRE,
            K_LSHIFT => DOWN | FIRE,
            else => 0,
        };
        if (m != 0) {
            if (down) self.macro |= m else self.macro &= ~m;
            return true;
        }
        const c: u32 = if (cp >= 'A' and cp <= 'Z') cp + 32 else cp;
        const b: u8 = switch (c) {
            'w' => UP,
            's' => DOWN,
            'a' => LEFT,
            'd' => RIGHT,
            else => 0,
        };
        if (b != 0) {
            if (down) self.wasd |= b else self.wasd &= ~b;
            return true;
        }
        if (c == 13 or c == '0') {
            self.fire = down;
            return true;
        }
        return false;
    }

    fn send(self: *Pad) void {
        io.setStick(self.arrows | self.wasd | self.macro | (if (self.fire) FIRE else 0));
    }
};

/// The ST scancode of the keys the game reads (0: a key it ignores).
fn scancode(cp: u32) u8 {
    return switch (cp) {
        K_ESC => 0x01,
        'p', 'P' => 0x19,
        ' ' => 0x39,
        else => 0,
    };
}
