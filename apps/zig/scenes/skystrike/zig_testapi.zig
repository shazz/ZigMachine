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
//                sent, 19 the screen off the world (0 picture, 1 scene,
//                2 hall), 20+i the i'th sent (op << 8 | arg); 60-63 tracers
//                shown, their two colours, the key help shown; 64/65 craters
//                made / filled in, 66-68 the ghx9 / sno9 / so9 addresses;
//                72 ZIG's music situation, 73 the MOD it last requested
//                (-1 none), 74 ORIGINAL's tune (0 off), 75 effect / YM /
//                gain commands the queue refused, 76 the title's credits
//                shown, 77-79 the music gains in flight / menus / game over
//                (x 1000), 80 the PSG voices
//   poke(300+k)  70 the crater lifetime in VBLs (0 never), 71 fullscreen
//                screens on / off, 77 the music gain in flight (x 1000, 0..1000),
//                80 the PSG voices (0..3)
//   ptr(5..11)   5 the ring (960 x 540, the world plane's buffer), 6 the
//                capture (320 x 200), 7 the overlay (400 x 280), 8 the
//                title's scroller zone as kept (176 x 8), 9 the intro's
//                borders (400 x 240), 10 / 11 the hall's picture and text
//                (320 x 200 each, 255 = no text)
// --------------------------------------------------------------------------
const zg = @import("zigos");
const scr = @import("scr.zig");
const sound = @import("sound.zig");
const hooks = @import("zig_hooks.zig");
const ring = @import("zig_ring.zig");
const scroll = @import("zig_scroll.zig");
const sandbox = @import("zig_sandbox.zig");
const mode = @import("zig_mode.zig");
const set = @import("zig_settings.zig");
const V = @import("vars.zig");
const music = @import("zig_music.zig");

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
        19 => @intFromEnum(hooks.screen),
        else => most(k),
    };
}

fn most(k: u32) i32 {
    return switch (k) {
        60 => @bitCast(@import("zig_tracers.zig").shown),
        61 => @import("zig_tracers.zig").ink,
        62 => @import("zig_tracers.zig").tail,
        63 => @intFromBool(@import("zig_help.zig").shown),
        64 => @bitCast(@import("zig_craters.zig").made),
        65 => @bitCast(@import("zig_craters.zig").filled),
        66 => V.v.ghx9,
        67 => V.v.sno9,
        68 => V.v.so9,
        70 => @bitCast(set.crater_life_vbls),
        72 => @intFromEnum(music.now),
        73 => if (music.playing) |m| @intFromEnum(m) else -1,
        74 => music.sndh_tune,
        75 => @bitCast(@import("zig_fx.zig").refused +% @import("zig_psg.zig").refused +% music.refused),
        76 => @intFromBool(@import("zig_credits.zig").shown),
        77 => milli(set.music_gain_play),
        78 => milli(set.music_gain_menus),
        79 => milli(set.music_gain_game_over),
        80 => set.psg_voices,
        else => if (k >= 20 and k - 20 < sound.sent_n) sound.sent[k - 20] else -1,
    };
}

pub fn poke(k: u32, value: i32) void {
    switch (k) {
        70 => set.crater_life_vbls = @bitCast(value),
        71 => set.fullscreen_screens = value != 0,
        // 0..1000 only: a gain outside 0..1 is refused downstream anyway, and a
        // huge one would overflow milli()'s @intFromFloat on the way back out.
        77 => if (value >= 0 and value <= 1000) {
            set.music_gain_play = @as(f32, @floatFromInt(value)) / 1000.0;
        },
        80 => if (value >= 0 and value <= 3) {
            set.psg_voices = @intCast(value);
        },
        else => {},
    }
}

fn milli(g: f32) i32 {
    return @intFromFloat(@round(g * 1000.0));
}

pub fn ptr(what: u32) ?[*]u8 {
    return switch (what) {
        5 => ring.buf.ptr,
        6 => if (hooks.capture.len != 0) hooks.capture.ptr else null,
        7 => if (scroll.over_px.len != 0) scroll.over_px.ptr else null,
        8 => &@import("zig_intro.zig").zone,
        9 => orNull(@import("zig_intro.zig").tiles),
        10 => orNull(@import("zig_hall.zig").pic),
        11 => orNull(@import("zig_hall.zig").layer),
        else => null,
    };
}

fn orNull(b: []u8) ?[*]u8 {
    return if (b.len != 0) b.ptr else null;
}
