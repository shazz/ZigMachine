// --------------------------------------------------------------------------
// PACING (the reference model's pacing.py): when does the next game frame
// start, in 50 Hz VBLs?
//
// JOUST has no VBL sync: a game frame lasts as long as its 18 calls take on
// the CPU, plus the OS interrupts that land during them. Every call counts its
// PURE CPU cycles (the 68000 instructions it executes); the Pacer inserts the
// interrupts as they fall due, as the harness's TOS does:
//   VBL every 160256 cycles costs 1200, Timer C every 40106 costs 200 (+300 on
//   every 4th tick: the Dosound tick), and the joystick packet arrives 4 ACIA
//   byte times + 800 after the Ikbdws trap starts, then costs 3 x 250 + 220.
// A key reaching the keyboard buffer costs two ACIA interrupts (make + break).
// --------------------------------------------------------------------------
const State = @import("state.zig");
const St = State.St;

pub const VBL_CYC: i64 = 512 * 313;
pub const TIMERC_CYC: i64 = @divFloor(8021247, 200);
pub const BAUD: i64 = 10267; // int(8021247 * 10 / 7812.5)
pub const VBL_COST: i64 = 1200;
pub const TIMERC_COST: i64 = 200;
pub const SND_COST: i64 = 300;
pub const ACIA_COST: i64 = 250;
pub const KEY_COST: i64 = 2 * ACIA_COST;
pub const IKBD_LAT: i64 = 4 * BAUD + 800; // Ikbdws($16) trap start -> packet complete
pub const JOY_PRE: i64 = 96; // jsr + clr.l + 3 pushes, up to the trap
pub const JOY_TRAP: i64 = 340 + 8; // trap (shim cost 300 + 40/byte) + addq.l #8,a7
pub const JOY_SERVICE: i64 = 3 * ACIA_COST + 220; // ACIA bytes + trampoline + joyvec + rte
pub const TST: i64 = 20;
pub const BEQ_T: i64 = 12;
pub const BEQ_N: i64 = 8;
pub const BRA_LOOP: i64 = 12; // bra.b $18 closing the main loop

/// A key on its way to the keyboard buffer: `at` is the cycle its ACIA
/// service starts (the harness's recorded cycle minus the 500 it costs).
pub const KeyEvent = struct { at: i64, code: u32 };

pub const Pacer = struct {
    t: i64,
    nv: i64,
    ntc: i64,
    tc: i64,
    vbl: i64,
    frame_vbl0: i64,
    keys: [64]KeyEvent,
    nkeys: u8,

    pub fn init(self: *Pacer, t: i64, nv: i64, ntc: i64, tc: i64, vbl: i64) void {
        self.t = t;
        self.nv = nv;
        self.ntc = ntc;
        self.tc = tc;
        self.vbl = vbl;
        self.frame_vbl0 = vbl;
        self.nkeys = 0;
    }

    /// Queue a key, in time order.
    pub fn addKey(self: *Pacer, at: i64, code: u32) void {
        if (self.nkeys == self.keys.len) return;
        var i: usize = self.nkeys;
        while (i > 0 and self.keys[i - 1].at > at) : (i -= 1) self.keys[i] = self.keys[i - 1];
        self.keys[i] = .{ .at = at, .code = code };
        self.nkeys += 1;
    }

    /// Service every interrupt due at or before `upto` (an instruction boundary).
    fn irq(self: *Pacer, st: *St, upto0: i64) void {
        var upto = upto0;
        while (true) {
            var c: i64 = 0;
            if (self.ntc <= upto and self.ntc <= self.nv) {
                self.ntc += TIMERC_CYC;
                self.tc += 1;
                c = TIMERC_COST;
                if (@mod(self.tc, 4) == 0) {
                    c += SND_COST;
                    st.dosoundTick();
                }
            } else if (self.nv <= upto) {
                self.nv += VBL_CYC;
                self.vbl += 1;
                c = VBL_COST;
                st.onVbl();
            } else if (self.nkeys > 0 and self.keys[0].at <= upto) {
                st.keyPush(self.keys[0].code);
                for (1..self.nkeys) |i| self.keys[i - 1] = self.keys[i];
                self.nkeys -= 1;
                c = KEY_COST;
            } else return;
            self.t += c;
            upto += c;
        }
    }

    /// Pure CPU work, interrupts inserted as they fall due.
    pub fn run(self: *Pacer, st: *St, cycles: i64) void {
        self.t += cycles;
        self.irq(st, self.t);
    }

    /// Call 5: pre, trap, the wait loop at instruction granularity, then `post`
    /// cycles (from the packet read to the rts, incl. the two $1E68 calls).
    pub fn joystick(self: *Pacer, st: *St, post: i64) void {
        self.run(st, JOY_PRE);
        const event = self.t + IKBD_LAT;
        self.run(st, JOY_TRAP);
        self.waitPacket(st, event);
        self.run(st, post);
    }

    /// tst.l $0E74 / beq.b until the IKBD packet has come in.
    pub fn waitPacket(self: *Pacer, st: *St, event: i64) void {
        var at_tst = true;
        while (true) {
            if (event <= self.t) {
                self.t += JOY_SERVICE;
                self.run(st, if (at_tst) TST + BEQ_N else BEQ_T + TST + BEQ_N);
                break;
            }
            self.run(st, if (at_tst) TST else BEQ_T);
            at_tst = !at_tst;
        }
    }

    /// VBLs elapsed during this frame: the `bra $18` after call 17 (12 cycles),
    /// then the interrupts due at the frame boundary are serviced.
    pub fn endFrame(self: *Pacer, st: *St) i64 {
        self.run(st, BRA_LOOP);
        return self.frameVbls();
    }

    /// The VBLs since the last frame boundary (a frame left by jmp $18 / $6
    /// has no closing bra).
    pub fn frameVbls(self: *Pacer) i64 {
        const n = self.vbl - self.frame_vbl0;
        self.frame_vbl0 = self.vbl;
        return n;
    }
};
