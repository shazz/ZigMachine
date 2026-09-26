// --------------------------------------------------------------------------
// The title ($0AEC-$0C92, $0C94): transcribed from the 68000 with its cycles
// (the reference model starts after it). Setpalette($0D10), JOUST.MUR onto a
// cleared screen, "ONE OR TWO PLAYERS (1/2)?", the high score (printed only
// when HIGH.SCO loaded: $86DA), the credits, then round after round: cycle
// the palette ($0C94 + the rotation of colours 4,6,3,8,9,10), Setpalette,
// the title tune (SFX 14) whenever the chip is quiet, 400 Bconstat polls, and
// an IKBD joystick interrogate. '1' / '2' / fire start the game; ^C quits.
//
// It waits for the player, so it runs across host frames: run() suspends at
// the top of a poll once the machine is due to hand back to the host.
// --------------------------------------------------------------------------
const State = @import("state.zig");
const cyc = @import("cyc.zig");
const pacing = @import("pacing.zig");
const sound = @import("sound.zig");
const keys = @import("keys.zig");
const text = @import("flow_text.zig");
const score = @import("flow_score.zig");
const input = @import("flow_input.zig");
const gameover = @import("flow_gameover.zig");
const newgame = @import("flow_newgame.zig");
const St = State.St;
const V = State.V;
const Cy = cyc.Cy;
const BASE = State.BASE;

pub const Title = struct {
    cy: Cy,
    at: enum { cycle, poll },
};

pub const Result = enum { suspended, one, two, quit };

/// $0C84: Setpalette($0D10).
fn setpal(st: *St, cy: *Cy) void {
    cy.run(0x0C84, 0x0C8E);
    newgame.setpalette(st, 0x0D10);
    cy.add(300);
    cy.run(0x0C90, 0x0C94);
}

/// $0AEC..$0B5C: everything before the first round. `cy` is the caller's
/// counter, after its jsr.
pub fn begin(st: *St, t: *Title) void {
    t.cy = Cy.init(st);
    const cy = &t.cy;
    cy.one(0x0AEC); // bsr.w $c84
    setpal(st, cy);
    cy.run(0x0AF0, 0x0AF6); // clr.w -(a7), bsr.w $2e8
    gameover.clear_screen(st, cy, 0);
    cy.run(0x0AF6, 0x0B04);
    const scr = st.g(V.screen_base);
    var i: i64 = 0;
    while (i < 32000) : (i += 4) {
        st.wr(scr + i, 4, st.rd(BASE + 0x13E58 + i, 4));
        cy.run(0x0B04, 0x0B0C);
        _ = cy.br(0x0B0C, i + 4 != 32000);
    }
    st.set_a(0, BASE + 0x1BB58);
    st.set_a(1, scr + 32000);
    const lines = [_][3]i64{ .{ 0x0B0E, 0x0F, 0x8705 }, .{ 0x0B24, 0x02, 0x86D3 }, .{ 0x0B3A, 0x01, 0x8727 } };
    for (lines) |l| {
        st.wb(0x0E7D, l[1]);
        cy.run(l[0], l[0] + 0x0E); // move.b #ink,$e7d; move.l #rec,-(a7)
        cy.one(l[0] + 0x0E); // bsr.w $73e
        text.print_text(st, cy, BASE + l[2]);
        cy.one(l[0] + 0x12); // adda.w #4,a7
    }
    cy.run(0x0B50, 0x0B5A);
    cy.flush();
    sound.dosound_silence(st); // Dosound($157D)
    cy.add(300);
    cy.one(0x0B5C);
    t.at = .cycle;
}

/// $0C94: the colour-cycling step on title colour 4 ($0D18).
fn cycle(st: *St, cy: *Cy) void {
    cy.run(0x0C94, 0x0CA4);
    st.ww(0x0D92, st.rw(0x0D92) + 1);
    var d4 = st.rw(0x0D92) & 0x700;
    if (!cy.br(0x0CA4, d4 != 0)) {
        cy.run(0x0CA6, 0x0CB2);
        d4 = 0x100;
        st.ww(0x0D92, 0x100);
    }
    cy.run(0x0CB2, 0x0CD6);
    const c = st.rw(0x0D18);
    var d0 = c & 0xF;
    var d1 = (c & 0xF0) >> 4;
    var d2 = (c & 0xF00) >> 8;
    var d3 = d0;
    if (!cy.br(0x0CD6, d3 != 0)) {
        cy.one(0x0CD8);
        d3 = d1;
        if (!cy.br(0x0CDA, d3 != 0)) {
            cy.one(0x0CDC);
            d3 = d2;
            if (!cy.br(0x0CDE, d3 != 0)) {
                cy.one(0x0CE0); // rts
                setRegs(st, d0, d1, d2, d3, d4);
                return;
            }
        }
    }
    cy.run(0x0CE2, 0x0CE8);
    d0 = 0;
    d1 = 0;
    d2 = 0;
    const tests = [_][2]i64{ .{ 0x0CE8, 0xA }, .{ 0x0CF0, 9 }, .{ 0x0CF8, 8 } };
    for (tests, 0..) |tb, k| {
        cy.one(tb[0]);
        if (!cy.br(tb[0] + 4, !State.bit(d4, tb[1]))) {
            cy.one(tb[0] + 6);
            switch (k) {
                0 => d2 = d3,
                1 => d1 = d3,
                else => d0 = d3,
            }
        }
    }
    cy.run(0x0D00, 0x0D0E);
    d2 = (d2 << 8) & 0xFFFF;
    d0 |= d2;
    d1 = (d1 << 4) & 0xFFFF;
    d0 |= d1;
    st.ww(0x0D18, d0);
    cy.one(0x0D0E);
    setRegs(st, d0, d1, d2, d3, d4);
}

fn setRegs(st: *St, d0: i64, d1: i64, d2: i64, d3: i64, d4: i64) void {
    st.set_d(0, d0, 2);
    st.set_d(1, d1, 2);
    st.set_d(2, d2, 2);
    st.set_d(3, d3, 2);
    st.set_d(4, d4, 2);
}

/// $0B60..$0BBE: one round's palette work and the title tune.
fn round(st: *St, cy: *Cy) void {
    cy.one(0x0B60); // bsr.w $c94
    cycle(st, cy);
    cy.run(0x0B64, 0x0BA2);
    const d0 = st.rw(0x0D24);
    st.ww(0x0D24, st.rw(0x0D22));
    st.ww(0x0D22, st.rw(0x0D20));
    st.ww(0x0D20, st.rw(0x0D16));
    st.ww(0x0D16, st.rw(0x0D1C));
    st.ww(0x0D1C, st.rw(0x0D18));
    st.ww(0x0D18, d0);
    st.set_d(0, d0, 2);
    cy.one(0x0BA2); // bsr.w $c84
    setpal(st, cy);
    cy.flush();
    input.call_0ac8_sfx_prio(st); // bsr.w $ac8 (the same 20-cycle call as the jsr)
    cy.run(0x0BAA, 0x0BB2);
    if (!cy.br(0x0BB2, st.g(V.sfx_prio) != 0x10)) {
        cy.run(0x0BB4, 0x0BB8);
        cy.one(0x0BB8); // bsr.w $a94
        score.call_sfx(st, cy, 14);
        cy.one(0x0BBC);
    }
    st.ww(0x0E5A, 0x190);
    cy.one(0x0BBE);
}

/// The rounds, from where the title left off. `joy` = [P1, P2] as the IKBD
/// would deliver them now.
pub fn run(st: *St, t: *Title, joy: *const [2]u8, limit: i64) Result {
    const cy = &t.cy;
    while (true) {
        if (t.at == .cycle) {
            round(st, cy);
            t.at = .poll;
        }
        if (st.pacer.vbl >= limit) return .suspended;
        // $0BC6: Bconstat
        cy.run(0x0BC6, 0x0BCE);
        var d0 = keys.bconstat(st, cy);
        st.regs[0] = d0;
        cy.run(0x0BD0, 0x0BD6);
        if (cy.br(0x0BD6, d0 & 0x80 != 0)) {
            // $0C16: Bconin
            cy.run(0x0C16, 0x0C1E);
            d0 = keys.bconin(st, cy);
            st.regs[0] = d0;
            cy.run(0x0C20, 0x0C28);
            if (cy.br(0x0C28, d0 & 0xFF == 3)) {
                cy.flush();
                return .quit;
            }
            cy.one(0x0C2C);
            if (cy.br(0x0C30, d0 & 0xFFFF == 0x31)) return start(st, cy, false);
            cy.one(0x0C32);
            if (!cy.br(0x0C36, d0 & 0xFFFF != 0x32)) return start(st, cy, true);
            continue;
        }
        cy.run(0x0BD8, 0x0BDE);
        st.ww(0x0E5A, st.rw(0x0E5A) - 1);
        if (cy.br(0x0BDE, st.rw(0x0E5A) != 0)) continue;
        // $0BE0: the joystick
        st.wl(0x0E74, 0);
        cy.run(0x0BE0, 0x0BF2);
        cy.flush();
        const event = st.pacer.t + pacing.IKBD_LAT;
        cy.add(340); // trap #14 Ikbdws (1 byte)
        cy.one(0x0BF4); // addq.l #8,a7
        cy.flush();
        st.pacer.waitPacket(st, event);
        st.wl(0x0E74, 0x0E40);
        cy.run(0x0BFE, 0x0C08);
        const d1 = (@as(i64, joy[1]) | joy[0]) & 0xFF; // j0 (port 0 = P2) | j1 (port 1 = P1)
        st.set_d(1, d1, 1);
        st.set_a(0, 0x0E41);
        if (cy.br(0x0C08, d1 & 0x80 == 0)) {
            t.at = .cycle;
            continue;
        }
        cy.one(0x0C0C);
        if (cy.br(0x0C12, st.g(V.two_player) == 0)) return start(st, cy, false);
        cy.one(0x0C14);
        return start(st, cy, true);
    }
}

/// $0C38 (two) / $0C5C (one) .. $0C82.
fn start(st: *St, cy: *Cy, two: bool) Result {
    if (two) {
        st.s(V.two_player, 1);
        st.s(V.players, 2);
        st.set_a(0, BASE + 0x0FF2);
        st.wb(0x0FF2 + 0x44, 0x30);
        st.wb(0x0FF2 + 0x4C, 4);
        cy.run(0x0C38, 0x0C5C);
    } else {
        st.s(V.two_player, 0);
        st.ww(0x0FF2, 0);
        st.s(V.players, 1);
        cy.run(0x0C5C, 0x0C70);
    }
    st.set_a(0, BASE + 0x0FA4);
    st.wb(0x0FA4 + 0x44, 0x30);
    st.wb(0x0FA4 + 0x4C, 4);
    cy.run(0x0C70, 0x0C84); // ... rts
    cy.flush();
    return if (two) .two else .one;
}
