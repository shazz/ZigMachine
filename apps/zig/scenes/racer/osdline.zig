// --------------------------------------------------------------------------
// RACER: the OSD's state line (key o, Matt 27 Nov): every option and debug toggle in force, in the top
// band (it replaces that band's line while the OSD is on; the bottom band keeps the stage timings):
//   FILL CPU|AFF  MUL MS|PL|F32  SHADE FL|LI|SO  SHADOW RL|HR|CK (real, real + headroom, checkerboard)
//   HAZE H1|H0  R n  PHYSICS ARC|CLA (+ the class's initial)  POV FAR|NEA|COC  MUSIC M1|M0  LAPS L n
// 40 columns at most (hud.COLS). No ZigOS import.
// --------------------------------------------------------------------------
const std = @import("std");
const arcade = @import("arcade.zig");
const fx = @import("fx.zig");
const haze = @import("haze.zig");
const params = @import("feel_params.zig");
const project = @import("project.zig");
const rules = @import("rules.zig");
const shadow = @import("shadow.zig");

pub const Toggles = struct { cpu: bool, r: u32, pov: []const u8, music: bool };

const SHADES = [_][]const u8{ "FL", "LI", "SO" };

fn shadowTag() []const u8 {
    return if (shadow.fake) "CK" else if (project.headroom) "HR" else "RL";
}

var hide_buf: [4]u8 = undefined;
var lod_buf: [8]u8 = undefined;

/// " Z<hex>" while a board A/B switch hides something (hide.zig), else nothing (the default line is unchanged).
fn hideTag() []const u8 {
    const m = @import("hide.zig").mask;
    if (m == 0) return "";
    return std.fmt.bufPrint(&hide_buf, " Z{X}", .{m}) catch "";
}

pub fn line(buf: []u8, t: Toggles) []const u8 {
    const mul = if (fx.use_f32) "F32" else if (fx.use_zmx) "MS" else "PL";
    const shade = SHADES[project.shade];
    const phys = if (arcade.model == .arcade) "ARC" else "CLA";
    const pov = t.pov[0..@min(t.pov.len, 3)];
    return std.fmt.bufPrint(buf, "{s} {s} {s} {s} H{d} R{d} {s}{c} {s} M{d} L{d}{s}{s}", .{
        if (t.cpu) "CPU" else "AFF",   mul,          shade,                                    shadowTag(),
        @intFromBool(haze.on),         t.r,          phys,                                     params.CLASSES[arcade.class].name[0],
        pov,                           @intFromBool(t.music), rules.race_laps, hideTag(), @import("carlod.zig").tag(&lod_buf),
    }) catch "";
}
