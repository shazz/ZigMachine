// Aggregator for the open ZigOS audio players — the root of the `players` module
// (built only into demo-audio.wasm, which provides the audio chip ABI imports).
pub const ModPlayer = @import("mod.zig").ModPlayer;
pub const YmPlayer = @import("ym_player.zig").YmPlayer;
