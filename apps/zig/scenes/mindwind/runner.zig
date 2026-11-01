// --------------------------------------------------------------------------
// Plays script.ops one frame at a time: instant ops run until one that takes
// frames, which then runs one frame of itself (the demo's loop bodies: the
// effect, then a wait for the VBL).
// --------------------------------------------------------------------------
const zg = @import("zigos");
const data = @import("data.zig");
const script = @import("script.zig");
const lines = @import("lines.zig");
const vram = @import("vram.zig");
const overlay = @import("overlay.zig");
const stripes = @import("stripes_fx.zig");
const picture = @import("picture_fx.zig");
const rainbow = @import("rainbow_fx.zig");
const bands = @import("bands.zig");
const scroller = @import("scroller.zig");

pub const MUSIC = "mindwind.sndh"; // Count Zero, the demo's DMA music (apps/zig/assets/screens/mindwind/mw_music.s)

pub var frame: u32 = 0; // since the music started (the song positions are counted from here)
pub var mode: script.Mode = .fader;
pub var hook: bool = false;
pub var slide_row: ?u16 = null; // the intro's slide: blank this line and the one above after the scroller moves
pub var ended: bool = false;
var pc: usize = 0;
var left: u32 = 0; // frames left in the current op (0 = not started)
var k: u32 = 0; // frames done in it

fn palette(p: script.Pal) [16]u16 {
    return switch (p) {
        .black => [_]u16{0} ** 16,
        .stripes => data.palette(data.pal_stripes),
        .girl => data.palette(data.girl_pal),
    };
}

fn effect(fx: script.Fx) void {
    switch (fx) {
        .none => {},
        .flat => stripes.step(.flat),
        .pulse => stripes.step(.pulse),
        .moire => stripes.step(.moire),
        .blocks => stripes.step(.blocks),
        .swirl => stripes.step(.swirl),
        .bands => stripes.step(.bands),
        .wobble => picture.wobble(overlay.pal[0]),
        .flip => picture.flip(overlay.pal[0]),
        .full3 => rainbow.full(2),
        .full2 => rainbow.full(1),
        .full1 => rainbow.full(0),
        .rewind_bands => bands.step(),
    }
}

/// Frames an op takes; 0 = instant. `until` and `reveal` say when they end themselves.
fn length(op: script.Op) u32 {
    return switch (op) {
        .run => |r| r.frames,
        .until, .reveal => 1 << 30,
        .bars_in, .flash_in, .flash_out => 17,
        .bars_out => 16,
        .bars_instant => 2,
        .scroller_slide => 110,
        .end => 1 << 30,
        else => 0,
    };
}

fn instant(op: script.Op) void {
    switch (op) {
        .fade => |f| overlay.fadeTo(palette(f.to), f.speed),
        .mode => |m| mode = m,
        .bars_now => |s| overlay.bars(s),
        .blank_all => lines.fill(0, lines.ROWS, vram.blank, 0),
        .scroller => |on| scroller.on = on,
        .scroller_reverse => scroller.reverse(),
        .music => |c| _ = zg.sndhCall(MUSIC, switch (c) {
            .rewind_sfx => 0x8001,
            .reverse_song => 0x8002,
        }),
        .vhs => |on| overlay.vhs_on = on,
        .hook => |on| hook = on,
        .field_blank => rainbow.empty(),
        .reveal => |i| rainbow.startReveal(i),
        else => {},
    }
}

/// One frame of a frame-taking op; true when the op is over.
fn step(op: script.Op) bool {
    switch (op) {
        .run => |r| effect(r.fx),
        .until => |u| {
            effect(u.fx);
            return frame + 1 >= u.frame;
        },
        .bars_in => overlay.bars(k),
        .bars_out => overlay.bars(16 - k),
        .bars_instant => {
            overlay.vhs_on = k == 1;
            overlay.bars(16);
        },
        .scroller_slide => {
            scroller.row = @intCast(0x65 + k);
            slide_row = scroller.row;
        },
        .reveal => return rainbow.reveal(),
        .flash_in => bands.flat(if (k < 16) bands.grey(@intCast(k)) else 0x0fff),
        .flash_out => bands.flat(if (k < 16) bands.grey(@intCast(15 - k)) else 0),
        .end => ended = true,
        else => {},
    }
    return false;
}

pub fn tick() void {
    slide_row = null;
    while (pc < script.ops.len) {
        const op = script.ops[pc];
        const n = length(op);
        if (n == 0) {
            instant(op);
            pc += 1;
            continue;
        }
        if (left == 0) {
            left = n;
            k = 0;
            if (op == .reveal) instant(op);
        }
        const done = step(op);
        k += 1;
        left -= 1;
        if (done or left == 0) {
            left = 0;
            if (op == .scroller_slide) scroller.row = 0xd2;
            pc += 1;
        }
        break;
    }
    frame += 1;
}
