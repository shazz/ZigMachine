// --------------------------------------------------------------------------
// The .kt loader (music.c mus_load_song_RW): the header, FX buses, default
// volumes and pans, instruments, sequences, packed patterns and wavetable
// entries, version by version. Versions 8..27 (packed patterns onwards) load;
// an older or newer file, more than 16 channels, a file cut short, more than
// 8 FX buses or a program over 32 steps are refused with a reason (kt_read.zig
// code). The arrays go in `arena`; the image itself is only read.
// --------------------------------------------------------------------------
const s = @import("kt_song.zig");
const rd = @import("kt_read.zig");
const parts = @import("kt_load_parts.zig");
const Arena = @import("kt_arena.zig").Arena;

pub fn load(data: []const u8, out: *s.Song, arena: *Arena) rd.Error!void {
    var r = rd.Reader{ .data = data };
    if (data.len < 9 or !std_eql(data[0..8], "cyd!song")) return error.NotKt;
    r.pos = 8;
    r.version = try r.u8_();
    if (r.version < s.VERSION_MIN or r.version > s.VERSION_MAX) return error.Version;
    out.* = .{};
    try header(&r, out);
    try effects(&r, out);
    if (r.has(13)) {
        for (0..out.num_channels) |c| out.default_volume[c] = try r.u8_();
        for (0..out.num_channels) |c| out.default_panning[c] = try r.i8_();
    }
    out.instruments = arena.alloc(s.Instrument, out.instruments.len) catch return error.TooLarge;
    for (out.instruments) |*i| i.* = try parts.instrument(&r);
    for (0..out.num_channels) |c| {
        const seq = arena.alloc(s.SeqEntry, out.sequences[c].len) catch return error.TooLarge;
        for (seq) |*e| e.* = .{ .position = try r.u16_(), .pattern = try r.u16_(), .note_offset = try r.i8_() };
        out.sequences[c] = seq;
    }
    out.patterns = arena.alloc(s.Pattern, out.patterns.len) catch return error.TooLarge;
    for (out.patterns) |*p| try pattern(&r, p, arena);
    out.waves = arena.alloc(s.WaveEntry, s.MAX_WAVES) catch return error.TooLarge;
    if (r.has(12)) {
        const n = try r.u8_();
        if (n > s.MAX_WAVES) return error.BadWave;
        for (out.waves[0..n]) |*e| try parts.wave(&r, e, arena);
    }
    try check(out);
}

fn std_eql(a: []const u8, b: []const u8) bool {
    for (a, b) |x, y| if (x != y) return false;
    return true;
}

/// The fixed header; the array lengths ride in the slices until they are allocated.
fn header(r: *rd.Reader, out: *s.Song) rd.Error!void {
    out.num_channels = try r.u8_();
    if (out.num_channels == 0) return error.BadSong;
    if (out.num_channels > s.MAX_CH) return error.TooManyChannels;
    _ = try r.u16_(); // time_signature
    if (r.has(17)) _ = try r.u16_(); // sequence_step
    out.instruments.len = try r.u8_();
    out.patterns.len = try r.u16_();
    for (0..out.num_channels) |c| out.sequences[c].len = try r.u16_();
    out.song_length = try r.u16_();
    out.loop_point = try r.u16_();
    out.master_volume = if (r.has(12)) try r.u8_() else s.MAX_VOLUME;
    out.song_speed = try r.u8_();
    out.song_speed2 = try r.u8_();
    out.song_rate = try r.u8_();
    out.flags = try r.u32_();
    out.multiplex_period = if (r.has(9)) try r.u8_() else 3;
    out.pitch_inaccuracy = if (r.has(16)) try r.u8_() else 0;
    const title_len: u8 = if (r.has(11)) try r.u8_() else 17;
    try r.skip(@min(title_len, 65));
    if (out.song_rate == 0) return error.BadSong; // cyd_set_callback divides by it
}

fn effects(r: *rd.Reader, out: *s.Song) rd.Error!void {
    const n: u8 = if (r.has(10)) try r.u8_() else if (out.flags & 1 != 0) 1 else 0;
    if (n > s.MAX_FX) return error.BadFx;
    if (r.has(10)) {
        for (out.fx[0..n]) |*f| try parts.fx(r, f);
        return;
    }
    for (out.fx[0..n]) |*f| { // versions 8 and 9: eight Sint32 gain/delay pairs
        f.* = .{ .flags = s.FX_REVERB | (if (out.flags & 2 != 0) s.FX_CRUSH else 0) };
        for (f.taps[0..8]) |*t| {
            const g: i32 = @bitCast(try r.u32_());
            const d: i32 = @bitCast(try r.u32_());
            t.* = .{ .gain = @truncate(g), .delay = @truncate(@as(u32, @bitCast(d))), .panning = 64, .flags = 1 };
        }
    }
}

/// One pattern: its length, colour, a nibble of flags a step, then each step's fields.
fn pattern(r: *rd.Reader, p: *s.Pattern, arena: *Arena) rd.Error!void {
    const n = try r.u16_();
    if (r.has(24)) _ = try r.u8_(); // colour
    p.steps = arena.alloc(s.Step, n) catch return error.TooLarge;
    const nibbles = try r.bytes(n / 2 + (n & 1));
    for (p.steps, 0..) |*st, i| {
        const byte = nibbles[i / 2];
        var b: u8 = if (i & 1 != 0 or i == n - 1) byte & 0xf else byte >> 4;
        st.note = if (b & 1 != 0) try r.u8_() else s.NOTE_NONE;
        st.instrument = if (b & 2 != 0) try r.u8_() else s.NO_INSTRUMENT;
        st.ctrl = 0;
        if (b & 4 != 0) {
            const c = try r.u8_();
            if (r.has(14)) b |= c & ~@as(u8, 7);
            st.ctrl = c & 7;
        }
        st.command = if (b & 8 != 0) try r.u16_() else 0;
        st.volume = if (b & 128 != 0) try r.u8_() else s.NO_VOLUME;
    }
}

/// What upstream would index out of its arrays with: refused, not played.
fn check(song: *const s.Song) rd.Error!void {
    for (0..song.num_channels) |c| for (song.sequences[c]) |e| {
        if (e.pattern >= song.patterns.len) return error.BadSong;
    };
    for (song.instruments) |*i| {
        if (i.fx_bus >= s.MAX_FX) return error.BadSong;
    }
}
