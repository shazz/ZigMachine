// --------------------------------------------------------------------------
// The .kt player's core, chip-free: load a song into a span of memory, start
// it (cyd's FX buses set as mus_set_fx sets them, their delay lines taken from
// the same span) and render s16 stereo at `rate`. kt.zig puts this on the
// Paula channels; the native tests (kt_core_test.zig) pin it against
// upstream's own render (apps/ports/klystrack/kt_ref).
// --------------------------------------------------------------------------
const s = @import("kt_song.zig");
const rd = @import("kt_read.zig");
pub const read = rd; // the refusal codes, for the exports (apps/zig/demo_audio_kt.zig)
const ld = @import("kt_load.zig");
const fx = @import("kt_fx.zig");
const chorus = @import("kt_chorus.zig");
const Arena = @import("kt_arena.zig").Arena;
pub const Engine = @import("kt_engine.zig").Engine;

/// The klystrack cart's mixing rate (apps/ports/klystrack/patches/mused.c.sed).
pub const RATE: u32 = 22050;

pub const Core = struct {
    song: s.Song = undefined,
    engine: Engine = .{},
    arena: Arena = .{},
    loaded_mark: usize = 0, // the arena after the song: a restart frees the FX lines

    /// Parse `data` (only read); its tables go in `mem`.
    pub fn load(self: *Core, data: []const u8, mem: []u8) rd.Error!void {
        self.arena = Arena.init(mem);
        try ld.load(data, &self.song, &self.arena);
        for (self.song.fx) |f| for (f.taps) |t| {
            if (t.flags & 1 != 0 and t.gain > 0) return error.BadFx; // above 0 dB: not in kt_tables_gen
        };
        self.loaded_mark = self.arena.used;
    }

    pub fn start(self: *Core, rate: u32) Error!void {
        return self.startAt(rate, 0);
    }

    /// mus_set_fx + mus_set_song(position): the FX buses' lines from the arena; the song from
    /// sequence row `position` (past the end: its last row), as klystrack's play from cursor.
    pub fn startAt(self: *Core, rate: u32, position: u16) Error!void {
        self.arena.reset(self.loaded_mark);
        const sy = &self.engine.synth;
        sy.bus_used = 0;
        for (&sy.bus, self.song.fx, 0..) |*b, def, i| {
            b.* = .{ .flags = def.flags };
            if (def.flags & (s.FX_REVERB | s.FX_CHORUS | s.FX_CRUSH) != 0) sy.bus_used |= @as(u8, 1) << @intCast(i);
            if (def.flags & s.FX_REVERB != 0) {
                b.rvb.line = try self.arena.alloc(i32, fx.RVB_MS * rate / 1000);
                fx.setTaps(&b.rvb, &def, rate);
            }
            if (def.flags & s.FX_CHORUS != 0) {
                chorus.set(&b.chr, rate, def.chr_rate, def.chr_min_delay, def.chr_max_delay, def.chr_sep);
                b.chr.line = try self.arena.alloc(i32, 2 * b.chr.buf_size);
            }
            fx.setCrush(&b.crush, rate, def.downsample, def.bit_drop, @intFromBool(def.flags & s.FX_CRUSH_DITHER != 0), def.crush_gain);
        }
        self.engine.start(&self.song, rate);
        self.engine.song_position = @min(position, self.song.song_length -| 1);
    }

    pub fn render(self: *Core, out: []i16) void {
        self.engine.render(out);
    }
};

pub const Error = @import("kt_arena.zig").Error;
