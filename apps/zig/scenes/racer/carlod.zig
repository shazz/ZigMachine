// --------------------------------------------------------------------------
// RACER: cheaper far cars, OPT-IN (R82 board optimisation, OPTIMIZE.md). The cars are the race's biggest cost on the
// board (~1.2-1.5 Mc of a 32X course's frame: 8 cars of 71-143 faces, 40 of them wheels), and only fewer faces cut it.
// These switches CHANGE THE PICTURE, so they are off by default (every pin holds) until Matt picks one on the board:
//   -  the AI cars' far model: 0 past 6 units (as built), 1 past 3 units, 2 always (the upper bound)
//   =  the wheels not turned past 3 units (posing costs ~0.2 ms a car)
//   ;  no shadow past 12 units
// The player's car is never changed. Distances are view depth at the car's size (carview.LOD1_Z's rule).
// No ZigOS import.
// --------------------------------------------------------------------------
const std = @import("std");
const fix = @import("fix.zig");

pub var far_level: u8 = 0;
pub var still_far = false;
pub var no_far_shadow = false;
pub var ai = false; // the car being drawn is an AI car (carview.drawRace sets it)

const UNIT: i32 = 1 << 16;

/// The view depth (Q16) past which the car takes its far model; LOD1_Z (6 units) for the player and by default.
pub fn farZ(lod1_z: i32, size: i32) i32 {
    if (!ai or far_level == 0) return fix.mul(lod1_z, size);
    return if (far_level == 1) fix.mul(3 * UNIT, size) else -std.math.maxInt(i32);
}

/// True when the wheels are drawn as modelled (not turned) at view depth z.
pub fn stillWheels(z: i32, size: i32) bool {
    return ai and still_far and z > fix.mul(3 * UNIT, size);
}

/// True when the car's shadow is left out at view depth z.
pub fn noShadow(z: i32, size: i32) bool {
    return ai and no_far_shadow and z > fix.mul(12 * UNIT, size);
}

pub fn key(cp: u32) bool {
    switch (cp) {
        '-' => far_level = (far_level + 1) % 3,
        '=' => still_far = !still_far,
        ';' => no_far_shadow = !no_far_shadow,
        else => return false,
    }
    return true;
}

/// " D<far level><W if still wheels><S if no far shadow>" on the OSD line while any is on, else nothing.
pub fn tag(buf: []u8) []const u8 {
    if (far_level == 0 and !still_far and !no_far_shadow) return "";
    return std.fmt.bufPrint(buf, " D{}{s}{s}", .{ far_level, if (still_far) "W" else "", if (no_far_shadow) "S" else "" }) catch "";
}

test "off by default, the player's car never changed, the far model nearer at level 1 and always at 2" {
    ai = true;
    defer ai = false;
    try std.testing.expectEqual(fix.mul(6 << 16, 2 << 16), farZ(6 << 16, 2 << 16));
    far_level = 1;
    try std.testing.expectEqual(fix.mul(3 << 16, 2 << 16), farZ(6 << 16, 2 << 16));
    far_level = 2;
    try std.testing.expect(farZ(6 << 16, 1 << 16) < 0);
    ai = false;
    try std.testing.expectEqual(@as(i32, 6 << 16), farZ(6 << 16, 1 << 16));
    far_level = 0;
    var b: [16]u8 = undefined;
    try std.testing.expectEqualStrings("", tag(&b));
}
