// player_test.zig: the 6502 player driven from Zig against the C cart's own SID writes.
//   zig test --dep cpu6502 -Mroot=apps/zig/scenes/sidwizard_z/player_test.zig -Mcpu6502=libs/zig/players/cpu6502.zig
// old_cart_sid.bin is what apps/ports/sidwizard (Hermit's whole editor on its C64 emulation) wrote to the
// SID after F1 on FLASHBAK.SWM: [reg, value] pairs, 4000 of them.
const std = @import("std");
const swm = @import("swm.zig");
const mem = @import("c64mem.zig");
const player = @import("player.zig");

const tune = @embedFile("tunes/FLASHITBACK.SWM");
const golden = @embedFile("old_cart_sid.bin");
var song: swm.Song = undefined;

fn loadSong() !void {
    swm.reset(&song);
    try swm.load(&song, tune);
}

test "the Zig-driven player writes the SID exactly as the C cart's editor did (4000 writes)" {
    try loadSong();
    try player.start(&song, .{ .mode = .song, .subtune = 0, .selinst = 1 });
    var got: usize = 0;
    var frames: u32 = 0;
    while (got < golden.len / 2 and frames < 2000) : (frames += 1) {
        _ = player.tick() orelse return error.DeadPlayer;
        for (mem.writes()) |w| {
            if (got >= golden.len / 2) break;
            if (golden[2 * got] != w.reg or golden[2 * got + 1] != w.val) std.debug.print("write {d} (frame {d}): want {d}={d} got {d}={d}\n", .{ got, frames, golden[2 * got], golden[2 * got + 1], w.reg, w.val });
            try std.testing.expectEqual(golden[2 * got], w.reg);
            try std.testing.expectEqual(golden[2 * got + 1], w.val);
            got += 1;
        }
        mem.takeWrites();
    }
    try std.testing.expectEqual(golden.len / 2, got);
}

test "a tick of the player costs well under half a frame of 6502 cycles" {
    try loadSong();
    try player.start(&song, .{ .mode = .song, .subtune = 0, .selinst = 1 });
    for (0..100) |_| {
        const c = player.tick() orelse return error.DeadPlayer;
        try std.testing.expect(c < player.FRAME_CYCLES / 2);
    }
}

test "a tune whose counts overrun the image is refused, not played" {
    try loadSong();
    var big: [swm.music_len - 1]u8 = undefined;
    try std.testing.expectError(error.NoRoom, swm.toC64(&song, &big));
}

test "pause zeroes every channel's attack/decay and sustain/release" {
    try loadSong();
    try player.start(&song, .{ .mode = .song, .subtune = 0, .selinst = 1 });
    for (0..40) |_| _ = player.tick();
    mem.takeWrites();
    player.pause(1);
    var zeroed: u32 = 0;
    for (mem.writes()) |w| {
        const ad_sr = w.reg == 5 or w.reg == 6 or w.reg == 12 or w.reg == 13 or w.reg == 19 or w.reg == 20;
        if (ad_sr and w.val == 0) zeroed += 1;
    }
    try std.testing.expect(zeroed >= 6);
}

test "pattern play loops the cursor's pattern: the song position never advances" {
    try loadSong();
    try player.start(&song, .{ .mode = .pattern, .subtune = 0, .selinst = 1, .curptn = .{ 1, 2, 3 } });
    for (0..400) |_| _ = player.tick() orelse return error.DeadPlayer;
    const r = mem.ram();
    try std.testing.expectEqual(@as(u8, 0), r[0x27]); // SEQPOS stays at the start
    try std.testing.expectEqual(@as(u8, 1), r[0x3A]);
}
