// --------------------------------------------------------------------------
// RACER: the board A/B switches (R82 board optimisation, OPTIMIZE.md): each hides one item of the picture so its cost
// is read off the board (glass ctl stats: fps, cart_c; the OSD's stage line, key o) by toggling it. None changes what
// is drawn when every switch is off (the default): no pin moves. The OSD's top line shows the mask as Z<hex>.
//   (  the cars (and their smoke)      )  the picture HUD        {  the panorama / backdrop op
//   }  the cars' shadows               #  the scenery (every face that is not ground)   $  the ground faces
// No ZigOS import.
// --------------------------------------------------------------------------
const trk = @import("trk.zig");

pub const CARS: u8 = 1;
pub const HUD: u8 = 2;
pub const BACKDROP: u8 = 4;
pub const SHADOWS: u8 = 8;
pub const SCENERY: u8 = 16;
pub const GROUND: u8 = 32;

pub var mask: u8 = 0;

const FLAG_GROUND: u8 = 0x10; // ground.FLAG_GROUND (not imported: ground.zig pulls the physics in)

pub fn on(bit: u8) bool {
    return mask & bit != 0;
}

/// The key's switch, or false when `cp` is not one of them.
pub fn key(cp: u32) bool {
    const bit: u8 = switch (cp) {
        '(' => CARS,
        ')' => HUD,
        '{' => BACKDROP,
        '}' => SHADOWS,
        '#' => SCENERY,
        '$' => GROUND,
        else => return false,
    };
    mask ^= bit;
    return true;
}

/// A track face skipped by the scenery / ground switches (collect's test, only while one of them is on).
pub inline fn skipFace(f: *const trk.Face) bool {
    if (mask & (SCENERY | GROUND) == 0) return false;
    return if (f.flags & FLAG_GROUND != 0) on(GROUND) else on(SCENERY);
}

test "the switches toggle and the faces follow them" {
    const std = @import("std");
    mask = 0;
    var f = std.mem.zeroes(trk.Face);
    try std.testing.expect(!skipFace(&f));
    try std.testing.expect(key('#'));
    try std.testing.expect(skipFace(&f));
    f.flags = FLAG_GROUND;
    try std.testing.expect(!skipFace(&f));
    try std.testing.expect(key('$'));
    try std.testing.expect(skipFace(&f));
    try std.testing.expect(!key('a'));
    mask = 0;
}
