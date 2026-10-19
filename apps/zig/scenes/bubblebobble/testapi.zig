// --------------------------------------------------------------------------
// The headless harness's door into the game (apps/bubblebobble_headless.mjs):
// drive the SAME sim.Game the scene plays, one 60 Hz tick at a time with a
// scripted key mask, and read the whole world back for assertions. Pulled in
// only when this scene IS the cart (bubblebobble.zig checks cart.Cart), so
// these exports never leak into another cart.
// --------------------------------------------------------------------------
const sim = @import("sim.zig");
const art = @import("art.zig");
const audio = @import("audio.zig");
const scene = @import("../bubblebobble.zig");

/// mask: bit0 left, bit1 right, bit2 jump, bit3 fire (held, not an edge).
fn decode(mask: u32) sim.Input {
    var in = sim.Input{};
    if (mask & 1 != 0) in.move -= 1;
    if (mask & 2 != 0) in.move += 1;
    in.jump = mask & 4 != 0;
    in.fire = mask & 8 != 0;
    return in;
}

export fn bbTestStart(seed: u32) void {
    scene.game.reset(@as(u64, seed) | 1, 1);
    scene.game.paused = false;
}
export fn bbTestLoadLevel(n: u32) void {
    scene.game.loadLevel(@intCast(n));
    scene.game.state = .playing;
}
/// One 60 Hz tick. Returns the game state as a number.
export fn bbTestTick(mask: u32) u32 {
    scene.game.step(decode(mask));
    return stateCode();
}
export fn bbTestState() u32 {
    return stateCode();
}
fn stateCode() u32 {
    return switch (scene.game.state) {
        .ready => 0,
        .playing => 1,
        .clearing => 2,
        .game_over => 3,
        .won => 4,
    };
}
export fn bbTestScore() i32 {
    return scene.game.score;
}
export fn bbTestLevel() u32 {
    return scene.game.level.number;
}
export fn bbTestLevelIndex() u32 {
    return @intCast(scene.game.level_index);
}
export fn bbTestLives() u32 {
    return @intCast(@max(0, scene.game.players[0].lives));
}
export fn bbTestEnemies() u32 {
    return @intCast(scene.game.remainingEnemies());
}
export fn bbTestEnemyCount() u32 {
    return scene.game.enemy_count;
}
export fn bbTestTrapped() u32 {
    var n: u32 = 0;
    for (scene.game.enemies[0..scene.game.enemy_count]) |e| {
        if (e.state == .trapped) n += 1;
    }
    return n;
}
export fn bbTestDefeated() u32 {
    var n: u32 = 0;
    for (scene.game.enemies[0..scene.game.enemy_count]) |e| {
        if (e.state == .defeated) n += 1;
    }
    return n;
}
export fn bbTestBubbles() u32 {
    return scene.game.bubble_count;
}
export fn bbTestItems() u32 {
    return scene.game.item_count;
}
export fn bbTestEffects() u32 {
    return scene.game.effect_count;
}
export fn bbTestParticles() u32 {
    return scene.game.particle_count;
}
export fn bbTestHurry() u32 {
    return if (scene.game.hurry) 1 else 0;
}
export fn bbTestTickCount() i32 {
    return scene.game.tick;
}
export fn bbTestPX() i32 {
    return scene.game.players[0].body.x;
}
export fn bbTestPY() i32 {
    return scene.game.players[0].body.y;
}
export fn bbTestPVY() i32 {
    return scene.game.players[0].body.vy;
}
export fn bbTestGround() u32 {
    return if (scene.game.players[0].body.ground) 1 else 0;
}
export fn bbTestDir() i32 {
    return scene.game.players[0].dir;
}
export fn bbTestWalked() i32 {
    return scene.game.counters.walked;
}
export fn bbTestBlown() i32 {
    return scene.game.counters.blown;
}
export fn bbTestPopped() i32 {
    return scene.game.counters.popped;
}
/// The nearest bubble to the player, or -1. The harness teleports onto it.
export fn bbTestNearestBubble() i32 {
    var best: i32 = -1;
    var bestd: i64 = std.math.maxInt(i64);
    const p = scene.game.players[0].body;
    for (scene.game.bubbles[0..scene.game.bubble_count], 0..) |b, i| {
        const d = @as(i64, @intCast(@abs(b.body.x - p.x))) + @as(i64, @intCast(@abs(b.body.y - p.y)));
        if (d < bestd) {
            bestd = d;
            best = @intCast(i);
        }
    }
    return best;
}
export fn bbTestBubbleX(i: u32) i32 {
    if (i >= scene.game.bubble_count) return 0;
    return scene.game.bubbles[i].body.x;
}
export fn bbTestBubbleY(i: u32) i32 {
    if (i >= scene.game.bubble_count) return 0;
    return scene.game.bubbles[i].body.y;
}
/// Put the player on the bubble and pop it, the way touching one does.
export fn bbTestPopAt(i: u32) void {
    if (i >= scene.game.bubble_count) return;
    const b = scene.game.bubbles[i];
    const p = &scene.game.players[0];
    p.body.x = b.body.x;
    p.body.y = b.body.y;
    p.dead = 0;
    scene.game.bubblePopForTest(@intCast(i));
}
/// The first trapped enemy's bubble index, or -1.
export fn bbTestTrappedBubble() i32 {
    for (scene.game.bubbles[0..scene.game.bubble_count], 0..) |b, i| {
        if (b.enemy_id != 0) return @intCast(i);
    }
    return -1;
}
/// Teleport the player under an enemy so a blown bubble traps it.
export fn bbTestAimAtEnemy(i: u32) void {
    if (i >= scene.game.enemy_count) return;
    const e = scene.game.enemies[i];
    const p = &scene.game.players[0];
    p.body.x = e.body.x - (20 << 16);
    p.body.y = e.body.y;
    p.dir = 1;
}
export fn bbTestEnemyX(i: u32) i32 {
    if (i >= scene.game.enemy_count) return 0;
    return scene.game.enemies[i].body.x;
}
export fn bbTestEnemyY(i: u32) i32 {
    if (i >= scene.game.enemy_count) return 0;
    return scene.game.enemies[i].body.y;
}
export fn bbTestEnemyKind(i: u32) u32 {
    if (i >= scene.game.enemy_count) return 0;
    return @intFromEnum(scene.game.enemies[i].kind);
}
export fn bbTestItemX(i: u32) i32 {
    if (i >= scene.game.item_count) return 0;
    return scene.game.items[i].body.x;
}
export fn bbTestItemY(i: u32) i32 {
    if (i >= scene.game.item_count) return 0;
    return scene.game.items[i].body.y;
}
export fn bbTestItemIsPower(i: u32) u32 {
    if (i >= scene.game.item_count) return 0;
    return if (scene.game.items[i].power == .none) 0 else 1;
}
/// Stand the dragon on an item, the way walking onto it does.
export fn bbTestWalkToItem(i: u32) void {
    if (i >= scene.game.item_count) return;
    const it = scene.game.items[i];
    const p = &scene.game.players[0];
    p.body.x = it.body.x;
    p.body.y = it.body.y;
    p.body.vy = 0;
    p.body.ground = true;
    p.dead = 0;
}
export fn bbTestPowerCount() u32 {
    var n: u32 = 0;
    for (scene.game.items[0..scene.game.item_count]) |it| {
        if (it.power != .none) n += 1;
    }
    return n;
}
export fn bbTestPending() u32 {
    return scene.game.counters.pending_count;
}
/// Grant a power-up the way collecting one does.
export fn bbTestGrantPower(p: u32) void {
    _ = scene.game.testApplyPower(@enumFromInt(p));
}
export fn bbTestSetLevelTicks(t: i32) void {
    scene.game.level_ticks = t;
}
// --- the chip ---------------------------------------------------------------
export fn bbTestMusic(track: u32) void {
    if (track > 4) return;
    audio.play(@enumFromInt(track));
}
export fn bbTestYmReg(i: u32) u32 {
    return audio.regAt(i);
}
export fn bbTestYmRefused() u32 {
    return audio.refused;
}
export fn bbTestMusicApplied() u32 {
    return audio.appliedFrames();
}
export fn bbTestSfx(id: u32) void {
    audio.sfx(@intCast(id));
}
export fn bbTestSfxFed() u32 {
    return audio.fed;
}
export fn bbTestMuted() u32 {
    return if (audio.muted) 1 else 0;
}

// --- the pages --------------------------------------------------------------
export fn bbTestPage(n: u32) void {
    scene.setPageForTest(n);
}
export fn bbTestSel(n: u32) void {
    scene.selectForTest(n);
}
export fn bbTestPalettePtr() [*]u32 {
    return art.palettePtr();
}

export fn bbTestRamPtr() [*]u8 {    return @ptrCast(&scene.game);
}
export fn bbTestRamLen() u32 {
    return @sizeOf(sim.Game);
}
/// The overscan plane's char buffer (400 x 280 indexed pixels).
export fn bbTestScreenPtr() [*]u8 {
    return art.screenPtr();
}
export fn bbTestScreenStride() u32 {
    return art.screenStride();
}
/// A CRC of the live world, so two runs of the same script can be compared.
export fn bbTestCRC() u32 {
    const words: [*]const u8 = @ptrCast(&scene.game);
    var h: u32 = 2166136261;
    var i: usize = 0;
    while (i < @sizeOf(sim.Game)) : (i += 1) {
        h = (h ^ words[i]) *% 16777619;
    }
    return h;
}

const std = @import("std");
