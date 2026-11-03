// --------------------------------------------------------------------------
// The .kt engine's state: music.c's MusEngine (channels, track status, song
// position) beside cyd's synth (kt_synth.zig), and the sample clock that runs
// the sequencer at the song's rate (cyd_set_callback). `render` is
// cyd_output_buffer_stereo with NOSDL_MIXER: s16 stereo, bit-exact against
// upstream (kt_ref). Pure: no chip; kt.zig puts its output on the Paula.
// --------------------------------------------------------------------------
const s = @import("kt_song.zig");
const c = @import("kt_cyd.zig");
const syn = @import("kt_synth.zig");
const set = @import("kt_cyd_set.zig");
const seq = @import("kt_seq.zig");

pub const CHN_PLAYING: u32 = 1;
pub const CHN_PROGRAM_RUNNING: u32 = 2;
pub const CHN_DISABLED: u32 = 4;

pub const MusChannel = struct {
    instrument: ?*const s.Instrument = null,
    note: u16 = 0,
    volume: u8 = 0,
    arpeggio_note: u8 = 0,
    target_note: u16 = 0,
    last_note: u16 = 0,
    fixed_note: u16 = 0,
    flags: u32 = 0,
    current_tick: u32 = 0,
    program_counter: u8 = 0,
    program_tick: u8 = 0,
    program_loop: u8 = 0,
    prog_period: u8 = 0,
    buzz_offset: i16 = 0,
};

pub const Track = struct {
    pattern: ?*const s.Pattern = null,
    last_ctrl: u8 = 0,
    pw: u16 = 0,
    pattern_step: u16 = 0,
    sequence_position: u16 = 0,
    slide_speed: u16 = 0,
    vibrato_position: u16 = 0,
    pwm_position: u16 = 0,
    note_offset: i8 = 0,
    filter_cutoff: u16 = 0,
    filter_resonance: u8 = 0,
    extarp1: u8 = 0,
    extarp2: u8 = 0,
    volume: u8 = 0,
    vib_delay: u8 = 0,

    pub fn step(t: *const Track) *const s.Step {
        return &t.pattern.?.steps[t.pattern_step];
    }
};

pub const Engine = struct {
    song: *s.Song = undefined,
    synth: syn.Synth = .{},
    chn: [s.MAX_CH]MusChannel = undefined,
    track: [s.MAX_CH]Track = undefined,
    song_counter: u8 = 0,
    song_position: u16 = 0,
    volume: u8 = s.MAX_VOLUME,
    play_volume: u8 = s.MAX_VOLUME,
    multiplex_ctr: u8 = 0,
    pitch_mask: u32 = 0xffffffff,
    callback_period: u32 = 1,
    callback_counter: u32 = 0,
    /// Called after each sequencer tick (tools/kt_render.zig --trace): never set on the machine.
    on_tick: ?*const fn (*const Engine) void = null,

    pub fn cyd(e: *Engine, i: usize) *c.Channel {
        return &e.synth.chn[i];
    }

    /// cyd_set_callback_rate: the sequencer runs every rate / song_rate samples.
    pub fn setTickRate(e: *Engine, song_rate: u8) void {
        e.callback_period = e.synth.rate / @max(song_rate, 1);
        e.callback_counter %= e.callback_period;
    }

    /// mus_init_engine + cyd_reset + mus_set_song(song, 0), as kt_ref (and the
    /// klystrack cart) start a song; the FX buses are kt.zig's (they need memory).
    pub fn start(e: *Engine, sg: *s.Song, rate: u32) void {
        e.song = sg;
        e.synth.rate = rate;
        e.synth.n = sg.num_channels;
        e.volume = sg.master_volume;
        e.play_volume = s.MAX_VOLUME;
        e.song_counter = 0;
        e.song_position = 0;
        e.multiplex_ctr = 0;
        e.pitch_mask = @as(u32, 0xffffffff) << @intCast(@min(sg.pitch_inaccuracy, 31));
        for (0..s.MAX_CH) |i| {
            set.initChannel(&e.synth.chn[i], rate, @intCast(i));
            e.chn[i] = .{ .volume = sg.default_volume[i] };
            e.track[i] = .{};
            set.setPanning(&e.synth.chn[i], @bitCast(sg.default_panning[i] +% @as(i8, @bitCast(c.PAN_CENTER))));
        }
        e.callback_counter = 0;
        e.setTickRate(sg.song_rate);
    }

    /// `out.len / 2` stereo samples, s16 interleaved, as cyd_output_buffer_stereo.
    pub fn render(e: *Engine, out: []i16) void {
        var i: usize = 0;
        while (i + 1 < out.len) : (i += 2) {
            if (e.callback_counter == 0) {
                e.callback_counter = e.callback_period - 1;
                seq.advanceTick(e);
                if (e.on_tick) |f| f(e);
            } else e.callback_counter -= 1;
            var l: i32 = 0;
            var r: i32 = 0;
            syn.output(&e.synth, &l, &r);
            out[i] = clamp16(@divTrunc(l, 4));
            out[i + 1] = clamp16(@divTrunc(r, 4));
            syn.cycle(&e.synth);
        }
    }
};

fn clamp16(v: i32) i16 {
    return @intCast(@min(32767, @max(-32768, v)));
}
