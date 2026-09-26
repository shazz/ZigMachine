// --------------------------------------------------------------------------
// The whole program, run the way the 68000 runs it:
//   $0000  jsr $86 (start-up), then $0006: jsr $618 (reset), jsr $AEC (the
//          title), jsr $4B8 (the new-game screen), then the main loop at
//          $0018: the 18 calls and bra $18, forever.
// R (jmp $6) and the end of a high-score name entry go back to $0006; fire
// after GAME OVER starts a new game from inside call 5 (jmp $18); ^C quits.
//
// PACING. There is no Vsync: a frame lasts as many 50 Hz VBLs as its cycles
// take (the pacer). run(limit) advances the machine while its VBL count has
// not passed `limit` -- the scene derives it from the host's elapsed time --
// and the waits that last as long as the player likes (the title, the P
// pause, the name entry) stop there and carry on at the next call.
// --------------------------------------------------------------------------
const State = @import("state.zig");
const cyc = @import("cyc.zig");
const calls = @import("calls.zig");
const boot = @import("boot.zig");
const title = @import("title.zig");
const input = @import("flow_input.zig");
const gameover = @import("flow_gameover.zig");
const newgame = @import("flow_newgame.zig");
const name = @import("flow_name.zig");
const St = State.St;
const Cy = cyc.Cy;

pub const Mode = enum { title, frame, pause, name_entry, quit };

pub const Machine = struct {
    st: St,
    mode: Mode,
    /// the next of the 18 calls in the frame
    k: usize,
    title: title.Title,
    c6: input.Call6,
    ne: name.NameEntry,
    /// XBIOS Random's state
    seed: u32,
    /// the joystick bytes the IKBD would send now: [P1 (port 1), P2 (port 0)]
    joy: [2]u8,
    /// game frames completed, and the VBLs the last one took
    frames: u64,
    frame_vbls: i64,

    /// Power on: the image loaded, the start-up and $0618 run, the title up.
    pub fn reset(self: *Machine, seed: u32) void {
        const st = &self.st;
        st.init();
        st.regs[15] = boot.STACK_TOP - 8;
        self.seed = seed;
        self.joy = .{ 0, 0 };
        self.frames = 0;
        self.frame_vbls = 0;
        self.k = 0;
        var cy = Cy.init(st);
        cy.one(0x0000); // jsr $86
        boot.init(st, &cy);
        cy.flush();
        self.fromSix();
    }

    /// $0006: jsr $618; jsr $AEC.
    fn fromSix(self: *Machine) void {
        const st = &self.st;
        var cy = Cy.init(st);
        cy.one(0x0006); // jsr $618
        newgame.reset(st, &cy, &self.seed);
        cy.one(0x000C); // jsr $aec
        cy.flush();
        title.begin(st, &self.title);
        self.mode = .title;
    }

    /// The title chose 1 or 2 players: jsr $4B8, then the main loop.
    fn afterTitle(self: *Machine) void {
        const st = &self.st;
        var cy = Cy.init(st);
        cy.one(0x0012); // jsr $4b8
        newgame.setup(st, &cy);
        cy.flush();
        self.startFrame();
    }

    fn startFrame(self: *Machine) void {
        self.st.pacer.frame_vbl0 = self.st.pacer.vbl;
        self.mode = .frame;
        self.k = 0;
    }

    /// Advance while the machine's VBL count has not passed `limit`. With
    /// `one_frame`, stop at the next frame boundary ($0018) instead.
    pub fn run(self: *Machine, limit: i64, one_frame: bool) void {
        const st = &self.st;
        while (true) {
            switch (self.mode) {
                .quit => return,
                .title => switch (title.run(st, &self.title, &self.joy, limit)) {
                    .suspended => return,
                    .quit => self.mode = .quit,
                    .one, .two => {
                        self.afterTitle();
                        if (one_frame) return;
                    },
                },
                .pause => {
                    if (input.pause(st, &self.c6, limit) == .suspended) return;
                    self.finishCall();
                },
                .name_entry => {
                    if (name.loop(st, &self.ne, &self.joy, limit) == .suspended) return;
                    st.exit = .none;
                    st.regs[15] = boot.STACK_TOP - 8;
                    self.frame_vbls = st.pacer.frameVbls();
                    self.frames += 1;
                    self.fromSix(); // jmp $6
                },
                .frame => {
                    if (self.k == 0 and !one_frame and st.pacer.vbl > limit) return;
                    if (self.step(limit) and one_frame and self.mode == .frame) return;
                },
            }
        }
    }

    /// One call of the frame. True when the frame ended.
    fn step(self: *Machine, limit: i64) bool {
        const st = &self.st;
        const k = self.k;
        st.cycles = -1;
        st.clocked = 0;
        switch (k) {
            5 => switch (input.call_1e10_joystick(st, self.joy)) {
                .done => st.pacer.joystick(st, st.cycles),
                .new_game => |pre| {
                    if (newgame.new_game(st, pre, &self.seed, &self.ne) == .name_entry) {
                        self.mode = .name_entry;
                        return false;
                    }
                    // jmp $18: the frame ends here, without its bra
                    st.regs[15] = boot.STACK_TOP - 8;
                    self.frame_vbls = st.pacer.frameVbls();
                    self.frames += 1;
                    st.exit = .none;
                    self.startFrame();
                    return true;
                },
            },
            6 => {
                if (input.call_1c92_keyboard(st, &self.c6, limit) == .suspended) {
                    self.mode = .pause;
                    return false;
                }
            },
            17 => if (gameover.call_450e_game_over(st, &self.ne)) {
                self.mode = .name_entry;
                return false;
            } else st.pacer.run(st, st.cycles - st.clocked),
            else => _ = calls.runCall(st, k, &.{ .joy = self.joy }),
        }
        return self.afterCall();
    }

    /// The pause ended: call 6's rest of the cycles, then the next call.
    fn finishCall(self: *Machine) void {
        const st = &self.st;
        st.pacer.run(st, st.cycles - st.clocked);
        self.mode = .frame;
        _ = self.afterCall();
    }

    fn afterCall(self: *Machine) bool {
        const st = &self.st;
        // jmp $6 / jmp $18 leave with the stack as main has it (the model's
        // exit paths adjust a7 from the call's entry value; the 68000 pops the
        // return addresses it pushed)
        if (st.exit == .restart or st.exit == .jmp18) st.regs[15] = boot.STACK_TOP - 8;
        switch (st.exit) {
            .none => {},
            .quit => {
                self.mode = .quit;
                return true;
            },
            .restart => { // jmp $6
                st.exit = .none;
                self.frame_vbls = st.pacer.frameVbls();
                self.frames += 1;
                self.fromSix();
                return true;
            },
            .jmp18 => {
                st.exit = .none;
                self.frame_vbls = st.pacer.frameVbls();
                self.frames += 1;
                self.startFrame();
                return true;
            },
        }
        self.k += 1;
        if (self.k < calls.NCALLS) return false;
        self.frame_vbls = st.pacer.endFrame(st); // bra $18
        self.frames += 1;
        self.startFrame();
        return true;
    }
};
