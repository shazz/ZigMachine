// --------------------------------------------------------------------------
// The main loop's 18 calls ($0018-$007E, then bra $18), in order (the model's
// joust_model.CALLS), and the driver that feeds each call's cycles to the
// pacer as the model's run_call does.
// --------------------------------------------------------------------------
const State = @import("state.zig");
const pace = @import("pace.zig");
const riders = @import("riders_move.zig");
const eggs = @import("eggs.zig");
const blit = @import("riders_blit.zig");
const ai = @import("ai.zig");
const coll = @import("coll.zig");
const lava = @import("hazards_lava.zig");
const flame = @import("hazards_flame.zig");
const ptero = @import("hazards_ptero.zig");
const troll = @import("hazards_troll.zig");
const pads = @import("hazards_pads.zig");
const input = @import("flow_input.zig");
const popups = @import("flow_popups.zig");
const waves = @import("flow_waves.zig");
const St = State.St;

pub const NCALLS = 18;

/// Run call k as the model's run_call does: the body, then the rest of its
/// pure cycles to the pacer.
pub fn runCall(st: *St, k: usize) bool {
    st.cycles = -1;
    st.clocked = 0;
    if (!body(st, k)) return false;
    if (st.cycles < 0) st.oob += 1; // every call counts its cycles
    // A call that left the frame (jmp $18 / $6, Pterm) clocked its own cycles.
    if (st.exit != .none) return true;
    st.pacer.run(st, st.cycles - st.clocked);
    return true;
}

/// Call k's body. Calls 5, 6 and 17 are not here: they can start a wait that
/// lasts as long as the player likes (a new game's name entry, the P pause,
/// GAME OVER's name entry), so machine.zig runs them itself, suspending
/// across host frames. Returns false for those.
pub fn body(st: *St, k: usize) bool {
    switch (k) {
        0 => lava.call_7724_lava_rise(st),
        1 => lava.call_778e_lava_bubbles(st),
        2 => flame.call_7930_lava_flames(st),
        3 => pace.call_0344_pace(st),
        4 => eggs.call_26a4_die_egg_hatch(st),
        7 => ai.call_20a6_enemy_ai(st),
        8 => ptero.call_4c6e_pterodactyl(st),
        9 => riders.call_2d8c_riders(st),
        10 => coll.call_3932_collisions(st),
        11 => blit.call_0540_platform_redraw(st),
        12 => popups.call_43ce_popups(st),
        13 => troll.call_488a_troll(st),
        14 => pads.call_75e2_spawn_pads(st),
        15 => waves.call_7b8e_waves(st),
        16 => input.call_0ac8_sfx_prio(st),
        else => return false,
    }
    return true;
}
