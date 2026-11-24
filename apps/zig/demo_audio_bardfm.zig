// --------------------------------------------------------------------------
// demo-audio.wasm: which player plays the BARD queue (demo_audio_sidlive.zig has the queue's exports).
// The SID player by default (SID live, the AY device, an open's silence); the VGM player for the FM
// device (players/fm_live.zig: the engine's own SFX device under the tune). The first device write of
// an open with none picks; a VGM playing when the queue opens keeps the queue until a SID / AY write.
// --------------------------------------------------------------------------
const players = @import("players");
const m = @import("root");
const sl = players.sid_live;
const live = @import("demo_audio_sidlive.zig").live;

/// The VGM player plays the queue (the FM device, or an open while a VGM played).
pub fn vgmPlays() bool {
    return m.vgm_exports.vgm.active and m.vgm_exports.vgm.live != null;
}

/// The open's device (none until a write picks one).
pub fn device() sl.Live.Device {
    return live().device;
}

/// The queue to the VGM player (its tune, if any, plays on).
pub fn toVgm() void {
    if (m.sid_exports.sid.live != null) {
        m.sid_exports.sid.stop();
        m.sid_exports.sid.live = null;
    }
    m.vgm_exports.vgm.startLive(live());
    m.current_mode = 1;
}

/// The queue to the SID player (a SID or AY write on an open the VGM player held): the tune stops.
fn toSid() void {
    m.vgm_exports.vgm.stop();
    m.sid_exports.sid.startLive(live());
    m.current_mode = 1;
}

/// An open with no device yet takes the one the batch's first device write picks.
pub fn pick(n: u32) void {
    const l = live();
    if (l.device != .none) return;
    for (l.queue.stage[0..@min(n, sl.Queue.STAGE_N)]) |e| {
        const d = sl.picks(e.addr) orelse continue;
        if (d == .fm) {
            l.device = .fm;
            if (!vgmPlays()) toVgm();
        } else if (vgmPlays()) {
            toSid();
        }
        return;
    }
}
