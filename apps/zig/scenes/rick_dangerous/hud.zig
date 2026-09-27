// --------------------------------------------------------------------------
// The loop's short presentation calls (the model's pkg_d.py): the HUD (calls
// 0-3), clear every slot (calls 4, 15), the flip $38DB8 (call 13) and the VBL
// wait $38D92 (calls 14, 18).
// --------------------------------------------------------------------------
const m = @import("ram.zig");
const F = @import("fields.zig");
const core = @import("core.zig");
const game = @import("game.zig");

/// Call 0, $3AE3E: if dirty, the 6 score digits $3ADB2 at offset $10.
pub fn score() void {
    if (m.rb(F.DIRTY_SCORE) == 0) return;
    core.printText(0x10, 0x3ADB2);
    m.wb(F.DIRTY_SCORE, 0);
}

/// $3AF7E: 6 blanks ($5E), then `count` icon tiles from the left, then print.
fn icons(text: i64, off: i64, count: i64, tile: i64) void {
    var k: i64 = 0;
    while (k < 6) : (k += 1) m.wb(text + k, 0x5E);
    k = 0;
    while (k < count) : (k += 1) m.wb(text + k, tile);
    core.printText(off, text);
}

/// Call 1, $3AEE2.
pub fn bullets() void {
    if (m.rb(F.DIRTY_BULLETS) == 0) return;
    icons(0x3ADBA, 0x31, m.rb(F.BULLETS), 0x0A);
    m.wb(F.DIRTY_BULLETS, 0);
}

/// Call 2, $3AF16.
pub fn dynamite() void {
    if (m.rb(F.DIRTY_DYNAMITE) == 0) return;
    icons(0x3ADC2, 0x51, m.rb(F.DYNAMITE), 0x0B);
    m.wb(F.DIRTY_DYNAMITE, 0);
}

/// Call 3, $3AF4A.
pub fn lives() void {
    if (m.rb(F.DIRTY_LIVES) == 0) return;
    icons(0x3ADCA, 0x78, m.rb(F.LIVES), 0x0C);
    m.wb(F.DIRTY_LIVES, 0);
}

pub fn all() void {
    score();
    bullets();
    dynamite();
    lives();
}

/// Calls 4 / 15, $3A698: EVERY slot: type = 0, both dirty-rect words = 0.
pub fn clearSlots() void {
    var a = F.ENT;
    while (m.rw(a) != 0xFFFF) : (a += F.ENT_SZ) {
        m.ww(a, 0);
        m.ww(a + 0x16, 0);
        m.ww(a + 0x1C, 0);
    }
}

/// $38DB8 must wait for a VBL, and the host's time is up.
pub fn flipBlocked() bool {
    return m.s8(m.rb(F.VBL_COUNT)) < 1 and game.ahead();
}

/// Call 13, $38DB8: wait until at least one VBL since the last wait, then
/// toggle $70000 / $78000.
pub fn flip() void {
    while (m.s8(m.rb(F.VBL_COUNT)) < 1) game.vblIrq();
    m.wb(0x38D6E, m.rb(0x38D6E) ^ 0x80);
    game.vbase = (m.rb(0x38D6D) << 16) | (m.rb(0x38D6E) << 8);
}

/// $38D92 waits for at least one VBL: the host's time is up.
pub fn waitBlocked() bool {
    return game.ahead();
}

/// Calls 14 / 18, $38D92: wait for the next VBL (the counter >= 1 AND
/// changed), then clear it.
pub fn wait() void {
    const d0 = m.rb(F.VBL_COUNT);
    while (m.s8(m.rb(F.VBL_COUNT)) < 1 or m.rb(F.VBL_COUNT) == d0) game.vblIrq();
    m.wb(F.VBL_COUNT, 0);
}
