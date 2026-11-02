// --------------------------------------------------------------------------
// The cart's Paula writes, waiting for their sample (HW 1.14.0, decisions.md
// 2026-11-02 "Paula channels for carts").
//
// A cart that holds the four Paula channels (env.hostPaulaClaim) hands the host
// its frame's Amiga register writes as 16-byte entries (Entry), each stamped
// with the CART's sample clock `t` (44.1 kHz, its own count of the audio it has
// paced, e.g. pt2's replayer ticks inside its audio callback). The audio side
// plays them at their sample, not at the frame's edge: a 50 Hz replay on a cart
// running 60 fps (the browser) or 20 fps (the board) keeps its rhythm.
//
// The two clocks are tied by one offset: stamp = t + offset, in the audio
// side's own render count (`now`). The first batch anchors it `lead` samples
// ahead of now (the cart says how late its batches can be: its longest frame);
// a batch that arrives with its first stamp already past (late) or absurdly far
// ahead (the cart's clock jumped) re-anchors it, and is counted (resyncs).
// Within a batch, and between batches that keep time, every write keeps its
// distance to the others, sample for sample.
//
// Plain state, no chip calls: tested natively (cart_paula_queue_test.zig). The
// chip side (paula.zig, the render loop) is apps/zig/demo_audio_paula.zig.
// --------------------------------------------------------------------------

/// One register write as the cart hands it over (little-endian, the host copies
/// the bytes): `addr` an Amiga bus address ($DFF096 DMACON, $DFF0A0 + 16 x AUDx
/// LCH/LCL/LEN/PER/VOL, $DFF0AC + 16 x the KESTREL AUDxPAN), `value` its 16 bits.
pub const Entry = extern struct {
    t: u32,
    addr: u32,
    value: u32,
    pad: u32 = 0,
};
comptime {
    if (@sizeOf(Entry) != 16) @compileError("the hosts copy 16-byte entries");
}

/// Writes waiting at most: a lead's worth of a busy replay (pt2: ~40 a row).
pub const CAP: u32 = 2048;
/// A batch is copied in here by the host, then pushStaged(n) queues it.
pub const STAGE: u32 = 512;
pub const LEAD_MIN: u32 = 256;
pub const LEAD_MAX: u32 = 16384; // 371 ms
/// A batch whose first stamp is further ahead than this many leads re-anchors.
const AHEAD_LEADS: u32 = 4;

pub const Queue = struct {
    ring: [CAP]Entry = undefined,
    // Here rather than a static of its own: an all-zero static joins demo-audio.wasm's big zero
    // run in its data section (apps/zero_segments.mjs counts it).
    stage: [STAGE]Entry = undefined,
    head: u32 = 0,
    len: u32 = 0,
    offset: u32 = 0,
    anchored: bool = false,
    lead: u32 = 2048,
    /// Samples rendered since the claim: the audio side's clock.
    now: u32 = 0,
    resyncs: u32 = 0,
    dropped: u32 = 0,

    /// The `n` entries the host staged, queued (push).
    pub fn pushStaged(self: *Queue, n: u32) u32 {
        return self.push(self.stage[0..@min(n, STAGE)]);
    }

    pub fn reset(self: *Queue, lead: u32) void {
        // Field by field: `self.* = .{}` would put a second copy of the struct in the data section.
        self.head = 0;
        self.len = 0;
        self.offset = 0;
        self.anchored = false;
        self.now = 0;
        self.resyncs = 0;
        self.dropped = 0;
        self.lead = @max(LEAD_MIN, @min(lead, LEAD_MAX));
    }

    fn ahead(self: *const Queue, t: u32) i32 {
        return @bitCast(t +% self.offset -% self.now);
    }

    /// Append a batch (in the cart's order); anchor on its first write. Returns the
    /// writes taken: a full queue drops the rest (counted).
    pub fn push(self: *Queue, batch: []const Entry) u32 {
        if (batch.len == 0) return 0;
        const d = self.ahead(batch[0].t);
        const far: i64 = @as(i64, self.lead) * AHEAD_LEADS;
        if (!self.anchored or d < 0 or d > far) {
            if (self.anchored) self.resyncs +%= 1;
            self.offset = self.now +% self.lead -% batch[0].t;
            self.anchored = true;
        }
        var taken: u32 = 0;
        for (batch) |e| {
            if (self.len == CAP) {
                self.dropped +%= @intCast(batch.len - taken);
                break;
            }
            self.ring[(self.head + self.len) % CAP] = e;
            self.len += 1;
            taken += 1;
        }
        return taken;
    }

    /// The first write, once its sample has come (stamp <= now), taken off the queue.
    pub fn due(self: *Queue) ?Entry {
        if (self.len == 0) return null;
        const e = self.ring[self.head];
        if (self.ahead(e.t) > 0) return null;
        self.head = (self.head + 1) % CAP;
        self.len -= 1;
        return e;
    }

    /// Samples until the next write's stamp, at most `max` (all of it when none waits).
    pub fn untilNext(self: *const Queue, max: u32) u32 {
        if (self.len == 0) return max;
        const d = self.ahead(self.ring[self.head].t);
        if (d <= 0) return 0;
        return @min(max, @as(u32, @intCast(d)));
    }

    pub fn advance(self: *Queue, n: u32) void {
        self.now +%= n;
    }
};
