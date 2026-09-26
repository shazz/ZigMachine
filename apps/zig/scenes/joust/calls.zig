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
const gameover = @import("flow_gameover.zig");
const newgame = @import("flow_newgame.zig");
const name = @import("flow_name.zig");
const St = State.St;

/// What the outside world gives one game frame: the joystick bytes exactly as
/// the IKBD delivered them to call 5 (bit7 fire, bit3 right, bit2 left, bit1
/// down, bit0 up), P1 = port 1, P2 = port 0.
pub const Input = struct {
    joy: [2]u8,
};

/// The machine state the synchronous (dev) driver needs besides St. The waits
/// (pause, name entry) run a VBL at a time, suspending and resuming as they
/// do across host frames.
pub var seed: u32 = 0;
var ne: name.NameEntry = undefined;
var c6: input.Call6 = undefined;

pub const NCALLS = 18;

/// Run call k as the model's run_call does: the body, then the rest of its
/// pure cycles to the pacer (call 5 through the joystick wait).
pub fn runCall(st: *St, k: usize, inp: *const Input) bool {
    st.cycles = -1;
    st.clocked = 0;
    if (!body(st, k, inp)) return false;
    if (st.cycles < 0) st.oob += 1; // every call counts its cycles
    // A call that left the frame (jmp $18 / $6, Pterm) clocked its own cycles.
    if (st.exit != .none) return true;
    if (k == 5) {
        st.pacer.joystick(st, st.cycles);
    } else {
        st.pacer.run(st, st.cycles - st.clocked);
    }
    return true;
}

/// Call k's body. Returns false for a call not transcribed (dev builds only).
pub fn body(st: *St, k: usize, inp: *const Input) bool {
    switch (k) {
        5 => switch (input.call_1e10_joystick(st, inp.joy)) {
            .done => {},
            .new_game => |pre| {
                if (newgame.new_game(st, pre, &seed, &ne) == .name_entry)
                    while (name.loop(st, &ne, &inp.joy, st.pacer.vbl + 1) == .suspended) {};
            },
        },
        6 => if (input.call_1c92_keyboard(st, &c6, st.pacer.vbl + 1) == .suspended) {
            while (input.pause(st, &c6, st.pacer.vbl + 1) == .suspended) {}
        },
        12 => popups.call_43ce_popups(st),
        15 => waves.call_7b8e_waves(st),
        16 => input.call_0ac8_sfx_prio(st),
        17 => if (gameover.call_450e_game_over(st, &ne)) {
            while (name.loop(st, &ne, &inp.joy, st.pacer.vbl + 1) == .suspended) {}
        },
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
        13 => troll.call_488a_troll(st),
        14 => pads.call_75e2_spawn_pads(st),
        else => return false,
    }
    return true;
}
