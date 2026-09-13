// --------------------------------------------------------------------------
// The eleven doors of the menu street and where each one leads.
//
// Rectangles and demo_name come from the TMX "Doors" object group (generated
// menu_map.zig); the ScreenIDs are jsApp.ScreenID (main.js:13-43), and each
// loader's own target is its me.state.change (screens/*/loader.js). Titles are
// the names the remake's index.html status table gives the screens.
//
// None of the twelve screens is ported yet, so `tag` (the cart a later port
// will launch) is null everywhere and entering a door shows COMING SOON.
// --------------------------------------------------------------------------
const std = @import("std");
const map = @import("../../assets/screens/union_demo/menu_map.zig"); // not assets.zig: tests natively
const Box = @import("charly.zig").Box;

/// jsApp.ScreenID values (main.js:13-43).
pub const ScreenId = enum(u16) {
    tcb1_loader = 101,
    l16_loader = 102,
    beatdis_loader = 103,
    superscroller_loader = 104,
    reps_loader = 105,
    deltaforce_loader = 106,
    intro_loader = 107,
    multifake_loader = 108,
    tnt2_loader = 109,
    tnt1_loader = 110,
    textracker_loader = 111,
    tnt3_loader = 112,
    copier_loader = 113,
    tcb1_screen = 114,
    l16_screen = 115,
    beatdis1024_screen = 116,
    superscroller_screen = 117,
    reps_screen = 118,
    deltaforce_screen = 119,
    intro_screen = 120,
    multifake_screen = 121,
    tnt2_screen = 122,
    tnt1_screen = 123,
    textracker_screen = 124,
    tnt3_screen = 125,
    copier_screen = 126,
    beatdis512_screen = 127,
};

pub const Door = struct {
    x: f32,
    y: f32,
    w: f32,
    h: f32,
    loader: ScreenId, // what DoorEntity.onCollision changes state to
    screen: ScreenId, // what that loader then starts
    title: []const u8,
    tag: ?[]const u8 = null, // the demo-<tag> cart, once the screen is ported
};

const Route = struct { demo_name: []const u8, screen: ScreenId, title: []const u8 };
const ROUTES = [_]Route{
    .{ .demo_name = "BEATDIS_LOADER", .screen = .beatdis1024_screen, .title = "TCB1" }, // Space; Enter = 512 KB
    .{ .demo_name = "DELTAFORCE_LOADER", .screen = .deltaforce_screen, .title = "DELTA FORCE" },
    .{ .demo_name = "TNT3_LOADER", .screen = .tnt3_screen, .title = "TNT3" },
    .{ .demo_name = "SUPERSCROLLER_LOADER", .screen = .superscroller_screen, .title = "TCB2" },
    .{ .demo_name = "TNT1_LOADER", .screen = .tnt1_screen, .title = "TNT1" },
    .{ .demo_name = "REPS_LOADER", .screen = .reps_screen, .title = "REPS" },
    .{ .demo_name = "TNT2_LOADER", .screen = .tnt2_screen, .title = "TNT2" },
    .{ .demo_name = "L16_LOADER", .screen = .l16_screen, .title = "L16" },
    .{ .demo_name = "MULTIFAKE_LOADER", .screen = .multifake_screen, .title = "TCB3" },
    .{ .demo_name = "COPIER_LOADER", .screen = .copier_screen, .title = "COPIER TEX" },
    .{ .demo_name = "TEXTRACKER_LOADER", .screen = .textracker_screen, .title = "HIDDEN SCREEN" },
};

/// DOORS[i] is the TMX object i, joined with its route by demo_name at comptime.
pub const DOORS: [map.DOORS.len]Door = blk: {
    var out: [map.DOORS.len]Door = undefined;
    for (map.DOORS, 0..) |d, i| {
        const route = for (ROUTES) |r| {
            if (std.mem.eql(u8, r.demo_name, d.demo_name)) break r;
        } else @compileError("no route for door " ++ d.demo_name);
        out[i] = .{
            .x = d.x,
            .y = d.y,
            .w = d.w,
            .h = d.h,
            .loader = @field(ScreenId, lower(d.demo_name)),
            .screen = route.screen,
            .title = route.title,
        };
    }
    break :blk out;
};

fn lower(comptime s: []const u8) []const u8 {
    comptime var buf: [s.len]u8 = undefined;
    inline for (s, 0..) |c, i| buf[i] = std.ascii.toLower(c);
    return &buf;
}

/// The door Charly's collision box overlaps (me.Rect.overlaps: strict edges),
/// as me.game.collide reports it; null when he is in front of none.
pub fn touching(b: Box) ?usize {
    for (DOORS, 0..) |d, i| {
        if (b.left < d.x + d.w and d.x < b.right and b.top < d.y + d.h and d.y < b.bottom) return i;
    }
    return null;
}
