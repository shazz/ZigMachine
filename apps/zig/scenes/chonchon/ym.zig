// --------------------------------------------------------------------------
// The music: the production's own assets/original/music.ym (an LHa archive
// holding ROLLOUT2.YM, a YM6 chip dump by Jochen Hippel, 10650 frames at 50 Hz),
// replayed through the MACHINE's YM2149 -- not samples, not a host-side player.
//
// chon_assets.py stores it as a per-frame DELTA stream:
//
//   u32  frame count
//   per frame: u16 little-endian mask of the registers 0..13 that changed,
//              then their new values in ascending register order.
//
// Frame 0 is a full 14-register write, so wrapping the song resets the chip to
// its opening state exactly as the Go's Loop:true does. Only CHANGED registers
// are written, so register 13 (the envelope shape) is not silently retriggered
// every frame.
//
// The cart pushes each frame's writes through zg.ymWrite, one frame per 50 Hz
// tick -- the audio thread applies them to the chip. `regs` is the cart's OWN
// cumulative mirror (the Go visualises YMRegisters() of the stream it reads),
// and the three music meters read regs 8/9/10 from it. The Go reads one 20 ms
// block per Update, so Go frame n uses YM frame n-1 (advanceTo(tick-1)).
// --------------------------------------------------------------------------
const zg = @import("zigos");
const assets = @import("assets.zig");

/// Writes the sfx queue refused (>32 in a host frame, or reg > 13). The gate
/// asserts this stays 0.
pub var refused: u32 = 0;

pub const Stream = struct {
    pos: usize = 0, // byte offset of the NEXT frame in `music`
    next_frame: u32 = 0, // frame index `pos` points at (wraps at `frames`)
    applied: u32 = 0, // total frames applied so far (never decreases)
    frames: u32 = 0,
    regs: [14]u8 = [_]u8{0} ** 14,

    pub fn init(self: *Stream) void {
        const m = assets.music;
        self.frames = @as(u32, m[0]) | (@as(u32, m[1]) << 8) |
            (@as(u32, m[2]) << 16) | (@as(u32, m[3]) << 24);
        self.pos = 4;
        self.next_frame = 0;
        self.applied = 0;
        self.regs = [_]u8{0} ** 14;
    }

    /// Apply every frame up to and including `target` (0-based).
    pub fn advanceTo(self: *Stream, target: u32) void {
        while (self.applied <= target) {
            self.applyOne();
            self.applied += 1;
        }
    }

    fn applyOne(self: *Stream) void {
        const m = assets.music;
        const mask = @as(u16, m[self.pos]) | (@as(u16, m[self.pos + 1]) << 8);
        self.pos += 2;
        var r: u8 = 0;
        while (r < 14) : (r += 1) {
            if (mask & (@as(u16, 1) << @intCast(r)) != 0) {
                const v = m[self.pos];
                self.pos += 1;
                self.regs[r] = v;
                if (!zg.ymWrite(r, v)) refused +%= 1;
            }
        }
        self.next_frame += 1;
        if (self.next_frame == self.frames) {
            self.next_frame = 0;
            self.pos = 4;
        }
    }
};
