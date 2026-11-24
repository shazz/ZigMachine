// --------------------------------------------------------------------------
// The SID on the sound side: the 6502 player's SID writes go on the BARD queue (zg.bard, system table
// 1.12, docs/project/DECISIONS.md 2026-11-07), as apps/ports/sidwizard's C64 emulation does: raw cRSID plays each write at its
// sample (BARD on the board, the AudioWorklet on the page), the cart never waits. Same reset model
// (an 8580 at the song's start), same lead (~139 ms).
//
// The stamp of a write is its 6502 cycle on the cart's 44.1 kHz clock, from the song's start:
// t = base + cycle x 44100 / 985248 (a PAL C64's clock; a frame is 19656 cycles = 879.8 samples).
// Integer only. Ticks are paced by bard.due(): the song keeps the sound side's time at any frame rate.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const mem = @import("c64mem.zig");

const bard = zg.bard;
pub const LEAD: u32 = 6144;
pub const MAX_TICKS: u32 = 8; // ticks a frame may run to catch up
const PAL_HZ: u64 = 985248;
const RATE: u64 = 44100;
const TRIES: u32 = 120;
/// A tick makes < 40 writes in practice (the C editor's worst: ~25); the queue must hold this many.
pub const TICK_ROOM: u32 = 64;

pub const Out = struct {
    open: bool = false,
    tries: u32 = 0,
    base: u32 = 0, // the sample the song's cycle 0 plays at
    reset_sent: bool = false,
    dropped: u32 = 0,

    /// The queue (the players may come up after the cart's boot: ask for a while).
    pub fn ensureOpen(self: *Out) bool {
        if (!self.open and self.tries < TRIES) {
            self.tries += 1;
            self.open = bard.open(LEAD);
        }
        return self.open;
    }

    /// A song starts now: a fresh SID, the song's cycle 0 a few ms after what the sound side has played.
    pub fn begin(self: *Out) void {
        self.reset_sent = false;
        self.base = if (bard.anchored()) bard.position() +% 441 else 0;
    }

    /// The sample of 6502 cycle `c` of this song.
    pub fn stamp(self: *const Out, c: u64) u32 {
        return self.base +% @as(u32, @truncate(c * RATE / PAL_HZ));
    }

    /// Is it time to run the player's frame starting at cycle `c`? (The sound side is within a lead of it.)
    pub fn due(self: *const Out, c: u64) bool {
        return self.open and bard.due(self.stamp(c)) and bard.room() >= TICK_ROOM;
    }

    /// The writes the player made, stamped. The song's first call opens with a SID reset.
    pub fn send(self: *Out, writes: []const mem.SidWrite) void {
        if (!self.open) return;
        if (!self.reset_sent) {
            self.reset_sent = true;
            const t0 = if (writes.len > 0) self.stamp(writes[0].cycle) else self.base;
            _ = bard.sidReset(t0, .mos8580);
        }
        for (writes) |w| if (!bard.sidWrite(self.stamp(w.cycle), w.reg, w.val)) {
            self.dropped +%= 1;
        };
        while (bard.pollEvent()) |_| {} // resets, re-anchors, drops: read and let go
    }

    /// The song ends with the program: the sound side's SID stops.
    pub fn close(self: *Out) void {
        if (self.open) bard.close();
        self.open = false;
    }
};
