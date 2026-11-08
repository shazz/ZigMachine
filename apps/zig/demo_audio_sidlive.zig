// --------------------------------------------------------------------------
// demo-audio.wasm: the BARD queue's player side (decisions.md 2026-11-07 "The
// BARD queue"). A cart's zg.bard ring is drained by its host (docs/sealed-
// loader.js + audio-worklet-sealed.js; fpga/host/bardq_pump.c on the native
// host and on BARD) into this module: the host copies a batch of 16-byte
// entries into the stage and calls audioBardQueue(n); the SID live player
// (libs/zig/players/sid.zig, sid_live.zig) plays each at its sample. Events go
// back the other way: the host copies those past the count it took.
//   open   every player stops; the SID player plays the queue (silent until
//          the cart's first SID reset), on the four Paula channels (mode 1)
//   close  (or any song, or the machine's reset) the queue stops playing
// --------------------------------------------------------------------------
const players = @import("players");
const m = @import("root");
const sl = players.sid_live;

var live: sl.Live = .{};
/// Entries handed over while nothing played them (counted, never applied).
var closed_drops: u32 = 0;

fn open() bool {
    return m.sid_exports.sid.active and m.sid_exports.sid.live != null;
}

/// Start SID live with `lead` (the most samples a batch may arrive after its first write's
/// stamp: the cart's longest frame plus the host's delay), clamped to 256..16384. Always 1.
export fn audioBardOpen(lead: u32) u32 {
    if (m.sndh.active) m.sndh.abandon();
    m.stopAll();
    m.sfx.songChanged();
    live.reset(lead);
    m.sid_exports.sid.startLive(&live);
    m.current_mode = 1; // the four Paula channels, as the .sid player's
    return 1;
}

export fn audioBardClose() void {
    if (!open()) return;
    m.sid_exports.sid.stop();
    m.sid_exports.sid.live = null;
    if (m.current_mode == 1) m.current_mode = 0;
}

export fn audioBardActive() u32 {
    return @intFromBool(open());
}

export fn audioBardStagePtr() u32 {
    return @intCast(@intFromPtr(&live.queue.stage));
}
export fn audioBardStageCap() u32 {
    return sl.Queue.STAGE_N;
}

/// The `n` staged entries queued for their samples; returns those taken (0: nothing plays them,
/// and they are counted in audioBardClosedDrops).
export fn audioBardQueue(n: u32) u32 {
    if (!open()) {
        closed_drops +%= n;
        return 0;
    }
    return live.pushStaged(n);
}

/// Events: a ring of EventCap 16-byte entries (sid_live.Event), EventCount produced in all.
export fn audioBardEventsPtr() u32 {
    return @intCast(@intFromPtr(&live.events));
}
export fn audioBardEventCap() u32 {
    return sl.EV_CAP;
}
export fn audioBardEventCount() u32 {
    return live.ev_count;
}

/// The cart-clock sample the queue has rendered up to; Anchored 0 before the first batch.
export fn audioBardPosition() u32 {
    return live.position();
}
export fn audioBardAnchored() u32 {
    return @intFromBool(live.queue.anchored);
}

export fn audioBardApplied() u32 {
    return live.applied;
}
export fn audioBardRefused() u32 {
    return live.refused;
}
export fn audioBardDropped() u32 {
    return live.queue.dropped;
}
export fn audioBardResyncs() u32 {
    return live.queue.resyncs;
}
export fn audioBardClosedDrops() u32 {
    return closed_drops;
}
/// Commands queued, their sample not come yet.
export fn audioBardPending() u32 {
    return live.queue.len;
}
