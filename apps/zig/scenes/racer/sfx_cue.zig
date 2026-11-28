// --------------------------------------------------------------------------
// RACER: the rule that starts one of the effects' PSG phrases (sfx.zig: the countdown, go, the chime, the lap, the
// endings) on a change of the race's state; split from sfx.zig (file size). No ZigOS import.
// --------------------------------------------------------------------------
const sfx = @import("sfx.zig");
const Snap = sfx.Snap;

/// The phrase a change of the race's state starts, or null.
pub fn cue(a: Snap, b: Snap) ?[]const sfx.Note {
    if (b.outcome != a.outcome) return switch (b.outcome) {
        .win => &sfx.WIN,
        .timeout => &sfx.LOSE,
        else => null,
    };
    if (b.state == .countdown and (a.state != .countdown or crossed(a.ticks, b.ticks, 30) or crossed(a.ticks, b.ticks, 60))) return &sfx.COUNT;
    if (b.state == .race and a.state == .countdown) return &sfx.GO;
    if (b.laps > a.laps) return &sfx.LAP;
    if (b.gates > a.gates) return &sfx.CHIME;
    return null;
}

fn crossed(a: u32, b: u32, at: u32) bool {
    return a < at and b >= at;
}
