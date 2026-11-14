// --------------------------------------------------------------------------
// zg.bard: the BARD queue (system table 1.12, decisions.md 2026-11-07 "The BARD
// queue", docs/ZIGOS_API.md 8d). A ring of timed commands from the cart to the
// sound side (BARD on the board, the AudioWorklet on the page) and a ring of
// events back, in the cart's own memory: the cart writes and never waits; its
// host takes the commands once a frame (on the board BARD reads them in DDR)
// and writes back what it took, the sound side's position and the events.
//
// Time is the cart's own 44.1 kHz sample clock: a command stamped t plays at
// sample t, a `lead` behind the first batch (the Paula queue's rule: HW_API 5).
// due(t) says when to produce the command stamped t, so a 50 Hz replay keeps
// the sound side's time whatever the cart's frame rate.
//
// Devices: SID live (cRSID with no tune: libs/zig/players/sid_live.zig) and up
// to eight AY / YM chips (libs/c/ayumi zm_ay_bank.h); one of the two an open.
// --------------------------------------------------------------------------
extern fn hostBardAttach(block: u32, lead: u32) u32;

/// Jobs for BARD (table 1.24): a coprocessor for non-music work (bard_job.zig).
pub const job = @import("bard_job.zig");

pub const MAGIC: u32 = 0x51424d5a; // "ZMBQ"
pub const CAP: u32 = 256; // commands the ring holds (a power of two)
pub const EV_CAP: u32 = 16; // events
pub const HEAD_WORDS: u32 = 16;

/// The block's header words (u32, little-endian). Who writes: the cart (C) or the host (H).
pub const W = struct {
    pub const magic = 0; // C
    pub const cap = 1; // C
    pub const ev_cap = 2; // C
    pub const lead = 3; // C
    pub const head = 4; // C: commands written (wraps)
    pub const tail = 5; // H: commands taken off the ring
    pub const dropped = 6; // C: commands refused, the ring full
    pub const pos = 7; // H: the sound side's position on the cart's clock
    pub const anchored = 8; // H: 1 once pos means something (the first batch has played in)
    pub const ev_head = 9; // H: events written (wraps)
    pub const ev_tail = 10; // C: events read
    pub const ev_lost = 11; // H: events that found the ring full (or, on the board, came too fast)
};

/// A command: the Paula queue's entry, `seq` its ring index (a reader takes it only when it matches).
pub const Cmd = extern struct { t: u32, addr: u32, value: u32, seq: u32 };
pub const Event = extern struct { t: u32, kind: u32, arg: u32, seq: u32 };
pub const Kind = enum(u32) { mark = 1, reset = 2, resync = 3, dropped = 4, _ };
pub const Model = enum(u32) { mos6581 = 6581, mos8580 = 8580 };

pub const SID_BASE: u32 = 0xD400; // a SID register write: addr = $D400 + 0..0x18
pub const AY_BASE: u32 = 0xA000; // an AY write: addr = $A000 + chip x 16 + reg (zm_ay_bank.h)
pub const AY_CHIPS: u32 = 8;
pub const OP_RESET: u32 = 1;
pub const OP_MARK: u32 = 2;

const Block = extern struct {
    head: [HEAD_WORDS]u32,
    cmds: [CAP]Cmd,
    events: [EV_CAP]Event,
};
var block: Block align(16) = undefined;
var attached: bool = false;

fn word(i: u32) *volatile u32 {
    return @ptrCast(&block.head[i]);
}

/// Hand the ring to the host. `lead`: the most samples a command may reach the sound side after
/// its stamp's turn (the cart's longest frame plus a frame; 256..16384). False: no BARD queue here
/// (no sound side yet, or a host without one): every command is then refused.
pub fn open(lead: u32) bool {
    for (&block.head) |*h| h.* = 0;
    // No slot's seq is its index before the cart writes it (a zeroed slot 0 would pass for command 0).
    for (&block.cmds) |*c| @as(*volatile u32, @ptrCast(&c.seq)).* = 0xFFFF_FFFF;
    word(W.cap).* = CAP;
    word(W.ev_cap).* = EV_CAP;
    word(W.lead).* = lead;
    word(W.pos).* = 0; // until the host says: a lead's worth from t = 0 is due at once
    word(W.magic).* = MAGIC;
    attached = hostBardAttach(@intCast(@intFromPtr(&block)), lead) != 0;
    return attached;
}

/// Stop the sound side playing the queue (the next cart's reset does too).
pub fn close() void {
    if (attached) _ = hostBardAttach(0, 0);
    attached = false;
}

fn push(t: u32, addr: u32, value: u32) bool {
    if (!attached) return false;
    const head = word(W.head).*;
    if (head -% word(W.tail).* >= CAP) {
        word(W.dropped).* +%= 1;
        return false;
    }
    const c: *volatile Cmd = @ptrCast(&block.cmds[head % CAP]);
    c.t = t;
    c.addr = addr;
    c.value = value;
    c.seq = head; // last: the entry is whole when its seq is its index
    word(W.head).* = head +% 1;
    return true;
}

/// SID register `reg` (0..0x18) to `value` at the cart's sample `t`. False: refused (ring full, closed).
pub fn sidWrite(t: u32, reg: u32, value: u8) bool {
    if (reg > 0x18) return false;
    return push(t, SID_BASE + reg, value);
}
/// A fresh SID (all registers 0, PAL) of `model` at `t`. The SID is silent until the first.
pub fn sidReset(t: u32, model: Model) bool {
    return push(t, OP_RESET, @intFromEnum(model));
}
/// AY chip `chip` (0..7) fresh at `t`: its clock in Hz, AY or YM levels. It plays from here (centred pans).
pub fn ayConfigure(t: u32, chip: u32, clock_hz: u24, ym: bool) bool {
    if (chip >= AY_CHIPS) return false;
    return push(t, AY_BASE + chip * 16 + 14, @as(u32, clock_hz) | @as(u32, @intFromBool(ym)) << 24);
}
/// AY register `reg` (0..13) of `chip` to `value` at `t`; 13 re-triggers the envelope, as on the chip.
pub fn ayWrite(t: u32, chip: u32, reg: u32, value: u8) bool {
    if (chip >= AY_CHIPS or reg > 13) return false;
    return push(t, AY_BASE + chip * 16 + reg, value);
}
/// The pans of `chip`'s channels A, B, C: k / 200 each (0 left, 100 centre, 200 right), equal-power or linear.
pub fn ayStereo(t: u32, chip: u32, a: u8, b: u8, c: u8, equal_power: bool) bool {
    if (chip >= AY_CHIPS or a > 200 or b > 200 or c > 200) return false;
    const v = @as(u32, a) | @as(u32, b) << 8 | @as(u32, c) << 16 | @as(u32, @intFromBool(equal_power)) << 24;
    return push(t, AY_BASE + chip * 16 + 15, v);
}
/// `chip`'s gain in the mix, Q15 (32768 = 1, the default).
pub fn ayGain(t: u32, chip: u32, q15: u16) bool {
    if (chip >= AY_CHIPS) return false;
    return push(t, AY_BASE + 0x80 + chip, q15);
}
/// Ask for a `mark` event carrying `arg` (24 bits on every host) when the sound side reaches `t` (a beat, a pattern row).
pub fn mark(t: u32, arg: u24) bool {
    return push(t, OP_MARK, arg);
}

/// The sound side's position on the cart's clock (what it has rendered), a frame or two old.
pub fn position() u32 {
    return word(W.pos).*;
}
pub fn anchored() bool {
    return word(W.anchored).* != 0;
}
/// Time to produce the command stamped `t`: it is within a lead of the sound side's position.
pub fn due(t: u32) bool {
    const ahead: i32 = @bitCast(t -% position());
    return ahead < @as(i32, @intCast(word(W.lead).*));
}

/// The next event the sound side sent back, oldest first.
pub fn pollEvent() ?Event {
    const tail = word(W.ev_tail).*;
    if (tail == word(W.ev_head).*) return null;
    const p: *volatile Event = @ptrCast(&block.events[tail % EV_CAP]);
    const e: Event = .{ .t = p.t, .kind = p.kind, .arg = p.arg, .seq = p.seq };
    word(W.ev_tail).* = tail +% 1;
    return e;
}

pub fn dropped() u32 {
    return word(W.dropped).*;
}
pub fn eventsLost() u32 {
    return word(W.ev_lost).*;
}
pub fn isOpen() bool {
    return attached;
}
/// Commands the ring takes now (a replay writes a whole tick or none of it).
pub fn room() u32 {
    if (!attached) return 0;
    return CAP - (word(W.head).* -% word(W.tail).*);
}
