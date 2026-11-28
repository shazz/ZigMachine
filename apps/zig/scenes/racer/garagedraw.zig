// --------------------------------------------------------------------------
// RACER: the car select screen (R82 board batch, item 10), after the track select's pick. Our own look (the front end's
// panels, the system font, the logo's gradient letters, the track's sky gradient behind): the car on show turns slowly
// in the middle, drawn by the race's own pipeline (carview.draw: the model's faces, its liveries, its shadow, the wheels
// rolling) from a camera fitted to its footprint; under it its name, its CAR CLASS and that class's top speed. Up / down
// the garage's cars (each read and shown at once), left / right the class, fire the race (front.zig).
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const cam = @import("cam.zig");
const carmodel = @import("carmodel.zig");
const carview = @import("carview.zig");
const clip = @import("clip.zig");
const fd = @import("frontdraw.zig");
const fix = @import("fix.zig");
const menu = @import("menu.zig");
const palette = @import("palette.zig");
const arcade = @import("arcade.zig");
const params = @import("feel_params.zig");

pub const TURN_STEP: i32 = 96; // Q16 turns a frame: a full turn in ~11 s at 60 fps
pub const FOOT = "UP/DN CAR L/R CLASS FIRE RACE BKSP";

pub var break_still = false; // racer_batch.mjs --break turn (key *, as the course): the car never turns

/// The car's heading `frames` frames into the screen (a slow turn, Q16 turns).
pub fn heading(frames: u32) i32 {
    if (break_still) return 0;
    return @intCast((frames *% @as(u32, TURN_STEP)) & 0xFFFF);
}

/// The showroom camera for a car whose footprint is `len` long (Q7): back 1.5 lengths, up 0.3, pitched down ~15 degrees (the
/// car sits a little above the view's middle, clear of the name panel).
pub fn showroom(at: [3]i32, len: i32) cam.Pose {
    const l: i32 = @max(len, 64) << 9; // Q16
    return .{ .pos = .{ at[0], at[1] + fix.mul(l, 19661), at[2] - fix.mul(l, 98304) }, .yaw = 0, .pitch = 0x0B00_0000 };
}

/// The model turning, through the race's pipeline (no track face: an empty tile list).
fn model(d: anytype, fb: *zg.LogicalFB) void {
    const t = d.cur();
    const m = carmodel.of(0);
    const at = if (t.grid.len != 0) t.grid[0].pos else t.line[0].pos;
    var v = cam.view(showroom(at, m.foot.z1 - m.foot.z0));
    clip.near = clip.NEAR;
    d.f.list = &.{};
    d.f.stats = .{};
    d.f.collect(t, &v, false);
    const s = carview.Snap{ .pos = at, .angle = heading(d.front.frames), .spin = d.front.frames << 23 };
    carview.draw(&d.f, &d.caches[0], &v, t, s, null, m, carmodel.LIVERY[0]);
    d.f.sort();
    _ = d.p.fill(fb, &d.f);
}

/// A class's top speed as the HUD reads speed (racehud: 250 x 3.6 x a tick's velocity).
pub fn topKmh(class: usize) u32 {
    return @intCast((@as(u64, @intCast(params.CLASSES[class].top)) * 900) >> 16);
}

pub fn draw(d: anytype, os: *zg.ZigOS, fb: *zg.LogicalFB, p: menu.Px) void {
    model(d, fb);
    os.blitSync(); // WHY: the AFFINE fill's spans land before the panels
    p.panel(8, 16, 304, 12);
    fd.text(os, fb, "SELECT A CAR", 160 - 6 * 8, 18, menu.HILITE);
    p.panel(8, 142, 304, 34);
    var nb: [16]u8 = undefined;
    const name = std.ascii.upperString(&nb, d.lib.cars.label()[0..@min(d.lib.cars.label().len, nb.len)]);
    p.big(os.system_font, name, 160 - @as(i32, @intCast(name.len)) * 8, 145, 2);
    var b: [40]u8 = undefined;
    const cls = params.CLASSES[arcade.class].name;
    const line = std.fmt.bufPrint(&b, "< {s} >  TOP {} KM/H", .{ cls, topKmh(arcade.class) }) catch "";
    fd.text(os, fb, line, 160 - @as(i32, @intCast(line.len)) * 4, 164, palette.INK);
    p.panel(8, 178, 304, 10);
    fd.text(os, fb, FOOT, 160 - FOOT.len * 4, 179, palette.INK);
}
