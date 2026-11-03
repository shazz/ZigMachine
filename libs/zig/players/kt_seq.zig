// --------------------------------------------------------------------------
// The .kt sequencer's tick (music.c mus_advance_tick): each track's sequence
// and pattern step, its note (trigger, legato, slide, release), its pattern
// command, then the row and song position, and every playing channel's
// per-tick work (kt_chan.zig). A song plays forever: at its end it goes back
// to its loop point (upstream returns 0 only with MUS_NO_REPEAT, export-only).
// --------------------------------------------------------------------------
const s = @import("kt_song.zig");
const eng = @import("kt_engine.zig");
const set = @import("kt_cyd_set.zig");
const chan = @import("kt_chan.zig");
const prog = @import("kt_prog.zig");

const Engine = eng.Engine;

pub fn advanceTick(e: *Engine) void {
    const sg = e.song;
    for (0..sg.num_channels) |i| track(e, i);
    e.song_counter +%= 1;
    const speed = if (e.song_position & 1 == 0) sg.song_speed else sg.song_speed2;
    if (e.song_counter >= speed) nextRow(e);
    for (0..e.synth.n) |i| if (e.chn[i].flags & eng.CHN_PLAYING != 0) chan.advance(e, i);
    if (sg.flags & s.SONG_ENABLE_MULTIPLEX != 0 and sg.multiplex_period > 0) multiplex(e);
}

fn track(e: *Engine, i: usize) void {
    const sg = e.song;
    const t = &e.track[i];
    if (e.song_counter == 0) {
        const seqs = sg.sequences[i];
        while (t.sequence_position < seqs.len and seqs[t.sequence_position].position <= e.song_position) {
            const se = seqs[t.sequence_position];
            t.pattern = &sg.patterns[se.pattern];
            t.pattern_step = e.song_position -% se.position;
            if (t.pattern_step >= sg.patterns[se.pattern].steps.len) t.pattern = null;
            t.note_offset = se.note_offset;
            t.sequence_position += 1;
        }
    }
    var delay: u8 = 0;
    if (t.pattern != null and t.step().command & 0x7FF0 == 0x0ed0) delay = @intCast(t.step().command & 0xf); // EXT_NOTE_DELAY
    if (e.song_counter == delay and t.pattern != null) note(e, i);
    if (t.pattern != null) prog.trackCommand(e, i, e.song_counter == delay);
}

fn note(e: *Engine, i: usize) void {
    const sg = e.song;
    const t = &e.track[i];
    const st = t.step();
    const n: u8 = if (st.note < 0xf0) st.note +% @as(u8, @bitCast(t.note_offset)) else st.note;
    const inst = st.instrument;
    var pinst: ?*const s.Instrument = e.chn[i].instrument;
    if (inst != s.NO_INSTRUMENT) {
        if (inst < sg.instruments.len) {
            pinst = &sg.instruments[inst];
            e.chn[i].instrument = pinst;
        } else pinst = null;
    }
    if (n == s.NOTE_RELEASE) {
        set.enableGate(e.cyd(i), e.synth.rate, false);
        return;
    }
    const ins = pinst orelse return;
    if (n == s.NOTE_NONE) return;
    t.slide_speed = 0;
    var speed: u16 = ins.slide_speed | 1;
    var ctrl = st.ctrl;
    if (st.command & 0xff00 == 0x0300) { // MUS_FX_SLIDE
        ctrl |= s.CTRL_SLIDE | s.CTRL_LEGATO;
        speed = st.command & 0xff;
    }
    const target: u16 = ((@as(u16, n) +% ins.base_note -% s.MIDDLE_C) << 8) +% @as(u16, @bitCast(@as(i16, ins.finetune)));
    const mc = &e.chn[i];
    if (ctrl & s.CTRL_SLIDE != 0) {
        if (ctrl & s.CTRL_LEGATO != 0) {
            mc.target_note = target;
        } else {
            const old = mc.note;
            _ = chan.trigger(e, i, ins, @as(u16, n) << 8, -1);
            mc.note = old;
        }
        t.slide_speed = speed;
    } else if (ctrl & s.CTRL_LEGATO != 0) {
        chan.setNote(e, i, target, true, if (ins.flags & s.INST_QUARTER_FREQ != 0) 4 else 1);
        mc.target_note = target;
    } else {
        const prev_track = t.volume;
        const prev_cyd = e.cyd(i).adsr.volume;
        _ = chan.trigger(e, i, ins, @as(u16, n) << 8, -1);
        mc.target_note = target;
        if (inst == s.NO_INSTRUMENT) {
            t.volume = prev_track;
            e.cyd(i).adsr.volume = prev_cyd;
        }
    }
    if (inst != s.NO_INSTRUMENT) {
        const relative = ins.flags & s.INST_RELATIVE_VOLUME != 0;
        t.volume = if (relative) s.MAX_VOLUME else ins.volume;
        e.cyd(i).adsr.volume = if (mc.flags & eng.CHN_DISABLED != 0) 0 else chan.scaleVolume(e, ins.volume, mc.volume);
    }
}

fn nextRow(e: *Engine) void {
    const sg = e.song;
    for (0..e.synth.n) |i| {
        const t = &e.track[i];
        const p = t.pattern orelse continue;
        const cmd = t.step().command;
        if (cmd & 0xff00 == 0x0d00) { // LOOP_PATTERN
            t.pattern_step = cmd & 0xff;
        } else if (cmd & 0xff00 == 0x2d00) { // SKIP_PATTERN
            const left: i32 = @as(i32, @intCast(p.steps.len)) - @as(i32, t.pattern_step) - 1;
            e.song_position +%= @intCast(@max(left, 0));
            t.pattern = null;
            t.pattern_step = 0;
        } else t.pattern_step +%= 1;
        if (t.pattern) |q| if (t.pattern_step >= q.steps.len) {
            t.pattern = null;
            t.pattern_step = 0;
        };
    }
    e.song_counter = 0;
    e.song_position +%= 1;
    if (e.song_position >= sg.song_length) {
        e.song_position = sg.loop_point;
        for (0..e.synth.n) |i| {
            e.track[i].pattern = null;
            e.track[i].pattern_step = 0;
            e.track[i].sequence_position = 0;
        }
    }
}

fn multiplex(e: *Engine) void {
    const sg = e.song;
    for (0..e.synth.n) |i| {
        if (e.multiplex_ctr / sg.multiplex_period == i) {
            chan.updateVolumes(e, i, e.track[i].volume);
        } else e.cyd(i).adsr.volume = 0;
    }
    e.multiplex_ctr +%= 1;
    if (e.multiplex_ctr >= @as(u32, sg.num_channels) * sg.multiplex_period) e.multiplex_ctr = 0;
}
