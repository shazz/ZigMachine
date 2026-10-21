// --------------------------------------------------------------------------
// demo-audio.wasm: the SAP player's exports (an Atari 8-bit tune's 6502 code
// on the POKEY, libs/zig/players/sap_player.zig). Split from
// demo_audio_main.zig, whose players and mode they share. Mode 5 while it plays.
// --------------------------------------------------------------------------
const audio = @import("audio_hw");
const players = @import("players");
const m = @import("root");

pub var sap: players.SapPlayer = .{};

/// The staged file is a SAP of a kind this player runs (TYPE B or C, mono).
/// False otherwise, with the reason in audioSapStatus.
export fn audioLoadSap(len: u32) bool {
    // The SAP was just staged over an SNDH's image (song RAM is the 68000's RAM). Left
    // active, the SNDH would go on rendering first and audioSapPlay's stopAll would run its
    // EXIT on the SAP's bytes. Abandon it unrun, as the YM, MOD and XM loads do.
    if (m.sndh.active) {
        m.sndh.abandon();
        m.sfx.reset();
        if (m.current_mode == 4) m.current_mode = 0;
    }
    return sap.load(len);
}

/// Start subsong `song`: 1..SONGS, or 0 for the file's DEFSONG (as an SNDH's tune).
export fn audioSapPlay(song: u32) void {
    m.stopAll();
    audio.machinePaulaClearScopes();
    sap.start(if (song >= 1 and song <= 255) @intCast(song - 1) else 255);
    m.current_mode = if (sap.active) 5 else 0;
}

export fn audioSapStop() void {
    sap.stop();
    if (m.current_mode == 5) m.current_mode = 0;
}

/// Why the last SAP did not load or stopped, for the host to say:
/// bits 0-7 the load's refusal (sap.zig Refusal), 8-15 the CPU's stop
/// (sap_player.zig Stopped: 1 JAM, 2 unstable opcode, 3 a call that never
/// returned), 16-23 the opcode it stopped on. 0 = playing, or played fine.
export fn audioSapStatus() u32 {
    return @intFromEnum(sap.refused) | (@as(u32, @intFromEnum(sap.stopped)) << 8) | (@as(u32, sap.stop_op) << 16);
}
/// The PC it stopped at.
export fn audioSapStopPc() u32 {
    return sap.stop_pc;
}
/// Hardware writes the tune made that nothing answers ($D000-$D7FF, not the
/// POKEY or WSYNC), and POKEY writes lost to a full queue: never silent.
export fn audioSapUnknownWrites() u32 {
    return players.sap_bus.unknown;
}
export fn audioSapLostWrites() u32 {
    return players.sap_bus.overflow;
}
/// Subsongs in the loaded file.
export fn audioSapSongs() u32 {
    return sap.info.songs;
}
