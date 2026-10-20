// --------------------------------------------------------------------------
// The music mirror: the seven replacement YM dumps the production's F1..F7
// select, stored by chonchon2_assets.py as per-frame DELTA streams.
//
// The host, not the cart, drives the YM chip now:
//   * tracks 1..3 are SNDHs (Jinks #1, lockbuster2_rollout #1 and #2), whose
//     register streams were matched against the production's dumps;
//   * tracks 4..7 have no SNDH match in docs/music and are requested as the
//     production's own unpacked YM dumps, docs/music/chonchon2_music-<n>.ymraw.
// In both cases the player owns the chip, so zg.ymWrite is not used (the host
// refuses those writes while an SNDH plays). This module advances the SAME
// embedded register stream in lockstep with the clock, and its `regs` is the
// mirror the three music meters read -- the Go's visual.YMRegisters().
//
// Format: u32 LE frame count, then per frame a u16 LE mask + the changed
// register values in ascending register order. Frame 0 writes all 14, so a
// track switch or the loop's wrap resets the chip's opening state exactly as
// the Go's Loop:true does.
// --------------------------------------------------------------------------
const assets = @import("assets.zig");

pub const Stream = struct {
    track: usize = 0,
    pos: usize = 0,
    next_frame: u32 = 0,
    applied: u32 = 0,
    frames: u32 = 0,
    regs: [14]u8 = [_]u8{0} ** 14,

    pub fn init(self: *Stream) void {
        self.select(0);
    }

    pub fn select(self: *Stream, track: usize) void {
        self.track = track;
        const m = assets.music[track];
        self.frames = @as(u32, m[0]) | (@as(u32, m[1]) << 8) |
            (@as(u32, m[2]) << 16) | (@as(u32, m[3]) << 24);
        self.pos = 4;
        self.next_frame = 0;
        self.applied = 0;
        self.regs = [_]u8{0} ** 14;
    }

    /// The Go reads one 960-frame block per 50 Hz Update, so one call of this
    /// per tick applies exactly one block/track frame.
    pub fn step(self: *Stream) void {
        const m = assets.music[self.track];
        const mask = @as(u16, m[self.pos]) | (@as(u16, m[self.pos + 1]) << 8);
        self.pos += 2;
        var r: usize = 0;
        while (r < 14) : (r += 1) {
            if (mask & (@as(u16, 1) << @intCast(r)) != 0) {
                self.regs[r] = m[self.pos];
                self.pos += 1;
            }
        }
        self.next_frame += 1;
        self.applied += 1;
        if (self.next_frame == self.frames) {
            self.next_frame = 0;
            self.pos = 4;
        }
    }
};
