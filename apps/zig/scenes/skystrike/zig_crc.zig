// --------------------------------------------------------------------------
// The game's LOGIC state as one number, for the harness's proof that ZIG
// mode changes presentation and pacing only (apps/skystrike_zig_crc.mjs):
// every BASIC variable, the banks' bytes, RND, the zones, the sprite table,
// the flow's place and the main loop's pass count, and both screens (POINT
// reads them: they are game state here).
//
// Left out, because they are PACING: TIMER and the VBL count, the waits the
// flow counts down, the four variables that copy TIMER -- z2 and t (128),
// fps# (120) and lxt (the time of the last explosion, 404) -- and where an
// OFF sprite stands (below). And the sound actually sent (sound.sent), which
// is presentation.
// --------------------------------------------------------------------------
const std = @import("std");
const scr = @import("scr.zig");
const sprite = @import("sprite.zig");
const zone = @import("zone.zig");
const rnd = @import("rnd.zig");
const flow = @import("flow.zig");
const sound = @import("sound.zig");
const V = @import("vars.zig");
const v = &V.v;

const PACING = [_][]const u8{ "z2", "t", "fps_f", "lxt" };

fn pacing(comptime name: []const u8) bool {
    inline for (PACING) |p| if (comptime std.mem.eql(u8, p, name)) return true;
    return false;
}

fn feed(h: *std.hash.Fnv1a_32, x: anytype) void {
    const T = @TypeOf(x);
    if (T == V.Str or T == V.Name) return h.update(x.get());
    switch (@typeInfo(T)) {
        .array => for (x) |e| feed(h, e),
        .int => h.update(std.mem.asBytes(&x)),
        .float => h.update(std.mem.asBytes(&x)),
        .bool => h.update(&.{@intFromBool(x)}),
        .@"enum" => h.update(&.{@intCast(@intFromEnum(x))}),
        .@"struct" => |s| inline for (s.fields) |f| feed(h, @field(x, f.name)),
        else => @compileError("zig_crc: no rule for " ++ @typeName(T)),
    }
}

fn vars(h: *std.hash.Fnv1a_32) void {
    @setEvalBranchQuota(20000); // a comptime name test for each of ~340 variables
    inline for (@typeInfo(V.V).@"struct".fields) |f| {
        if (!comptime pacing(f.name)) feed(h, @field(v.*, f.name));
    }
}

/// An OFF sprite's place is read by nothing (ZONE, COLLIDE, UPDATE and PUT
/// SPRITE all test `on`; SPRITE sets every field), but a MOVE program left
/// running (the title's plane) keeps moving it by the VBL: pacing again.
fn sprites(h: *std.hash.Fnv1a_32) void {
    for (sprite.spr) |s| {
        feed(h, s.on);
        if (s.on) feed(h, s);
    }
}

pub fn crc() u32 {
    var h = std.hash.Fnv1a_32.init();
    vars(&h);
    h.update(&scr.extra5);
    h.update(&scr.extra6);
    h.update(&scr.bank7);
    feed(&h, rnd.save());
    feed(&h, zone.save());
    sprites(&h);
    feed(&h, flow.pc);
    feed(&h, @import("pass.zig").passes);
    feed(&h, sound.log_total);
    h.update(scr.get(.back));
    h.update(scr.get(.physic));
    return h.final();
}

