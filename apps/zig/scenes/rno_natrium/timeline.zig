// --------------------------------------------------------------------------
// NATRIUM's sequencer ($AA9A..$BEB8), as a state machine driven by the VBL.
//
// The original is one straight-line program: each part busy-loops on the
// global counter $144AC (a long the VBL bumps at 50 Hz, together with the word
// $144A0 that parts reset), calling an effect, waiting for a VBL, or checking a
// step count $144A4. Here one tick() is one VBL: it bumps both counters, then
// runs the program until the point where the 68000 would next wait for a VBL.
// Every part boundary is the original's compare constant.
//
// What a 68000 cycle count decided, and a state machine has to be told. The
// RAM snapshots measure it (each figure below is theirs):
//   * the $D670 dot tunnel runs one pass a VBL (F = 19, 20, 21 in a row);
//   * the $DDEC tunnel does NOT: the word it counts its calls in reads $BA at
//     counter $700, 186 calls in the 205 VBLs since f = 0 -- ~1.10 VBL a call,
//     so about one frame in ten is skipped. Modelled as a fixed cost of
//     DDEC_COST/1024 VBL (the calls land on f = 203 then 204, as the snapshot's
//     two fields do);
//   * $D7F6 and $DB14 sync to the VBL, one call each. The field each frame
//     lands in says an ODD number of wobble calls overran into a second VBL
//     before $A00 (where is not recorded: the port takes it at the first
//     call), and, counting on from there, an even number of rotozoom calls
//     before $1C00 (the port models none);
//   * the env objects render every 3 VBLs (198/201/204 and 150/153/156);
//   * $C06E (texture -> four 64 KB C2P arrays) takes 19 VBLs: the wobble's
//     $144A0 = 237 at counter $A00 fixes it, and the box shows the last tunnel
//     frame meanwhile;
//   * $E7C2 (fill both screens) crosses one VBL: counter = $1201 + f in the
//     twister, which is what makes both buffers match the $1500 snapshot;
//   * part 7's init overruns $1B00: $144A0 = $BD at counter $1C00 puts the
//     zoom-in at $1B0F. The explicit waits account for 21 of those VBLs; the
//     other 4 (P7_COPIES) are $E980 + $C722 + $BF1A and the back-buffer
//     rotozoom draws, calibrated to the snapshot rather than cycle-counted;
//   * the twister's buffers are one swap away from a draw-every-VBL run at
//     $1500, $1900 and $1C00: one $E094 call overran (parts_b.zig).
// A live log of $144A0 at each call's entry would replace every calibrated
// number here with a measured one.
// --------------------------------------------------------------------------
const A = @import("assets.zig");
const st = @import("st.zig");
const envmap = @import("envmap.zig");
const parts_a = @import("parts_a.zig");
const parts_b = @import("parts_b.zig");

pub const END: u32 = 0x1E00; // the original quits to the desktop here
pub const C06E_VBLS: u16 = 19;
pub const P7_COPIES: u16 = 4;
pub const VBL_UNITS: u32 = 1024;
pub const DDEC_COST: u32 = 1129; // 1.1025 VBL a call: 186 calls in 205 VBLs
pub const DDEC_PHASE: u32 = 205; // the first call starts after the zoom's copy

/// $5F400 and $67400.
pub var screens: [2]st.Screen = undefined;

pub const State = enum {
    // parts_a
    wait_start,
    p1_wipe,
    p1_rno,
    p1_natrium,
    p1_erase,
    p1_clear,
    p2_init,
    p2_init_b,
    p2_wait,
    p2_tunnel_start,
    p2_tunnel,
    p2_wobble_start,
    p2_wobble_compute,
    p2_wobble,
    p2_out,
    p3_init,
    p3_c2p_a,
    p3_c2p_b,
    p3_wait,
    zoom_compute,
    zoom_copy,
    env_start,
    env_loop,
    // parts_b
    p3_out,
    p4_init,
    p4_wait,
    p4_pre,
    p4_strip_wait,
    p4_strip,
    p4_wipe_wait,
    p4_wipe,
    p4_end,
    p5_first,
    p5_loop,
    p6_init,
    p6_init_b,
    p6_c2p_a,
    p6_c2p_b,
    p6_wait,
    p6_curtain,
    p6_out,
    p7_init,
    p7_init_b,
    p7_back_a,
    p7_back_b,
    p7_wait,
    p7_roto_start,
    p7_roto_compute,
    p7_roto,
    p7_out,
    p7_end,
};
const FIRST_B = @intFromEnum(State.p3_out);

pub const Seq = struct {
    f: u16, // $144A0: per-part frame counter, reset by parts
    counter: u32, // $144AC: the global timeline
    step: u16, // $144A4: per-sub-part step
    flag: st.Flag, // $144B8: the shared field parity
    front: u1, // which of `screens` $CA5C points at ($CA60 is the other)
    shown: u1, // the video base ($FF8201)
    pal: [16]u16,
    state: State,
    stall: u16, // VBLs a routine is still busy for
    // work split across a VBL wait: the half before it, and what comes after
    zoom_out: bool,
    zoom_par: u1,
    table: [200]u8,
    after: State,
    pending_f: u16, // the f $D7F6 / $DB14 built their tables from
    overrun: bool, // the one $D7F6 call still to overrun its VBL
    busy: u32, // $DDEC: time until its next call, in 1/1024 VBL
    env: envmap.Object,
    env_limit: u32,
    env_after: State,
    strip: u8,
    finished: bool,

    /// The program's start: $C90C clears both screens and sets $14360 (black),
    /// $C47E converts NATRIUM into the back buffer. Every field set here:
    /// demo_main holds the cart as undefined bytes.
    pub fn reset(self: *Seq) void {
        self.f = 0;
        self.counter = 0;
        self.step = 0;
        self.flag = .{ .v = 0 };
        self.front = 0;
        self.shown = 0;
        self.setPal(A.PAL_BLACK);
        self.state = .wait_start;
        self.stall = 0;
        self.zoom_out = false;
        self.zoom_par = 0;
        @memset(&self.table, 0);
        self.after = .wait_start;
        self.pending_f = 0;
        self.overrun = false;
        self.busy = 0;
        self.env = envmap.object(A.cube);
        self.env_limit = 0;
        self.env_after = .wait_start;
        self.strip = 0;
        self.finished = false;
        for (&screens) |*s| st.clear(s);
        st.fromIlbm(self.back(), A.natrium_rows, A.LOGO_TOP, A.LOGO_ROWS);
    }

    /// One VBL ($C04E: $144A0 += 1, $144AC += 1), then the program up to its
    /// next wait.
    pub fn tick(self: *Seq) void {
        if (self.finished) return;
        self.f +%= 1;
        self.counter += 1;
        if (self.stall > 0) {
            self.stall -= 1;
            if (self.stall > 0) return;
        }
        var guard: usize = 0;
        while (!self.run()) {
            guard += 1;
            if (guard > 16) break; // a state chain never runs this long; do not hang the frame
        }
    }

    /// Runs the current state. True = the program now waits for the next VBL.
    fn run(self: *Seq) bool {
        return if (@intFromEnum(self.state) < FIRST_B) parts_a.run(self) else parts_b.run(self);
    }

    pub fn frontBuf(self: *Seq) *st.Screen {
        return &screens[self.front];
    }
    pub fn back(self: *Seq) *st.Screen {
        return &screens[self.front ^ 1];
    }
    pub fn shownBuf(self: *const Seq) *const st.Screen {
        return &screens[self.shown];
    }

    /// movem.l <addr>, d0-d7 / movem.l d0-d7, $FF8240
    pub fn setPal(self: *Seq, addr: u32) void {
        for (&self.pal, 0..) |*c, i| c.* = A.pal(addr, i);
    }

    /// Start a $D472 (in) or $D570 (out) run of 52 calls, then go to `after`.
    pub fn zoom(self: *Seq, out: bool, after: State) void {
        self.step = 0;
        self.zoom_out = out;
        self.after = after;
        self.state = .zoom_compute;
    }

    /// Start an env-object loop ($EE5A + $EB42) that runs until `limit`.
    pub fn envLoop(self: *Seq, limit: u32, after: State) void {
        self.env_limit = limit;
        self.env_after = after;
        self.state = .env_start;
    }
};
