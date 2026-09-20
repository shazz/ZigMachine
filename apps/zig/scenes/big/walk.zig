// The B.I.G. Demo's COLOUR WALK — the same construction on two screens.
//
// Key 2's plane ($18F9A) and key 1's pen ramp ($148A0) both make a new colour
// the same way: roll two bits, and step ONE CHANNEL of an existing colour by one
// level, in a direction that flips when that channel reaches 0 or 7. The fourth
// outcome does nothing — key 2 re-rolls, key 1 leaves the entry alone.
//
//   roll 0   RED    step +-$100, bounds $000..$700, direction at $19236 / $149E8
//   roll 1   GREEN  step +-$010, bounds $00..$70,   direction at $1923A
//   roll 2   BLUE   step +-$001, bounds $0..$7,     direction at $19238
//   roll 3   nothing
//
// THREE INDEPENDENT DIRECTIONS, one per channel, is the part that matters. A
// port with only the blue stepper — which is what shipped, because only that
// case had been read — emits values that differ from their neighbour in one
// nibble, and on key 2 the diagonal rotation then carries that single walking
// value across all 3,400 words: the whole plane converges. Measured at 203
// distinct colours falling to EIGHT by frame 4,300. With all three the walk is
// three-dimensional and the field stays as rich as the real screen's.
//
// That is why this lives in its own file rather than twice in two scenes: it is
// one mechanism, it was wrong in one way, and it should only ever be fixed once.

/// The three bounce directions, one per channel. They persist across calls the
/// way $19236 / $1923A / $19238 persist in the demo — a channel that has hit 7
/// keeps coming down until it hits 0.
pub const Dirs = struct {
    r: i16 = 0x100,
    g: i16 = 0x010,
    b: i16 = 0x001,
};

/// One step of `w`, chosen by the low two bits of `roll`. Returns `w` unchanged
/// on roll 3, which is the caller's cue to re-roll if it wants to (key 2 does;
/// key 1 does not).
pub fn step(w: u16, roll: u32, d: *Dirs) u16 {
    const ch: u2 = @truncate(roll);
    const mask: u16 = switch (ch) {
        0 => 0x700,
        1 => 0x070,
        2 => 0x007,
        3 => return w,
    };
    const one: i16 = switch (ch) {
        0 => 0x100,
        1 => 0x010,
        2 => 0x001,
        3 => unreachable,
    };
    const dir: *i16 = switch (ch) {
        0 => &d.r,
        1 => &d.g,
        2 => &d.b,
        3 => unreachable,
    };
    const level = w & mask;
    if (level == 0) dir.* = one else if (level == mask) dir.* = -one;
    return @intCast(@as(i32, w) + dir.*);
}
