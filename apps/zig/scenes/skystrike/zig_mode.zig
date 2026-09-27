// --------------------------------------------------------------------------
// ORIGINAL or ZIG, switched by Z at any moment (skystrike.zig's hostKey), as
// replicants_emlyn's mode.zig switches its own. ZIG is the default at power
// on; the harness's lockstep power-on (testapi.zig) sets ORIGINAL, whose
// screens and traces are the ST's.
//
//   ORIGINAL  the ST's 320 x 200 screen on plane 0, the 21-VBL pause of each
//             new screen, Maestro's digis and the PSG
//   ZIG       in play: the world scrolled by the hardware in a 400 x 280
//             frame with its borders open (zig_view.zig), no pause at a new
//             screen, the effects as samples on the Paula channels
//             (zig_sound.zig); the title, menu, briefing and hall of fame
//             stay the original's screens
//
// Only presentation and pacing differ; the switch changes no game state, and
// the key never reaches the game (it reads no Z). While a name is typed into
// the hall of fame, Z is a letter.
// --------------------------------------------------------------------------
const flow = @import("flow.zig");
const hooks = @import("zig_hooks.zig");
const hud = @import("zig_hud.zig");
const zsound = @import("zig_sound.zig");

pub fn set(zig: bool) void {
    hooks.zig = zig;
}

pub fn toggle() void {
    set(!hooks.zig);
    zsound.switched(hooks.zig);
    hud.notice(hooks.zig);
}

/// Z (or z) switches, except where the game reads letters.
pub fn isToggle(c: u8) bool {
    if (c != 'Z' and c != 'z') return false;
    return flow.pc != .l2310 and flow.pc != .l2311;
}
