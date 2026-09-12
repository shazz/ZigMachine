// Aggregator for the open ZigOS audio players — the root of the `players` module
// (built only into demo-audio.wasm, which provides the audio chip ABI imports).
pub const ModPlayer = @import("mod.zig").ModPlayer;
pub const YmPlayer = @import("ym_player.zig").YmPlayer;
pub const SndhPlayer = @import("sndh_player.zig").SndhPlayer;

/// Diagnosis for a tune that will not run: the 68000 PC where a replay call
/// gave up (0 if none has), and the last trap the little TOS could not answer.
pub fn sndhStuckPc() u32 {
    return @import("sndh_player.zig").stuck_pc;
}
pub fn sndhTimerRate(t: u32) u32 {
    return @import("sndh_player.zig").timerRate(t);
}
pub fn sndhUnhandledTrap() u32 {
    return @import("sndh_player.zig").unhandled_trap;
}
