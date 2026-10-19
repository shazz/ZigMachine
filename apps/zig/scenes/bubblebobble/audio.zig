// --------------------------------------------------------------------------
// BUBBLE BOBBLE — sound. Two independent machines, both of them the cart's
// own hardware, exactly as the Go remake drives the two halves of its audio
// context:
//
//  * MUSIC: the original's five YM tunes (resources/audio/bubble-1..5.ym,
//    LHA-wrapped YM5/YM6 in the source, parsed to a per-frame register DELTA
//    stream by tools/bubblebobble/bb_assets.py) replayed through the machine's
//    YM2149 with zg.ymWrite, one frame per 50 Hz tick. That is the larcociel5
//    technique; frame 0 is a full 14-register write so a loop restarts the
//    chip in its opening state.
//  * SFX: the ten WAVs the Go plays as one-shot players, re-rendered to the
//    cart ring's 12 kHz signed 8-bit mono and pushed through
//    zg.audioStreamStart/zg.audioFeed (the kickoff2 sfx pattern). The ring
//    carries the samples; the YM stays live beside it — the machine audio
//    mixes the raw streamer and the YM together.
//
// Nothing here is host-side.
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const assets = @import("assets.zig");

pub const RATE: f32 = 12000.0;
const CHUNK: usize = 512;

pub const Track = enum(u8) { menu = 0, theme = 1, hurry = 2, gameover = 3, win = 4 };

pub var muted = false;
pub var refused: u32 = 0; // ymWrite rejections; the gate asserts this stays 0
pub var fed: u32 = 0; // sample bytes handed to the ring

/// The register file the cart last applied (the harness's mirror check).
pub fn regAt(i: u32) u32 {
    if (i >= 14) return 0;
    return m_regs[i];
}
/// How many frames of the current tune have been played (the harness's clock).
pub fn appliedFrames() u32 {
    return m_applied;
}

// --- music ------------------------------------------------------------------
var m_track: Track = .menu;
var m_pos: usize = 0; // byte offset of the NEXT frame in MUSIC_BIN
var m_frames: u32 = 0;
var m_next: u32 = 0;
var m_applied: u32 = 0;
var m_regs: [14]u8 = [_]u8{0} ** 14; // the frame being played
var m_sum: [14]u8 = [_]u8{0} ** 14; // what the chip was last told
var m_live = false;
var m_force = true; // write every register on the next frame
var m_silenced = false;

pub fn play(track: Track) void {
    m_track = track;
    m_pos = assets.MUSIC[@intFromEnum(track)].off + 2;
    m_frames = assets.MUSIC[@intFromEnum(track)].frames;
    m_next = 0;
    m_applied = 0;
    m_live = true;
    m_force = true;
    m_regs = [_]u8{0} ** 14;
}

fn silenceChip() void {
    if (m_silenced) return;
    _ = zg.ymWrite(7, 0x3F);
    _ = zg.ymWrite(8, 0);
    _ = zg.ymWrite(9, 0);
    _ = zg.ymWrite(10, 0);
    m_silenced = true;
}

/// One 50 Hz tick: apply the next music frame.
pub fn tick() void {
    if (muted) {
        silenceChip();
        return;
    }
    m_silenced = false;
    if (!m_live) return;
    applyOne(m_force);
    m_force = false;
}

fn applyOne(force: bool) void {
    const b = assets.MUSIC_BIN;
    const mask = std.mem.readInt(u16, b[m_pos..][0..2], .little);
    m_pos += 2;
    var r: u8 = 0;
    while (r < 14) : (r += 1) {
        if (mask & (@as(u16, 1) << @intCast(r)) != 0) {
            m_regs[r] = b[m_pos];
            m_pos += 1;
        }
    }
    // Only registers whose value actually CHANGED go to the chip: register 13
    // (the envelope shape) must not be silently retriggered every frame.
    r = 0;
    while (r < 14) : (r += 1) {
        if (force or m_sum[r] != m_regs[r]) {
            if (!zg.ymWrite(r, m_regs[r])) refused +%= 1;
            m_sum[r] = m_regs[r];
        }
    }
    m_next += 1;
    m_applied += 1;
    if (m_next >= m_frames) {
        m_next = 0;
        m_pos = assets.MUSIC[@intFromEnum(m_track)].off + 2;
        m_force = true; // frame 0 is a full write: the loop restarts the chip
    }
}

pub fn toggleMute() void {
    muted = !muted;
    if (!muted) m_force = true;
}

// --- sfx --------------------------------------------------------------------
const MAXS = 10;
const Sample = struct { off: u32 = 0, len: u32 = 0, course: u32 = 0 };
var bank: [MAXS]Sample = [_]Sample{.{}} ** MAXS;
var queue: [6]u8 = [_]u8{0} ** 6;
var qhead: u8 = 0;
var qtail: u8 = 0;
var budget: f32 = 0;
var started = false;

pub fn init() void {
    for (0..MAXS) |i| {
        bank[i] = .{ .off = assets.SFX[i].off, .len = assets.SFX[i].len, .course = 0 };
    }
    if (!started) {
        started = true;
        zg.audioStreamStart(RATE);
    }
}

pub fn sfx(id: u8) void {
    if (muted or id >= MAXS) return;
    if ((qtail + 1) % 6 == qhead) return; // full: the Go capped its players too
    queue[qtail] = id;
    qtail = (qtail + 1) % 6;
}

pub fn pending() bool {
    return qhead != qtail;
}

/// Per-frame feeder, paced by the host's own delta.
pub fn update(elapsed_ms: f32) void {
    if (!started) return;
    if (std.math.isFinite(elapsed_ms) and elapsed_ms > 0) {
        budget += RATE * @min(elapsed_ms, 200.0) / 1000.0;
    }
    var guard: usize = 0;
    while (budget >= @as(f32, @floatFromInt(CHUNK)) and guard < 64) : (guard += 1) {
        budget -= @as(f32, @floatFromInt(CHUNK));
        feedChunk();
    }
}

fn feedChunk() void {
    var buf: [CHUNK]u8 = [_]u8{0} ** CHUNK;
    var filled: usize = 0;
    while (filled < CHUNK) {
        if (qhead == qtail) break;
        const s = &bank[queue[qhead]];
        const have = s.len - s.course;
        if (have == 0) {
            qhead = (qhead + 1) % 6;
            continue;
        }
        const n: usize = @min(CHUNK - filled, have);
        @memcpy(buf[filled..][0..n], assets.SFX_BIN[s.off + s.course ..][0..n]);
        s.course += @intCast(n);
        filled += n;
        if (s.course >= s.len) qhead = (qhead + 1) % 6;
    }
    zg.audioFeed(&buf);
    fed += @intCast(filled);
}
