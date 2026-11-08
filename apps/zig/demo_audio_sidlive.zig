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
//   close  (or any song, stream, or the machine's reset) the queue stops playing
// --------------------------------------------------------------------------
const audio = @import("audio_hw");
const players = @import("players");
const m = @import("root");
const sl = players.sid_live;

/// The queue lives in song RAM, below the SID player's chunk (sid.zig CHUNK_OFF): SID live plays no
/// file, and a static would be ~21 KB of data segment in demo-audio.wasm and in BARD's image. All
/// else that takes song RAM (a song, a stream) stops the SID player first, so nothing reads it then:
/// every export below answers only while the queue is open (the stage pointer is 0 when closed).
const LIVE_OFF: u32 = 0;
comptime {
    if (LIVE_OFF + @sizeOf(sl.Live) > players.sid.CHUNK_OFF) @compileError("the BARD queue overlaps the SID chunk");
}
fn live() *sl.Live {
    return @ptrFromInt(audio.SONG_BASE + LIVE_OFF);
}

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
    live().reset(lead);
    m.sid_exports.sid.startLive(live());
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

/// Where the host copies a batch (0 while closed: song RAM is someone else's then).
export fn audioBardStagePtr() u32 {
    return if (open()) @intCast(@intFromPtr(&live().queue.stage)) else 0;
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
    return live().pushStaged(n);
}

/// Events: a ring of EventCap 16-byte entries (sid_live.Event), EventCount produced in all.
export fn audioBardEventsPtr() u32 {
    return if (open()) @intCast(@intFromPtr(&live().events)) else 0;
}
export fn audioBardEventCap() u32 {
    return sl.EV_CAP;
}

/// One counter of the open queue, 0 while closed.
fn stat(comptime f: fn (*const sl.Live) u32) u32 {
    return if (open()) f(live()) else 0;
}
fn evCount(l: *const sl.Live) u32 {
    return l.ev_count;
}
fn anchored(l: *const sl.Live) u32 {
    return @intFromBool(l.queue.anchored);
}
fn applied(l: *const sl.Live) u32 {
    return l.applied;
}
fn refused(l: *const sl.Live) u32 {
    return l.refused;
}
fn dropped(l: *const sl.Live) u32 {
    return l.queue.dropped;
}
fn resyncs(l: *const sl.Live) u32 {
    return l.queue.resyncs;
}
fn pending(l: *const sl.Live) u32 {
    return l.queue.len;
}

export fn audioBardEventCount() u32 {
    return stat(evCount);
}
/// The cart-clock sample the queue has rendered up to; Anchored 0 before the first batch.
export fn audioBardPosition() u32 {
    return stat(sl.Live.position);
}
export fn audioBardAnchored() u32 {
    return stat(anchored);
}
export fn audioBardApplied() u32 {
    return stat(applied);
}
export fn audioBardRefused() u32 {
    return stat(refused);
}
export fn audioBardDropped() u32 {
    return stat(dropped);
}
export fn audioBardResyncs() u32 {
    return stat(resyncs);
}
/// Commands queued, their sample not come yet.
export fn audioBardPending() u32 {
    return stat(pending);
}
export fn audioBardClosedDrops() u32 {
    return closed_drops;
}
