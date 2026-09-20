// --------------------------------------------------------------------------
// part1()'s choreography (screen.js:224-269).
//
// The remake cues every step off the ProTracker player's own state —
// `module.position == 0 && module.row == 7`, then `modsample[ch] == n`, where
// modsample[ch] is the 0-BASED sample index the player latched on that
// channel's last note (pt.js:690, `channel.sample = nn - 1`). This machine's MOD
// player exposes neither, so the cues were resolved OFF THE TUNE: hybridglenz.mod
// was stepped row by row at its speed/bpm to the first note that satisfies each
// test. Order/row and the second it falls on are recorded beside each constant;
// they are the tune's, not a guess, and they are the only numbers here that did
// not come out of screen.js.
//
// The consequence of not reading the player: the timeline is a wall clock, so it
// runs whether or not the visitor has enabled sound, and it cannot re-sync if
// the browser drops a second of frames.
// --------------------------------------------------------------------------
const A = @import("assets.zig");
const Color = @import("zigos").Color;

pub const P1: f32 = 1.68; // order 0 row 7            — the square flies in
pub const P2: f32 = 9.12; // order 0 row 38, ch3 smp 14 — txt1
pub const P3: f32 = 12.00; // order 0 row 50, ch2 smp 23 — txt2
pub const P4: f32 = 15.48; // order 1 row 0,  ch1 smp 23 — txt3
pub const P6: f32 = 17.88; // order 1 row 10, ch2 smp 14 — the bar slides up
pub const P5: f32 = 22.68; // order 1 row 30, ch1 smp 27 — the logo, white-hot
pub const P7: f32 = 25.56; // order 2 row 0,  ch0 smp 2  — go()

/// The last fade (the logo's white flash) ends here; nothing moves after.
pub const FADES_END: f32 = P5 + 1;

pub const BAR_FROM: f32 = 600; // scr.pos, 2x: below the 568-tall canvas
pub const BAR_TO: f32 = 508;

/// Linear.easeNone progress through a `dur`-second tween that starts at `at`.
fn ramp(t: f32, at: f32, dur: f32) f32 {
    if (t <= at) return 0;
    if (t >= at + dur) return 1;
    return (t - at) / dur;
}

fn mix(a: f32, b: f32, k: f32) f32 {
    return a + (b - a) * k;
}

fn shade(from: Color, to: Color, k: f32) Color {
    return .{
        .r = @intFromFloat(@round(mix(@floatFromInt(from.r), @floatFromInt(to.r), k))),
        .g = @intFromFloat(@round(mix(@floatFromInt(from.g), @floatFromInt(to.g), k))),
        .b = @intFromFloat(@round(mix(@floatFromInt(from.b), @floatFromInt(to.b), k))),
        .a = 255,
    };
}

/// Everything the tweens hold at `t` seconds. The square's x is halved here
/// (the remake's 100 is 100 canvas px = 50 of ours); rot and size are not.
pub const State = struct {
    sq_x: f32,
    sq_rot: f32,
    sq_size: f32,
    sq_solid: bool, // square.alpha == 1: drawn as flat white
    panel_on: bool, // square.alpha != 1: the framed panel is drawn under it
    panel_fade: f32, // ... and square.alpha over it IS the panel's colour
    txt: [3]f32, // txts.alpha1..3
    flash: f32, // txts.alpha4, tsl-logowhite over tsl-logo
    logo_on: bool,
    bar_y: f32, // scr.pos, halved to plane rows
    running: bool, // p7 fired: part1 hands over to go()

    pub fn at(t: f32) State {
        const k = ramp(t, P1, 4); // x:0, size:1, rot:0 over 4 s
        const alpha = 1 - ramp(t, P1 + 4, 1); // then square.alpha 1 -> 0 over 1 s
        return .{
            .sq_x = mix(50, 0, k),
            .sq_rot = mix(-180, 0, k),
            .sq_size = mix(2.5, 1, k),
            .sq_solid = alpha == 1,
            .panel_on = alpha < 1, // the remake's `if (square.alpha != 1)`
            .panel_fade = alpha,
            .txt = .{
                ramp(t, P2, 1) * (1 - ramp(t, P2 + 2, 1)),
                ramp(t, P3, 1) * (1 - ramp(t, P3 + 2, 1)),
                ramp(t, P4, 1) * (1 - ramp(t, P4 + 2, 2)), // this one falls over 2 s
            },
            .flash = if (t < P5) 0 else 1 - ramp(t, P5, 1),
            .logo_on = t >= P5,
            .bar_y = mix(BAR_FROM, BAR_TO, ramp(t, P6, 5)) / 2,
            .running = t >= P7,
        };
    }
};

/// How far through the fades this state is. The scene uploads the palette when
/// this changes, which is what gets the FINAL, all-zero state installed: a plain
/// `clock < FADES_END` cut-off stops one frame early and leaves the logo a
/// couple of levels light forever.
pub fn fadeSignature(s: State) f32 {
    return s.panel_fade + s.txt[0] + s.txt[1] + s.txt[2] + s.flash;
}

/// The three fades the remake does with globalAlpha are palette moves here,
/// which is exact: each one covers a region of a single index.
///   - the panel: the square dissolving over it is white -> '#221133';
///   - txt1/2/3: white ink appearing out of the '#334444' fill;
///   - the logo: tsl-logowhite covers every logo colour BUT its own '#221133',
///     so that one entry is left alone and the other 22 flash from white.
pub fn applyFades(s: State, out: *[256]Color) void {
    out[A.PANEL] = shade(A.PANEL_RGB, A.WHITE_RGB, s.panel_fade);
    for (s.txt, 0..) |alpha, i| out[A.TXT_BASE + i] = shade(A.BG_RGB, A.WHITE_RGB, alpha);
    for (A.LOGO_COLORS, 0..) |c, i| {
        const flash = if (i == A.LOGO_PANEL) 0 else s.flash;
        out[A.LOGO_BASE + i] = shade(c, A.WHITE_RGB, flash);
    }
}
