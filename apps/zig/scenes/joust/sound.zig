// --------------------------------------------------------------------------
// JOUST's sound, as the GAME sees it: the 16 XBIOS Dosound scripts (pointer
// table $17E2, data $157D-$17E1) started by $0A94 with a priority ($0D8C,
// lower = more important), and the TOS Dosound interpreter that plays them
// on the 50 Hz Timer C tick. The game READS the chip back ($0AC8 resets the
// priority when mixer reg 7 has every channel off), so the interpreter runs
// here, inside the machine, register for register.
//
// What the player HEARS is the same scripts played by joust_sfx.sndh's own
// 68000 Dosound interpreter (apps/zig/assets/screens/joust/sfx.s): every
// script started here is logged, and the scene requests its subtune.
// --------------------------------------------------------------------------
const State = @import("state.zig");
const St = State.St;
const V = State.V;

pub const SFX_TABLE: i64 = 0x17E2;
pub const SILENCE: i64 = 0x157D; // script 0: the all-off script, also passed straight to Dosound
/// The start-up siren ($09AC, Giaccess, not a script), in the SFX log after
/// the 16 scripts: joust_sfx.sndh's subtune 17.
pub const SIREN: i64 = 16;

/// $0A94(n): start Dosound script n if n <= the current priority. Returns true
/// if it started. Registers are preserved (movem).
pub fn play_sfx(st: *St, n: i64) bool {
    if (n > st.g(V.sfx_prio)) return false;
    st.s(V.sfx_prio, n);
    const ptr = st.rl(SFX_TABLE + 4 * n);
    st.snd_ptr = ptr - State.BASE;
    st.snd_delay = 0;
    st.logSfx(n);
    return true;
}

/// Dosound($157D) called directly (the title, the name entry, ^C): script 0.
pub fn dosound_silence(st: *St) void {
    st.snd_ptr = SILENCE;
    st.snd_delay = 0;
    st.logSfx(0);
}

/// The TOS Dosound interpreter, one 50 Hz tick (every 4th Timer C tick).
pub fn dosound_tick(st: *St) void {
    if (st.snd_ptr == 0) return;
    if (st.snd_delay != 0) {
        st.snd_delay -= 1;
        if (st.snd_delay != 0) return;
    }
    var p = st.snd_ptr;
    var i: usize = 0;
    while (i < 512) : (i += 1) {
        const c = st.rb(p);
        if (c < 0x80) {
            st.psg[@intCast(c & 15)] = @intCast(st.rb(p + 1));
            p += 2;
        } else if (c == 0x80) {
            st.snd_temp = st.rb(p + 1);
            p += 2;
        } else if (c == 0x81) {
            const reg = st.rb(p + 1);
            const inc = st.rb(p + 2);
            const end = st.rb(p + 3);
            st.psg[@intCast(reg & 15)] = @intCast(st.snd_temp);
            st.snd_temp = (st.snd_temp + inc) & 0xFF;
            if (st.snd_temp != end) {
                st.snd_ptr = p;
                break;
            }
            p += 4;
        } else {
            const n = st.rb(p + 1);
            p += 2;
            st.snd_ptr = if (n == 0) 0 else p;
            if (n != 0) st.snd_delay = n;
            break;
        }
    }
}
