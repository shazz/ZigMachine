// --------------------------------------------------------------------------
// The FastTracker 2 .XM player: an OPEN ZigOS player, the 8-voice sibling of
// mod.zig. It sequences an XM image held in the shared song RAM and plays it
// through the SAME four Paula channels the MOD player uses, with its eight
// voices mixed two to a channel in software (xm_mix.zig, xm_chip.zig): so it
// runs on the sealed audio chip in the browser and on BARD (the FPGA sound
// CPU), where no chip has more than four channels.
//
// Supported: 1..8 channels; linear and Amiga frequency tables; 8- and 16-bit
// delta-coded samples with forward and ping-pong loops; the volume envelope
// with sustain, loop and fadeout; the volume column's set-volume; effects
// 0 1 2 3 4 5 6 A B C D E1 E2 E9 EA EB EC ED EE F and K (xm_effects.zig).
// Refused (xm_format.zig, with a reason): not an XM, a version before 1.02,
// more than 8 channels, a truncated file, a pattern or order out of range.
// Ignored: the other effects and volume-column commands, the panning
// envelope, instrument vibrato, global volume, sample panning, E4..E8 and
// E3/E6/E7/EF. Per-voice XM panning is not kept: each Paula channel carries
// its pair's voices at the pan of mod.zig's channel for that pair.
// --------------------------------------------------------------------------
const fmt = @import("xm_format.zig");
const pat = @import("xm_pattern.zig");
const inst = @import("xm_instr.zig");
const xv = @import("xm_voice.zig");
const rows = @import("xm_rows.zig");
const chip = @import("xm_chip.zig");
const audio = @import("audio_hw");

pub const XmPlayer = struct {
    data: []u8 = &.{}, // the song image (samples are decoded in it at load)
    hdr: fmt.Header = .{},
    tabs: inst.Tables = .{},
    /// Only the first num_patterns are read (orders are checked against them at load).
    pats: [fmt.MAX_PATTERNS]pat.PatInfo = undefined,
    active: bool = false,
    speed: u8 = 6, // ticks per row
    samples_per_tick: u32 = 882,
    tick_acc: u32 = undefined, // samples until the next tick (start() sets it)
    tick: u8 = 0,
    row: u16 = 0,
    order_pos: u8 = 0,
    break_row: i16 = -1, // pending pattern break target
    jump_pos: i16 = -1, // pending position jump target
    row_delay: u8 = 0, // EEx: rows still to repeat
    repeat: bool = false, // the row just counted down is not read again
    cache_pat: u16 = 0xFFFF, // the row cache (xm_rows.zig readCells)
    cache_row: u16 = undefined, // read only once cache_pat matches (xm_rows.zig readCells)
    cache_off: usize = undefined,
    chan: [fmt.MAX_CH]xv.Chan = undefined, // reset by start()

    /// Parse and check `data`, decoding its samples in place. On an error
    /// nothing plays; a loaded song consumes `data` (a reload must re-stage it).
    pub fn load(self: *XmPlayer, data: []u8) fmt.Error!void {
        self.* = .{};
        if (data.len > chip.BUF_OFFSET) return error.TooLarge;
        const hdr = try fmt.parse(data);
        const after = try pat.scan(data, &hdr, &self.pats);
        try inst.parseAll(data, &hdr, after, &self.tabs);
        self.hdr = hdr;
        self.data = data;
    }

    /// Start at `bpm` (ProTracker's 32..255 range), or at the song's own tempo otherwise.
    pub fn start(self: *XmPlayer, bpm: u32) void {
        self.active = true;
        self.speed = self.hdr.speed;
        const tempo: u16 = if (bpm >= 32 and bpm <= 255) @intCast(bpm) else self.hdr.bpm;
        self.setBpm(tempo);
        self.tick_acc = 0;
        self.tick = 0;
        self.row = 0;
        self.order_pos = 0;
        self.break_row = -1;
        self.jump_pos = -1;
        self.row_delay = 0;
        self.repeat = false;
        self.cache_pat = 0xFFFF;
        for (&self.chan) |*c| {
            c.* = .{};
            @memset(&c.memo, 0);
        }
        chip.setup();
    }

    /// Silence the channels, but only if XM was playing: another player's Paula
    /// channels (a MOD's, a raw stream's) are not XM's to switch off.
    pub fn stop(self: *XmPlayer) void {
        if (!self.active) return;
        self.active = false;
        for (0..audio.NUM_CHANNELS) |ch| audio.machinePaulaSetActive(@intCast(ch), 0);
    }

    /// A tick is 2.5 / BPM seconds: 110250 / BPM samples at 44100 Hz, integer only.
    pub fn setBpm(self: *XmPlayer, bpm: u16) void {
        self.samples_per_tick = 110250 / @as(u32, @max(bpm, 1));
    }

    pub fn trigger(self: *XmPlayer, ch: usize, note: u8) void {
        rows.trigger(self, ch, note);
    }

    /// Render `frames` stereo samples, the sequencer ticked at sample-accurate
    /// boundaries and each tick's voices mixed onto the Paula channels.
    pub fn renderStereo(self: *XmPlayer, frames: usize) void {
        const n = @min(frames, audio.MAX_FRAMES);
        audio.machineClear(@intCast(n));
        var off: usize = 0;
        while (off < n) {
            if (self.tick_acc == 0) {
                rows.tick(self);
                self.tick_acc = self.samples_per_tick;
            }
            const block: u32 = @min(@as(u32, @intCast(n - off)), self.tick_acc);
            chip.mixBlock(self, @intCast(off), block);
            self.tick_acc -= block;
            off += block;
        }
        audio.machineClamp(@intCast(n));
    }
};
