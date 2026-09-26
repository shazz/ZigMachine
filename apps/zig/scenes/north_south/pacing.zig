// --------------------------------------------------------------------------
// How many 50 Hz VBLs a battle frame spans (the rip's model/pacing.py).
//
// The loop ends with trap #5 (flat $135D6): flip the screen, then busy-wait
// for the next VBL. So a frame lasts floor((phase + busy) / VBL) + 1 VBLs:
//   busy  = the frame's own 68000 work (cost.zig's fitted linear model) plus
//           the interrupts that land in it — VBLs, Timer C (200 Hz), and the
//           Timer A digi player, one interrupt per sample byte (6-10 kHz),
//           which is simulated here in cycle time with the sequencer below,
//           so the sound's CPU load follows which samples play when;
//   phase = where in the VBL the loop top was reached.
// Every value is an f64 computed in the model's order, so the VBL counts are
// the model's (96.5 % of them are the real game's).
// --------------------------------------------------------------------------
const A = @import("assets.zig");
const cost = @import("cost.zig");

const VBL: f64 = 512 * 313;
const TIMERC: f64 = @divTrunc(8021247, 200); // the model's integer //
const CPU_HZ: f64 = 8021247;
const MFP_HZ: f64 = 2457600;
// pacing_params.json
const C_VBL: f64 = 2654;
const C_VBL_START: f64 = 500;
const C_TC: f64 = 200;
const C_IRQ: f64 = 296;
const C_IRQ_STOP: f64 = 207;
const TAIL: f64 = 164;
const PLAY_BASE: f64 = 149707;
/// Where frame 0 starts after a VBL: the setup's length, per field.
const PHASE0 = [3]f64{ 142476, 137344, 142492 };

const MAX_PLAYS = 64;

/// The digi player as the pacing clock sees it: $49D4 (VBL sequencer) and
/// $417E (Timer A), sound/SPEC.md.
pub const Sequencer = struct {
    active: bool,
    seq: u16, // which sequence
    index: u16,
    loop: bool,
    playing: bool,
    left: i32, // bytes still to be read, including the 0
    period: f64, // Timer A period in CPU cycles
    next_irq: ?f64,
    cut: bool,

    pub fn reset(self: *Sequencer) void {
        self.* = .{ .active = false, .seq = 0, .index = 0, .loop = false, .playing = false, .left = 0, .period = 0, .next_irq = null, .cut = false };
    }

    /// $4CB6 with the flags the battle uses ($81/$82/$84/$88).
    pub fn play(self: *Sequencer, n: u16, flags: u16) void {
        if (n >= nseq()) return;
        self.active = false;
        if (self.playing) self.cut = true; // the next interrupt reads 0 and stops
        if (flags & 0x80 != 0) {
            self.index = 0;
            self.seq = n;
            self.loop = flags & 0x20 != 0;
            self.active = true;
        }
    }

    /// $49D4: true if a sample was started (the handler then costs more).
    fn vbl(self: *Sequencer, now: f64) bool {
        if (!self.active or self.playing) return false;
        var smp = seqByte(self.seq, 2 * self.index);
        var rate: u16 = if (smp != 0xFF) seqByte(self.seq, 2 * self.index + 1) else 0;
        if (smp == 0xFF) {
            if (!self.loop) {
                self.active = false;
                return false;
            }
            self.index = 0;
            smp = seqByte(self.seq, 0);
            rate = seqByte(self.seq, 1);
        }
        self.index += 1;
        self.playing = true;
        self.cut = false;
        self.left = smpLen(smp);
        self.period = @as(f64, @floatFromInt(4 * @as(i64, if (rate != 0) rate else 256) * 8021247)) / MFP_HZ;
        self.next_irq = now + self.period;
        return true;
    }

    /// One Timer A interrupt: true if it was the stopping one (byte 0).
    fn irq(self: *Sequencer) bool {
        self.next_irq = self.next_irq.? + self.period;
        if (self.cut or self.left <= 1) {
            self.playing = false;
            self.cut = false;
            self.next_irq = null;
            return true;
        }
        self.left -= 1;
        return false;
    }
};

fn nseq() u16 {
    return A.be16(A.sound, 0);
}
fn smpLen(s: u16) i32 {
    return A.be16(A.sound, 4 + 2 * @as(usize, s));
}
fn seqByte(n: u16, i: u16) u16 {
    const nsmp: usize = A.be16(A.sound, 2);
    const body = 4 + 2 * nsmp + 2 * @as(usize, nseq());
    return A.sound[body + A.be16(A.sound, 4 + 2 * nsmp + 2 * @as(usize, n)) + i];
}

const Play = struct { off: f64, n: u16, flags: u16 };

pub const Pacer = struct {
    now: ?f64,
    next_vbl: f64,
    next_tc: f64,
    last_vbls: u32,
    vbl_count: u32,
    plays: [MAX_PLAYS]Play,
    nplays: usize,
    snd: Sequencer,

    pub fn reset(self: *Pacer) void {
        self.now = null;
        self.next_vbl = VBL;
        self.next_tc = 0;
        self.last_vbls = 0;
        self.vbl_count = 0;
        self.nplays = 0;
        self.snd.reset();
    }

    /// A play_seq call: its offset in the frame, from the counters so far.
    pub fn play(self: *Pacer, snapshot: *const cost.Cost, n: u16, flags: u16) void {
        if (self.nplays == MAX_PLAYS) return;
        self.plays[self.nplays] = .{ .off = PLAY_BASE + snapshot.work() - cost.CONST, .n = n, .flags = flags };
        self.nplays += 1;
    }

    fn nextEvent(self: *const Pacer, with_irq: bool) f64 {
        var nxt = @min(self.next_vbl, self.next_tc);
        if (with_irq) if (self.snd.next_irq) |i| {
            nxt = @min(nxt, i);
        };
        return nxt;
    }

    /// trap #5: run the frame's work against the interrupts, then wait for the VBL.
    pub fn frameDone(self: *Pacer, field: usize, c: *const cost.Cost) void {
        if (self.now == null) {
            const ph = PHASE0[field];
            self.now = ph;
            self.next_tc = ph + 1000;
        }
        self.vbl_count = 0;
        const w = c.work();
        sortPlays(self.plays[0..self.nplays]);
        var head: usize = 0;
        const plays = self.plays[0..self.nplays];
        var done: f64 = 0;
        var t = self.now.?;
        while (true) {
            var target = if (head < plays.len) plays[head].off else w;
            target = @max(target, done);
            const nxt = self.nextEvent(self.snd.playing);
            if (t + (target - done) <= nxt) {
                t += target - done;
                done = target;
                if (head < plays.len and done >= plays[head].off) {
                    const p = plays[head];
                    head += 1;
                    while (self.snd.playing) { // busy-wait until the cut interrupt
                        t = @max(t, self.nextEvent(true));
                        t = self.interrupt(t);
                    }
                    self.snd.play(p.n, p.flags);
                    continue;
                }
                if (done >= w and head == plays.len) break;
                continue;
            }
            done += nxt - t;
            t = self.interrupt(nxt);
        }
        self.nplays = 0;
        while (true) {
            const nxt = self.nextEvent(self.snd.playing);
            const is_vbl = nxt == self.next_vbl;
            t = self.interrupt(@max(t, nxt));
            if (is_vbl) break;
        }
        t += TAIL;
        self.last_vbls = self.vbl_count;
        self.now = t;
    }

    /// Serve the earliest due interrupt at time t; returns the time after it.
    fn interrupt(self: *Pacer, t: f64) f64 {
        if (self.snd.playing) if (self.snd.next_irq) |i| {
            if (i <= t and i <= @min(self.next_vbl, self.next_tc)) {
                return t + (if (self.snd.irq()) C_IRQ_STOP else C_IRQ);
            }
        };
        if (self.next_tc <= t and self.next_tc <= self.next_vbl) {
            self.next_tc += TIMERC;
            return t + C_TC;
        }
        self.next_vbl += VBL;
        self.vbl_count += 1;
        const started = self.snd.vbl(t);
        return t + C_VBL + (if (started) C_VBL_START else 0);
    }
};

/// Stable insertion sort by offset (Python's sorted).
fn sortPlays(p: []Play) void {
    var i: usize = 1;
    while (i < p.len) : (i += 1) {
        const v = p[i];
        var j = i;
        while (j > 0 and p[j - 1].off > v.off) : (j -= 1) p[j] = p[j - 1];
        p[j] = v;
    }
}
