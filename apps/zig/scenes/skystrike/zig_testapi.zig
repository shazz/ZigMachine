// --------------------------------------------------------------------------
// The ZIG harness's door (apps/skystrike_zig*.mjs), next to testapi.zig's.
//
//   mode(m)      1 ZIG, 0 ORIGINAL, as the Z key would (without the notice)
//   capture(on)  keep a copy of the back screen as each live line-1000 draw
//                leaves it (ptr 6)
//   val(300+k)   0 the logic CRC (zig_crc.zig), 1 ZIG on, 2 the flight view
//                shown, 3/4 the live sector / layer, 5 live draws, 6/7 the
//                ring's centre sector / base layer, 8 ring valid, 9 slots
//                drawn, 10 rebuilds, 11 shifts, 12/13 the pan (ring coords),
//                14/15 the camera (world), 16 sandboxed draws, 17 sandboxed
//                draws that made a sound (checked 0), 18 sound commands
//                sent, 20+i the i'th sent (op << 8 | arg)
//   ptr(5..7)    5 the ring (960 x 520, the world plane's buffer), 6 the
//                capture (320 x 200), 7 the overlay (400 x 280)
// --------------------------------------------------------------------------
const zg = @import("zigos");
const scr = @import("scr.zig");
const sound = @import("sound.zig");
const hooks = @import("zig_hooks.zig");
const ring = @import("zig_ring.zig");
const scroll = @import("zig_scroll.zig");
const sandbox = @import("zig_sandbox.zig");
const mode = @import("zig_mode.zig");

pub const BASE: u32 = 300;

pub fn setMode(m: u32) callconv(.c) void {
    mode.set(m != 0);
}

pub fn capture(on: u32) callconv(.c) void {
    if (on == 0) {
        hooks.capture = &.{};
        return;
    }
    if (hooks.capture.len == 0) hooks.capture = zg.mem.mustAlloc(u8, scr.PIX);
}

pub fn val(k: u32) i32 {
    return switch (k) {
        0 => @bitCast(@import("zig_crc.zig").crc()),
        1 => @intFromBool(hooks.zig),
        2 => @intFromBool(hooks.flightView()),
        3 => hooks.live_sx,
        4 => hooks.live_al,
        5 => @bitCast(hooks.draws),
        6 => ring.cx,
        7 => ring.b,
        8 => @intFromBool(ring.valid),
        9 => @bitCast(ring.drawn),
        10 => @bitCast(ring.rebuilds),
        11 => @bitCast(ring.shifts),
        else => more(k),
    };
}

fn more(k: u32) i32 {
    return switch (k) {
        12 => scroll.scroll_x,
        13 => scroll.scroll_y,
        14 => scroll.cam_x,
        15 => scroll.cam_y,
        16 => @bitCast(sandbox.renders),
        17 => @bitCast(sandbox.leaks),
        18 => @intCast(sound.sent_n),
        60 => @bitCast(@import("zig_tracers.zig").shown),
        61 => @import("zig_tracers.zig").ink,
        62 => @import("zig_tracers.zig").tail,
        63 => @intFromBool(@import("zig_help.zig").shown),
        else => if (k >= 20 and k - 20 < sound.sent_n) sound.sent[k - 20] else -1,
    };
}

pub fn ptr(what: u32) ?[*]u8 {
    return switch (what) {
        5 => ring.buf.ptr,
        6 => if (hooks.capture.len != 0) hooks.capture.ptr else null,
        7 => if (scroll.over_px.len != 0) scroll.over_px.ptr else null,
        else => null,
    };
}
