// --------------------------------------------------------------------------
// ZIG mode's weapon keys: one key for each chord the original needs
// (zig_settings.zig names them):
//
//   left Ctrl    the guns     = FIRE                 (350)
//   left Shift   a rocket     = FIRE + right         (380)
//   Space        a bomb       = FIRE + left          (360)
//
// A key held is exactly the chord held (input.zig's jleft / jright / fire /
// mouse key read it), so the game sees what the joystick would give and
// nothing else changes. Space still goes into the key buffer and is still
// FIRE, as in the original, so with the pilot bailed out (bale) it lands his
// chute (155) and drops nothing. The arrows + FIRE chords work as before:
// Ctrl is a FIRE button too. ORIGINAL ignores Ctrl and Shift, and its Space
// is plain FIRE.
// --------------------------------------------------------------------------
const input = @import("input.zig");
const hooks = @import("zig_hooks.zig");
const set = @import("zig_settings.zig");
const V = @import("vars.zig");
const v = &V.v;

/// A key down. False: not a weapon key here (the caller goes on with it).
pub fn down(cp: u32) bool {
    if (!hooks.zig) return false;
    if (cp == set.key_guns) {
        input.weapon.guns = true;
        return true;
    }
    if (cp == set.key_rocket) {
        input.weapon.rocket = true;
        return true;
    }
    if (cp == ' ' and set.space_bombs and hooks.flightView() and v.bale == 0) input.weapon.bomb = true;
    return false;
}

/// A key up.
pub fn up(cp: u32) void {
    if (cp == set.key_guns) input.weapon.guns = false;
    if (cp == set.key_rocket) input.weapon.rocket = false;
    if (cp == ' ') input.weapon.bomb = false;
}

/// The mode was switched: nothing stays held across it.
pub fn release() void {
    input.weapon = .{};
}
