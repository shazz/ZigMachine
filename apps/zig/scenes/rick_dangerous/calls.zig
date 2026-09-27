// --------------------------------------------------------------------------
// The loop's calls that run straight through (calls 0-5, 9-12, 15, 16) and
// its P test after call 14 (the model's rick_model.CALLS and rick_loop.py).
// --------------------------------------------------------------------------
const m = @import("ram.zig");
const F = @import("fields.zig");
const io = @import("io.zig");
const hud = @import("hud.zig");
const draw = @import("draw.zig");
const pass = @import("pass.zig");
const actors = @import("actors.zig");
const world = @import("world.zig");
const rick = @import("rick.zig");

/// $3D7D8: P pauses unless dying, at a submap edge, or another key.
pub fn pauses() bool {
    const x = m.sw(F.R_X);
    return !(m.rb(F.RICK_DYING) != 0 or x <= 0 or x >= 0xE8 or m.rb(F.KEY) != 0x19);
}

/// A call that runs straight through (calls 0-5, 9-12, 15, 16).
pub fn run(k: i64) void {
    io.beginCall(k);
    switch (k) {
        0 => hud.score(),
        1 => hud.bullets(),
        2 => hud.dynamite(),
        3 => hud.lives(),
        4, 15 => hud.clearSlots(),
        5 => {
            rick.restoreCheckpoint();
            m.wb(F.SPAWN_ROWS, 7); // $3D792, the loop's own move.b #7,$3904A
        },
        9 => draw.erase(),
        10 => pass.loop(),
        11 => actors.bonusTimer(),
        12 => world.rng(),
        16 => rick.flag(),
        else => {},
    }
    io.endCall();
}
