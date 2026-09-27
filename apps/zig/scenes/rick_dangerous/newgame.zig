// --------------------------------------------------------------------------
// The game's start-up $3D6AC..$3D6E6 and a new game $3ADDA / $39062.
// --------------------------------------------------------------------------
const m = @import("ram.zig");
const F = @import("fields.zig");
const clock = @import("clock.zig");
const game = @import("game.zig");
const world = @import("world.zig");

/// $3D6AC..$3D6E6 (no TOS here: Super, the vectors, the IKBD commands and
/// Setscreen are the machine's): clear $63800-$7FFFF, the level-select flags
/// ($39344 = 0, $39346 = $FF, $39344 = 3), the RNG seed $38FF6, the live
/// palette to the colour registers, $3D8E8 (the grey toggle) = 0.
pub fn startUp() void {
    m.zero(0x63800, 0x72 * 0x400);
    m.ww(F.MAX_LEVEL, 0);
    m.ww(F.LEVEL_SELECT_ON, 0xFF);
    m.ww(F.MAX_LEVEL, 3);
    world.rngSeed();
    for (&game.pal, 0..) |*p, i| p.* = m.rw(F.LIVE_PAL + 2 * @as(i64, @intCast(i)));
    m.ww(0x3D8E8, 0);
}

/// $3ADDA: score 0, 6 bullets, 6 dynamite, 6 lives, the HUD digits 0, all dirty.
pub fn newGame() void {
    for ([_]i64{ 0x3ADA8, 0x3ADA9, 0x3ADAA }) |a| m.wb(a, 0);
    m.wb(F.BULLETS, 6);
    m.wb(F.DYNAMITE, 6);
    m.wb(F.LIVES, 6);
    m.wl(0x3ADB2, 0);
    m.ww(0x3ADB6, 0);
    for ([_]i64{ F.DIRTY_BULLETS, F.DIRTY_DYNAMITE, F.DIRTY_LIVES, F.DIRTY_SCORE }) |a| m.wb(a, 0xFF);
}

/// $39062: bit7 (used) off in all $20B spawn records.
pub fn reviveSpawns() void {
    var a: i64 = 0x37C66;
    for (0..0x20B) |_| {
        m.wb(a + 2, m.rb(a + 2) & 0x7F);
        a += 6;
    }
    clock.work(0x20B * 40);
}
