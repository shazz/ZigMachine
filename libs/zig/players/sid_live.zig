// --------------------------------------------------------------------------
// SID live: the BARD queue's first device (decisions.md 2026-11-07 "The BARD
// queue"). A cart writes the SID's registers itself, as a C64 player does
// (a GoatTracker replay ticking at 50 Hz), through zg.bard: a ring in its own
// memory that the host drains without anyone waiting. Each write is stamped
// with the CART's 44.1 kHz sample clock and lands at that sample here, through
// the Paula queue's own mechanism (cart_paula_queue.QueueOf: one offset ties
// the two clocks, a lead ahead of the first batch; late batches re-anchor).
//
// The engine is cRSID in raw mode (machineSidRaw: a C64 with no tune), at
// 22.05 kHz: the queue counts output samples (44.1), so an engine sample is
// two of them and a write takes hold at the first engine sample at or after
// its stamp. Until the cart's first SID reset the engine is off (silence),
// whatever .sid played before.
//
// The AY device (libs/c/ayumi zm_ay_bank.h, ChipNomad's chips) takes the
// addresses $A000..$A0FF; it renders at the queue's own 44.1 kHz, so its
// writes land at their output sample exactly. One device an open: the first
// SID reset or AY configure picks it, and the other's writes are refused.
//
// Plain state, no chip calls (sid_live_test.zig): the player that renders it
// is sid.zig (SidPlayer.live), the exports apps/zig/demo_audio_sidlive.zig.
// --------------------------------------------------------------------------
const cq = @import("cart_paula_queue.zig");

pub const Entry = cq.Entry;
pub const Queue = cq.QueueOf(1024, 256);

/// Entry.addr: a SID register at $D400 + 0..0x18, or one of the queue's own commands.
pub const SID_BASE: u32 = 0xD400;
pub const SID_REGS: u32 = 0x19;
pub const OP_RESET: u32 = 1; // a fresh raw SID; value = 6581 or 8580
pub const OP_MARK: u32 = 2; // an event back when the write's sample comes; value = the cart's arg
/// The AY device: addr = AY_BASE + chip x 16 + reg (14 configures the chip), AY_BASE + 0x80 + chip its gain.
pub const AY_BASE: u32 = 0xA000;
pub const AY_SPAN: u32 = 0x100;
pub const AY_REG_CONFIG: u32 = 14;

/// What comes back to the cart (zg.bard.pollEvent), at the sample it happened.
pub const Kind = enum(u32) { mark = 1, reset = 2, resync = 3, dropped = 4 };
pub const Event = extern struct {
    t: u32, // the cart's clock: the entry's stamp (resync / dropped: the consumer's position)
    kind: u32,
    arg: u32, // 24 bits. mark: the cart's value; reset: the model; resync / dropped: the count so far
    seq: u32 = 0, // the ring index, set where the event lands in the cart's ring
};
pub const EV_CAP: u32 = 64;

pub const Live = struct {
    queue: Queue = .{},
    events: [EV_CAP]Event = undefined,
    /// Events produced (total, wraps): the hosts copy those past what they took.
    ev_count: u32 = 0,
    applied: u32 = 0,
    refused: u32 = 0,
    /// The engine has had its first reset (before it, silence).
    engine_on: bool = false,
    /// What this open plays: picked by the first SID reset or AY configure.
    device: Device = .none,
    pub const Device = enum(u8) { none, sid, ay };

    pub fn reset(self: *Live, lead: u32) void {
        self.queue.reset(lead);
        self.ev_count = 0;
        self.applied = 0;
        self.refused = 0;
        self.engine_on = false;
        self.device = .none;
    }

    fn event(self: *Live, t: u32, kind: Kind, arg: u32) void {
        // 24 bits on every host: the board carries kind and arg in one word (snd_mailbox.h S_BQ_EV).
        self.events[self.ev_count % EV_CAP] = .{ .t = t, .kind = @intFromEnum(kind), .arg = arg & 0xFF_FFFF };
        self.ev_count +%= 1;
    }

    /// A batch from the cart's ring, in its order. A re-anchor or a drop is said back.
    pub fn push(self: *Live, batch: []const Entry) u32 {
        const resyncs = self.queue.resyncs;
        const dropped = self.queue.dropped;
        const taken = self.queue.push(batch);
        if (self.queue.resyncs != resyncs) self.event(self.position(), .resync, self.queue.resyncs);
        if (self.queue.dropped != dropped) self.event(self.position(), .dropped, self.queue.dropped);
        return taken;
    }

    pub fn pushStaged(self: *Live, n: u32) u32 {
        return self.push(self.queue.stage[0..@min(n, Queue.STAGE_N)]);
    }

    /// The next write whose sample has come, or null.
    pub fn take(self: *Live) ?Entry {
        return self.queue.due();
    }

    /// What a write does here beside the chip: the counters, and its event. Returns
    /// .sid (write the register), .reset (a fresh engine), .ay (the AY device's write: the caller
    /// counts it with ayAnswer, as the device takes it or not) or .none.
    pub const Do = enum { none, sid, reset, ay };
    pub fn classify(self: *Live, e: Entry) Do {
        if (e.addr >= AY_BASE and e.addr < AY_BASE + AY_SPAN and self.device != .sid) {
            if ((e.addr - AY_BASE) & 0x8F == AY_REG_CONFIG) self.device = .ay;
            return .ay;
        }
        if (e.addr >= SID_BASE and e.addr < SID_BASE + SID_REGS and self.device != .ay) {
            self.applied +%= 1;
            return .sid;
        }
        if (e.addr == OP_RESET and self.device != .ay) {
            self.applied +%= 1;
            self.engine_on = true;
            self.device = .sid;
            self.event(e.t, .reset, e.value);
            return .reset;
        }
        if (e.addr == OP_MARK) {
            self.applied +%= 1;
            self.event(e.t, .mark, e.value);
            return .none;
        }
        self.refused +%= 1;
        return .none;
    }

    /// The AY device's answer to a write classify gave it.
    pub fn ayAnswer(self: *Live, taken: bool) void {
        if (taken) self.applied +%= 1 else self.refused +%= 1;
    }

    /// Engine samples to render before the next write, at most `max` (>= 1 once the due ones
    /// are taken): a write stamped d output samples ahead waits ceil(d / 2) engine samples.
    pub fn chunk(self: *const Live, max: u32) u32 {
        const d = self.queue.untilNext(2 * max);
        return @max(1, (d + 1) / 2);
    }

    /// `n` engine samples rendered: the queue's clock moves on 2 n output samples.
    pub fn advance(self: *Live, n: u32) void {
        self.queue.advance(2 * n);
    }

    /// The consumer's position on the cart's clock: the stamp it has rendered up to (0 before
    /// the first batch anchors the two clocks).
    pub fn position(self: *const Live) u32 {
        return if (self.queue.anchored) self.queue.now -% self.queue.offset else 0;
    }
};
