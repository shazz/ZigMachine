// --------------------------------------------------------------------------
// The two sources of .kt commands (music.c): the pattern's volume column and
// command (mus_exec_track_command) and the instrument's program, a 32-step
// list of commands with jumps, labels and loops (mus_exec_prog_tick). Both end
// in do_command (kt_cmd.zig).
// --------------------------------------------------------------------------
const s = @import("kt_song.zig");
const eng = @import("kt_engine.zig");
const cmd = @import("kt_cmd.zig");

const Engine = eng.Engine;

const FX_END: u16 = 0xffff;
const FX_NOP: u16 = 0xfffe;
const FX_JUMP: u16 = 0xff00;
const FX_LABEL: u16 = 0xfd00;
const FX_LOOP: u16 = 0xfe00;

pub fn trackCommand(e: *Engine, i: usize, first_tick: bool) void {
    const t = &e.track[i];
    const st = t.step();
    const inst = st.command;
    const vol = st.volume;
    const tick = e.song_counter;
    switch (vol & 0xf0) {
        0xb0 => cmd.run(e, i, tick, 0x1700 | @as(u16, vol & 0xf), false), // PAN_LEFT
        0xc0 => cmd.run(e, i, tick, 0x1900 | @as(u16, vol & 0xf), false), // PAN_RIGHT
        0xa0 => { // SET_PAN
            const v: u16 = vol & 0xf;
            const pan: u16 = if (v <= 8) v * 64 / 8 else (v - 8) * 64 / 8 + 64;
            cmd.run(e, i, tick, 0x1800 | pan, false);
        },
        0xe0 => cmd.run(e, i, tick, 0x0a00 | (@as(u16, vol & 0xf) << 4), false), // FADE_UP
        0xd0 => cmd.run(e, i, tick, 0x0a00 | @as(u16, vol & 0xf), false), // FADE_DN
        else => if (vol <= s.MAX_VOLUME) cmd.run(e, i, if (first_tick) 0 else tick, 0x0c00 | @as(u16, vol), false),
    }
    switch (inst & 0xff00) {
        0x0000, 0x1000 => { // ARPEGGIO (with a parameter), SET_EXT_ARP
            if (inst & 0xff00 == 0 and inst & 0xff == 0) return; // same settings
            t.extarp1 = @intCast((inst & 0xf0) >> 4);
            t.extarp2 = @intCast(inst & 0xf);
        },
        else => cmd.run(e, i, tick, inst, false),
    }
}

/// mus_exec_prog_tick: run the program's step (and the steps chained to it by
/// bit 15); `advance` moves the program on.
pub fn progTick(e: *Engine, i: usize, advance: bool) void {
    const mc = &e.chn[i];
    const prog = &mc.instrument.?.program;
    var tick: usize = mc.program_tick;
    var visited = [_]bool{false} ** s.PROG_LEN;
    while (true) {
        const inst = prog[tick];
        if (inst == FX_END) {
            mc.flags &= ~eng.CHN_PROGRAM_RUNNING;
            return;
        }
        var dont_reloop = false;
        if (inst != FX_NOP) switch (inst & 0xff00) {
            FX_JUMP => {
                if (visited[tick]) return; // two jumps into each other: the program hangs
                visited[tick] = true;
                tick = inst & (s.PROG_LEN - 1);
            },
            FX_LABEL => {},
            FX_LOOP => {
                if (mc.program_loop == inst & 0xff) {
                    if (advance) mc.program_loop = 1;
                } else {
                    if (advance) mc.program_loop +%= 1;
                    var l: u32 = 0;
                    while (prog[tick] & 0xff00 != FX_LABEL and tick > 0) {
                        tick -= 1;
                        if (prog[tick] & 0x8000 == 0) l += 1;
                    }
                    tick -%= 1; // -1 wraps to the next increment's 0, as upstream's int
                    dont_reloop = l <= 1;
                }
            },
            else => cmd.run(e, i, mc.program_counter, inst, true),
        };
        if (inst == FX_NOP or inst & 0xff00 != FX_JUMP) {
            tick +%= 1;
            if (tick >= s.PROG_LEN) tick = 0;
        }
        if (inst & 0x8000 != 0 and inst != FX_NOP and !dont_reloop) continue;
        break;
    }
    if (advance) mc.program_tick = @intCast(tick);
}
