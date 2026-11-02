// --------------------------------------------------------------------------
// The trainer: the Empire cracktro's options (cracktro.zig) as the game reads
// them. Each one gates the one decrement it cancels, nothing else, so with
// every flag off the game is the original byte for byte:
//   lives     $3C266 die(): lives - 1           (rick_anim.zig)
//   bullets   $3BF5E shoot(): bullets - 1       (rick_act.zig)
//   dynamite  $3C07E dynamite(): dynamite - 1   (rick_act.zig)
// --------------------------------------------------------------------------

pub var infinite_lives: bool = false;
pub var infinite_bullets: bool = false;
pub var infinite_dynamite: bool = false;

/// The harness's door: bit 0 lives, bit 1 bullets, bit 2 dynamite.
pub fn set(bits: u32) void {
    infinite_lives = bits & 1 != 0;
    infinite_bullets = bits & 2 != 0;
    infinite_dynamite = bits & 4 != 0;
}

pub fn mask() u32 {
    return @as(u32, @intFromBool(infinite_lives)) |
        @as(u32, @intFromBool(infinite_bullets)) << 1 |
        @as(u32, @intFromBool(infinite_dynamite)) << 2;
}
