// --------------------------------------------------------------------------
// demo-audio.wasm: the Hippel (.hip) player's exports (libs/zig/players/
// hip_player.zig): an Amiga module's own 68000 replay on the SNDH player's
// Musashi, driving an emulated Paula (paula.zig) on the four sample channels.
// The scope view is the MOD's (mode 1), as the XM's is: the same four channels.
// --------------------------------------------------------------------------
const audio = @import("audio_hw");
const players = @import("players");
const m = @import("root");

pub var hip: players.HipPlayer = .{};

/// The staged file is a Hippel module (a bra jump table and a "TFMX" song).
/// Everything else stops first: the module moves into the 68000's RAM, where
/// an SNDH's image, a MOD's samples or a SAP's Atari live.
export fn audioLoadHip(len: u32) bool {
    // Abandoned, not stopped: the staged file may already cover the SNDH's code,
    // so its EXIT must not run.
    if (m.sndh.active) m.sndh.abandon();
    m.stopAll();
    if (m.current_mode == 1 or m.current_mode == 4) m.current_mode = 0;
    return hip.load(len);
}

/// Start song `tune` (from 1; 0 = the first).
export fn audioHipPlay(tune: u32) void {
    audio.machinePaulaClearScopes();
    hip.start(@intCast(@min(tune, 255)));
    m.current_mode = if (hip.active) 1 else 0;
}

export fn audioHipStop() void {
    hip.stop();
    if (m.current_mode == 1) m.current_mode = 0;
}

/// Playing (false once stopped, refused, or the replay ran away).
export fn audioHipActive() bool {
    return hip.active;
}
/// Voice `ch`'s DMA switch-on edges since the song started (paula.zig).
export fn audioHipStarts(ch: u32) u32 {
    return if (ch < 4) players.paula.starts[ch] else 0;
}
/// Pointers re-latched at a voice's wrap: the double-buffered AUDxLC at work.
export fn audioHipLatches() u32 {
    return players.paula.latches;
}
/// Voices refused for a pointer outside the 68000's RAM, and audio interrupts the
/// replay enabled (never raised here). Both 0 for a module that plays right.
export fn audioHipBadPointers() u32 {
    return players.paula.bad_ptr;
}
export fn audioHipIrqWanted() u32 {
    return players.paula.irq_wanted;
}
export fn audioHipPositionMs() u32 {
    return if (hip.active) hip.positionMs() else 0;
}
/// Test only: a known-wrong Paula (paula.zig mutant), 0 = none.
export fn audioHipMutant(n: u32) void {
    players.paula.mutant = n;
}
