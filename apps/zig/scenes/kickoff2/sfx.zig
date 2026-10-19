// --------------------------------------------------------------------------
// Kickoff2 — the digi bank as a one-shot samples-only stream. The Go repo
// decodes the original's Paula `expsound` bank (period-word + signed 8-bit);
// tools/kickoff2/ko2_assets.py re-rendered it to the cart ring's 12 kHz and
// curated the kick/whistle/contact/bounce set. The ring loops until stopped,
// so the scene feeds it at the audio's own pace: queued sample bytes, then
// silence while idle. No MOD bed, no SNDH — samples only, as requested.
//
// events (the original's originalSoundCommands mapping):
//   kick small  = sample 8         post     = sample 9    bounce = 1..4
//   contact     = sample 7         whistle  = samples 6/16 (both halves)
// bank index = sample index mapped by sounds.txt (KEPT list order).
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const ballMod = @import("ball.zig");
const g = @import("gs.zig");

const RATE: f32 = 12000.0;
const RING: usize = 32768;

const sounds_bin = @embedFile("../../assets/screens/kickoff2/sounds.bin");

// Bank ids (order in sounds.bin = KEPT [0,1,2,3,6,7,8,9,14,15,16]):
pub const Bounce1: u5 = 0;
pub const Bounce2: u5 = 1;
pub const Bounce3: u5 = 2;
pub const Bounce4: u5 = 3;
pub const WhistleShort: u5 = 4; // sample 6
pub const Contact: u5 = 5; // sample 7
pub const KickSmall: u5 = 6; // sample 8
pub const Post: u5 = 7; // sample 9
pub const CrowdGoal: u5 = 8; // sample 14
pub const CrowdBoo: u5 = 9; // sample 15
pub const WhistleLong: u5 = 10; // sample 16

const Sample = struct { off: u32 = 0, len: u32 = 0, course: u32 = 0 };
const MAXS = 11;
var bank: [MAXS]Sample = [_]Sample{.{}} ** MAXS;
var bankRate: u16 = RATE_RATE;
const RATE_RATE = 12000;

var queue: [8]u5 = [_]u5{0} ** 8;
var qhead: u8 = 0;
var qtail: u8 = 0;
// samples-per-play remixes: goal whistle + crowd play as one queued pair.
var budget: f32 = 0;
var started = false;
var silence_buf = [_]u8{0} ** 512;

/// Module init: parse sounds.bin, start the ring.
pub fn init() void {
    if (started) return;
    started = true;
    const b = sounds_bin;
    const count = std.mem.readInt(u16, b[0..2], .little);
    const rate: u16 = std.mem.readInt(u16, b[2..4], .little);
    bankRate = rate;
    var off: u32 = 4 + 4 * @as(u32, count);
    var i: usize = 0;
    while (i < count and i < MAXS) : (i += 1) {
        const at = 4 + i * 4;
        const len = std.mem.readInt(u32, b[at..][0..4], .little);
        bank[i] = .{ .off = off, .len = len };
        off += len;
    }
    zg.audioStreamStart(RATE);
}

/// An event carrier the sim's ball step fills each tick; the drain turns it
/// into queue entries exactly like the original's audio cues.
pub fn reqEvent() *ballMod.Event {
    tickEvent = .{};
    return &tickEvent;
}

var tickEvent: ballMod.Event = .{};

pub fn requestWhistle() void {
    queuePush(WhistleLong);
}
pub fn requestKick() void {
    queuePush(KickSmall);
}
pub fn requestPost() void {
    queuePush(Post);
}
pub fn requestContact() void {
    queuePush(Contact);
}
pub fn requestGoal() void {
    queuePush(WhistleLong);
    queuePush(CrowdGoal);
}
pub fn requestFullTime() void {
    queuePush(WhistleLong);
    queuePush(WhistleLong);
    queuePush(CrowdBoo);
}

fn queuePush(id: u5) void {
    if ((qtail + 1) % 8 == qhead) return; // full: drop (the source did too)
    queue[qtail] = id;
    qtail = (qtail + 1) % 8;
}

/// Drain the per-tick event carrier into the queue once per tick.
fn drainEvent() void {
    if (tickEvent.kick) queuePush(KickSmall);
    if (tickEvent.post) queuePush(Post);
    if (tickEvent.contact) queuePush(Contact);
    if (tickEvent.bounce >= 1 and tickEvent.bounce <= 4) {
        const idx: u4 = @intCast(tickEvent.bounce - 1); // bank 0..3
        queuePush(idx);
    }
    tickEvent = .{};
}

/// Per-frame feeder (call from update, paced by dt).`
pub fn update(elapsed_ms: f32) void {
    drainEvent();
    budget += RATE * @max(elapsed_ms, 0) / 1000.0;
    var guard: usize = 0;
    while (budget >= 512 and guard < 64) : (guard += 1) {
        budget -= 512;
        feedChunk();
    }
}

fn feedChunk() void {
    var buf: [512]u8 = silence_buf;
    var filled: u32 = 0;
    // First, any queued/current sample bytes.
    while (filled < buf.len) {
        if (qhead == qtail) break;
        const s = &bank[queue[qhead]];
        const have: u32 = s.len - s.course;
        if (have == 0) {
            qhead = (qhead + 1) % 8; // consumed
            continue;
        }
        const n: u32 = @min(buf.len - filled, have);
        @memcpy(buf[filled..][0..n], sounds_bin[s.off + s.course ..][0..n]);
        s.course += n;
        filled += n;
        if (s.course >= s.len) qhead = (qhead + 1) % 8;
    }
    zg.audioFeed(&buf);
}
