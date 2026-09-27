// --------------------------------------------------------------------------
// ZIG mode's few hooks in the game's own code (scene.zig, hud.zig, sfx.zig,
// sound.zig, sprite.zig, machine.zig). They record what the presentation needs and never
// change what the game does, with one exception that IS the mode: in ZIG a
// screen drawn afresh during play is not charged the 21 VBLs the ST took
// (clock.REDRAW), so the flight goes on without the pause.
//
//   zig       ZIG mode is on (the harness's lockstep power-on sets ORIGINAL)
//   sandbox   the ring is drawing a sector off screen (zig_sandbox.zig): the
//             bonus bar is left out and nothing below is recorded
//   in_game   the back screen holds a sector of the world, drawn by line 1000
//             from the game loop; cleared the moment the program leaves the
//             game's labels (a briefing, the title, the hall of fame)
//   live_sx, live_al   the sector and layer that back screen shows
// --------------------------------------------------------------------------
const scr = @import("scr.zig");
const flow = @import("flow.zig");
const V = @import("vars.zig");
const v = &V.v;

pub var zig: bool = false;
pub var sandbox: bool = false;
pub var in_game: bool = false;
pub var live_sx: i32 = 0;
pub var live_al: i32 = 0;
/// Line-1000 draws of the world since power on (the harness's clock).
pub var draws: u32 = 0;
/// Line 1000 is drawing the live screen (its sprites belong to it).
var drawing: bool = false;
/// The harness's copy of the back screen as each live draw left it.
pub var capture: []u8 = &.{};

pub fn reset() void {
    sandbox = false;
    drawing = false;
    in_game = false;
    live_sx = 0;
    live_al = 0;
    draws = 0;
}

/// Line 1000 called from the game loop: 40 (a new screen) or 213 (the
/// pilot drifting down a layer), not the title screen's 2350.
fn gameDraw() bool {
    return flow.pc == .l40 or flow.pc == .l56;
}

/// ZIG: a screen drawn during play costs no VBLs.
pub fn freeRedraw() bool {
    return zig and !sandbox and gameDraw();
}

/// The start of line 1000.
pub fn beforeDraw() void {
    drawing = !sandbox;
}

/// The screen a sprite placed now stands on: the one being drawn, else the
/// one on show. (Not the game's sx, al: between a wrap and line 40, and
/// while the pilot drifts down, those name another screen.)
pub fn frame() [2]i32 {
    if (drawing) return .{ v.sx, @max(0, v.al) };
    return .{ live_sx, live_al };
}

/// The end of line 1000.
pub fn afterDraw() void {
    drawing = false;
    if (sandbox) return;
    live_sx = v.sx;
    live_al = v.al;
    draws +%= 1;
    if (gameDraw()) in_game = true;
    if (capture.len == scr.PIX) @memcpy(capture, scr.get(.back));
}

/// The labels at which the back screen still holds the world: the main
/// loop, its pause, the key waits and verdicts drawn over play, and the
/// fade that starts a briefing.
fn gameLabel(l: flow.L) bool {
    return switch (l) {
        .l34, .l34b, .l40, .l50, .l56, .l68, .l88b, .l90, .l151a, .l151b, .l90b, .l101b, .l102 => true,
        .l190a, .l190b, .l190c, .l220, .l225, .l227b, .l1660 => true,
        else => false,
    };
}

/// Every VBL (machine.zig): off the game's labels there is no world on screen.
pub fn tick() void {
    if (!gameLabel(flow.pc)) in_game = false;
}

/// The world is on screen and ZIG shows it.
pub fn flightView() bool {
    return zig and in_game and gameLabel(flow.pc);
}
