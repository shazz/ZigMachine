// --------------------------------------------------------------------------
// What each 8xx value does: the Falcon's 32-byte entries at DATA $13FD74 (prototypes/
// falcon_ays_re/ANALYSIS.md §0), one per value. An entry names a timer routine (the replay's
// tick), a VBL routine (one of the five Videl mode setters, or none) and a main routine (the
// frame's drawing). Here: the screen mode its VBL slot sets, the part its main routine draws.
// `.hold` = main slot `rts` (804/805, 813's copy of the last frame): nothing is drawn, the
// last frame stays up. Values the script never fires keep `.other`.
// --------------------------------------------------------------------------
const screen = @import("screen.zig");

pub const Part = enum {
    hold,
    black, // 807 $4A76
    white, // 823 $6FE8
    white_band, // 824 $70C6: lines 25..174
    grey_flash, // 81A/81B $628E
    noise, // 809 $3172
    blobs, // 80B-811, 821
    blob_fade, // 822 (up) / 836 (down)
    text, // 81D/81E/82B/82C/832
    ship, // 820 $6B58
    flames, // 817-819, 81C, 834, 835 ($527C)
    chosneck, // 808 ($30A8 / $2CC4)
    chos_blur, // 816 ($4B10)
    chos_zoom, // 812 ($3E1C)
    credits, // 82D-831, 833, 837, 838 ($D334, $AB0C)
    grey_obj, // 829 $7A34: the grey ball-oid on the right of a white band
    thanks, // 839/83A $7D04/$7D4A: the grey ball-oid + the text
    orange, // 82A $7B2C, 83B/83C: the ball-oid + the greetings
    melt, // 83E $AD30: the feedback blur to the end
    strobe, // 814/815 ($49E6)
    smear, // 825 $71A8: feedback blur while the jolt runs, then hold
    jolt, // 826 $722A: the jolt only, the picture held
    other, // a part not ported yet: drawn black
};

pub const Entry = struct {
    mode: ?screen.Mode = null, // null: the VBL slot is rts, the mode stays
    part: Part = .other,
};

const F = screen.Mode.full; // $D40: mode 804
const D = screen.Mode.doubled; // $E74: mode 805

pub const TABLE = blk: {
    var t = [_]Entry{.{}} ** 64;
    t[0x04] = .{ .mode = F, .part = .hold };
    t[0x05] = .{ .mode = D, .part = .hold };
    t[0x07] = .{ .part = .black };
    t[0x08] = .{ .mode = D, .part = .chosneck };
    t[0x09] = .{ .mode = F, .part = .noise };
    for (0x0B..0x12) |v| t[v] = .{ .mode = D, .part = .blobs };
    t[0x21] = .{ .mode = D, .part = .blobs };
    t[0x12] = .{ .mode = D, .part = .chos_zoom };
    t[0x13] = .{ .mode = D, .part = .hold }; // $4790: the last frame copied = a freeze
    t[0x14] = .{ .mode = F, .part = .strobe };
    t[0x15] = .{ .mode = F, .part = .strobe };
    t[0x16] = .{ .part = .chos_blur }; // VBL rts: mode 805 stays
    for ([_]u8{ 0x17, 0x18, 0x19, 0x1C, 0x34, 0x35 }) |v| t[v] = .{ .mode = F, .part = .flames };
    t[0x1A] = .{ .mode = F, .part = .grey_flash };
    t[0x1B] = .{ .mode = D, .part = .grey_flash };
    for ([_]u8{ 0x1D, 0x1E, 0x2B, 0x2C, 0x32 }) |v| t[v] = .{ .mode = F, .part = .text };
    t[0x20] = .{ .mode = F, .part = .ship };
    t[0x22] = .{ .mode = D, .part = .blob_fade };
    t[0x36] = .{ .mode = D, .part = .blob_fade };
    t[0x23] = .{ .part = .white };
    t[0x24] = .{ .part = .white_band };
    t[0x25] = .{ .part = .smear };
    t[0x26] = .{ .part = .jolt };
    t[0x29] = .{ .mode = F, .part = .grey_obj };
    t[0x2A] = .{ .mode = F, .part = .orange };
    for (0x2D..0x32) |v| t[v] = .{ .mode = F, .part = .credits };
    t[0x33] = .{ .mode = F, .part = .credits }; // + the jolt
    t[0x37] = .{ .mode = F, .part = .credits }; // the tiled wipe ($ABBC)
    t[0x38] = .{ .mode = F, .part = .credits }; // ($ABE8)
    t[0x39] = .{ .mode = F, .part = .thanks };
    t[0x3A] = .{ .mode = F, .part = .thanks };
    t[0x3B] = .{ .mode = F, .part = .orange }; // + the quake ($7D9C)
    t[0x3C] = .{ .mode = F, .part = .orange }; // the quake stops ($7E18)
    t[0x3E] = .{ .mode = F, .part = .melt };
    break :blk t;
};
