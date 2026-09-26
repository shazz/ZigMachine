// --------------------------------------------------------------------------
// The keyboard, turned into the three bytes the battle reads (game.Inputs).
//
// The original: each player has a joystick (bit0 up, bit1 down, bit2 left,
// bit3 right, bit7 fire). With two players the Union has the port-1 stick,
// Left Shift (switch unit) and Esc (retreat); the Confederates have the
// keyboard stick (arrows + Space), Right Shift and Backspace. With one player
// Right Shift switches and Backspace retreats.
//
// Here the host forwards no Shift keys, so:
//   Union        W A S D move, F fire, Z switch (for Left Shift), Esc retreat
//   Confederates arrows move, Space fire, / switch (for Right Shift), Backspace retreat
// With one player, both sets drive your side, and Z and / are both Right Shift.
// The byte $191C2 is "the last scancode, 0 once released": the most recent of
// these keys still held, or 0.
// --------------------------------------------------------------------------
const Inputs = @import("game.zig").Inputs;

pub const K_ESC: u32 = 0xE012;
pub const K_BACKSPACE: u32 = 8;
pub const K_RETURN: u32 = 13;

const UP: u8 = 1;
const DOWN: u8 = 2;
const LEFT: u8 = 4;
const RIGHT: u8 = 8;
const FIRE: u8 = 0x80;

const SC_ESC: u8 = 0x01;
const SC_BACKSPACE: u8 = 0x0E;
const SC_LSHIFT: u8 = 0x2A;
const SC_RSHIFT: u8 = 0x36;

pub const Controls = struct {
    union_stick: u8, // W A S D F
    confed_stick: u8, // arrows + Space
    key: u8, // the scancode byte
    key_src: u32, // the host key that set it

    pub fn reset(self: *Controls) void {
        self.union_stick = 0;
        self.confed_stick = 0;
        self.key = 0;
        self.key_src = 0;
    }

    /// Host direction codes: 0 up, 1 down, 2 left, 3 right.
    pub fn direction(self: *Controls, dir: u8, down: bool) void {
        const bit: u8 = switch (dir) {
            0 => UP,
            1 => DOWN,
            2 => LEFT,
            3 => RIGHT,
            else => return,
        };
        set(&self.confed_stick, bit, down);
    }

    /// A character key (lower-cased) or one of the K_* codes.
    pub fn keyChange(self: *Controls, cp_in: u32, down: bool) void {
        const cp = if (cp_in >= 'A' and cp_in <= 'Z') cp_in + 32 else cp_in;
        switch (cp) {
            'w' => set(&self.union_stick, UP, down),
            's' => set(&self.union_stick, DOWN, down),
            'a' => set(&self.union_stick, LEFT, down),
            'd' => set(&self.union_stick, RIGHT, down),
            'f' => set(&self.union_stick, FIRE, down),
            ' ' => set(&self.confed_stick, FIRE, down),
            'z' => self.scancode(cp, SC_LSHIFT, down),
            '/' => self.scancode(cp, SC_RSHIFT, down),
            K_ESC => self.scancode(cp, SC_ESC, down),
            K_BACKSPACE => self.scancode(cp, SC_BACKSPACE, down),
            else => {},
        }
    }

    fn scancode(self: *Controls, cp: u32, sc: u8, down: bool) void {
        if (down) {
            self.key = sc;
            self.key_src = cp;
        } else if (self.key_src == cp) {
            self.key = 0;
            self.key_src = 0;
        }
    }

    /// The bytes for this frame. `two_players`: the Union reads port 1 and the
    /// Confederates the keyboard stick; otherwise both sets feed the one stick.
    pub fn inputs(self: *const Controls, two_players: bool) Inputs {
        if (two_players) return .{ .key = self.key, .joy = self.confed_stick, .port1 = self.union_stick };
        const k: u8 = if (self.key == SC_LSHIFT) SC_RSHIFT else self.key;
        return .{ .key = k, .joy = self.union_stick | self.confed_stick, .port1 = 0 };
    }
};

fn set(v: *u8, bit: u8, down: bool) void {
    if (down) v.* |= bit else v.* &= ~bit;
}
