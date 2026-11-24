// --------------------------------------------------------------------------
// demo-audio.wasm: the BARD queue's player side (docs/project/DECISIONS.md 2026-11-07 "The
// BARD queue"). A cart's zg.bard ring is drained by its host (docs/sealed-
// loader.js + audio-worklet-sealed.js; fpga/host/bardq_pump.c on the native
// host and on BARD) into this module: the host copies a batch of 16-byte
// entries into the stage and calls audioBardQueue(n); the SID live player
// (libs/zig/players/sid.zig, sid_live.zig) plays each at its sample. Events go
// back the other way: the host copies those past the count it took.
//   open   every player stops; the SID player plays the queue (silent until
//          the cart's first SID reset), on the four Paula channels (mode 1)
//   close  (or any song, stream, or the machine's reset) the queue stops playing
// The FM device (players/fm_live.zig) is played by the VGM player instead: its first write queued
// hands the queue over to it (a tune loaded meanwhile plays under the queue); a VGM playing when the
// queue opens keeps playing, and the queue is the VGM player's until a SID or AY write picks them.
// --------------------------------------------------------------------------
const audio = @import("audio_hw");
const players = @import("players");
const m = @import("root");
const sl = players.sid_live;

/// The queue lives in song RAM, at its top below the Paula rings: SID live plays no file, a VGM under
/// the FM device sits below it (the song RAM's room is LIVE_OFF while the queue is open: audioSongCapacity),
/// and a static would be ~22 KB of data segment in demo-audio.wasm and in BARD's image. All else that
/// takes song RAM (another song, a stream) stops the queue first, so nothing reads it then: every
/// export below answers only while the queue is open (the stage pointer is 0 when closed).
pub const LIVE_OFF: u32 = players.xm_chip.BUF_OFFSET - 0x6000;
comptime {
    if (@sizeOf(sl.Live) > 0x6000) @compileError("the BARD queue overflows its room below the Paula rings");
    if (LIVE_OFF < players.sid.CHUNK_OFF + 2 * players.sid.CHUNK) @compileError("the BARD queue overlaps the SID chunk");
}
pub fn live() *sl.Live {
    return @ptrFromInt(audio.SONG_BASE + LIVE_OFF);
}

/// Entries handed over while nothing played them (counted, never applied).
var closed_drops: u32 = 0;

pub fn open() bool {
    return (m.sid_exports.sid.active and m.sid_exports.sid.live != null) or vgmPlays();
}

// Which player plays the queue (the SID player, or the VGM player for the FM device): demo_audio_bardfm.zig.
const hand = @import("demo_audio_bardfm.zig");
pub const vgmPlays = hand.vgmPlays;
pub const device = hand.device;
pub const toVgm = hand.toVgm;
const pick = hand.pick;

/// Start SID live with `lead` (the most samples a batch may arrive after its first write's
/// stamp: the cart's longest frame plus the host's delay), clamped to 256..16384. Always 1.
export fn audioBardOpen(lead: u32) u32 {
    if (m.vgm_exports.vgm.active) { // a VGM playing keeps playing: the queue is its player's (FM) until a SID / AY write
        m.vgm_exports.vgm.endLive();
        live().reset(lead);
        audio.machineAyReset();
        toVgm();
        return 1;
    }
    if (m.sndh.active) m.sndh.abandon();
    m.stopAll();
    m.sfx.songChanged();
    live().reset(lead);
    audio.machineAyReset(); // the AY device silent until the cart configures a chip
    m.sid_exports.sid.startLive(live());
    m.current_mode = 1; // the four Paula channels, as the .sid player's
    return 1;
}

export fn audioBardClose() void {
    if (!open()) return;
    if (vgmPlays()) {
        m.vgm_exports.vgm.endLive();
        if (!m.vgm_exports.vgm.active and m.current_mode == 1) m.current_mode = 0;
        return;
    }
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
    pick(n);
    const taken = live().pushStaged(n);
    if (vgmPlays()) players.fm_live.feed(live(), m.vgm_exports.vgm.base); // the FM device's writes go ahead at once
    return taken;
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
    return l.applied +% fmStat(l, 0);
}
fn refused(l: *const sl.Live) u32 {
    return l.refused +% fmStat(l, 1);
}
/// The FM device's own counters (the engine applies and refuses its writes): 0 applied, 1 refused, 2 waiting, 3 late.
fn fmStat(l: *const sl.Live, i: u32) u32 {
    return if (l.device == .fm) audio.machineVgmSfxStat(i) else 0;
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
/// Commands queued, their sample not come yet (the FM device: those in its engine's ring too).
export fn audioBardPending() u32 {
    return stat(pending) +% stat(fmPending);
}
fn fmPending(l: *const sl.Live) u32 {
    return fmStat(l, 2);
}
/// FM device writes that reached the engine after their engine frame was rendered (applied at once).
export fn audioBardLate() u32 {
    return stat(fmLate);
}
fn fmLate(l: *const sl.Live) u32 {
    return fmStat(l, 3);
}
/// The device the open plays: 0 none yet, 1 SID, 2 AY, 3 FM.
export fn audioBardDevice() u32 {
    return if (open()) @intFromEnum(live().device) else 0;
}
export fn audioBardClosedDrops() u32 {
    return closed_drops;
}
