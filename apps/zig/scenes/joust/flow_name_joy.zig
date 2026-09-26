// --------------------------------------------------------------------------
// The name entry's joystick poll $46CC (the model's d_gameover._joystick):
// an IKBD interrogate and its busy-wait, then up/down change the letter,
// left/right move the cursor, fire ends the entry.
// --------------------------------------------------------------------------
const State = @import("state.zig");
const cyc = @import("cyc.zig");
const pacing = @import("pacing.zig");
const keys = @import("keys.zig");
const St = State.St;
const Cy = cyc.Cy;
const BASE = State.BASE;
const P2 = State.P2;
const s8 = State.s8;
pub const Status = enum { suspended, restart };
const back = @import("flow_name.zig");

/// $46E2: tst.l $e74 / beq.b until the IKBD packet (IKBD_LAT after the trap
/// started); keys that arrive meanwhile are serviced at the loop's
/// instruction boundaries.
pub fn joy_wait(st: *St, cy: *Cy) void {
    cy.flush();
    const p = &st.pacer;
    const event = p.t + pacing.IKBD_LAT;
    cy.add(340); // trap (Ikbdws, 1 byte) ...
    cy.one(0x46E0); // ... addq.l #8,a7
    deliver(st, cy);
    var at_tst = true;
    while (true) {
        if (event <= p.t) {
            p.t += pacing.JOY_SERVICE; // ACIA bytes + trampoline + joyvec (masked)
            cy.add(if (at_tst) pacing.TST + pacing.BEQ_N else pacing.BEQ_T + pacing.TST + pacing.BEQ_N);
            break;
        }
        cy.add(if (at_tst) pacing.TST else pacing.BEQ_T);
        at_tst = !at_tst;
        deliver(st, cy);
    }
}

pub fn deliver(st: *St, cy: *Cy) void {
    cy.flush();
    st.pacer.run(st, 0);
}

/// $46CC. True when it left the call (fire: jmp $6).
pub fn joystick(st: *St, cy: *Cy, joy: i64) bool {
    st.wl(0x0E74, 0);
    cy.run(0x46CC, 0x46DE);
    joy_wait(st, cy);
    st.wl(0x0E74, 0x0E40);
    var d0 = joy & 0xFF;
    st.set_a(0, 0x0E41);
    cy.run(0x46EA, 0x46FC);
    if (!cy.br(0x46FC, st.rl(0x0E5E) == BASE + P2)) cy.one(0x46FE);
    st.set_d(0, d0, 1);
    cy.one(0x4700);
    if (cy.br(0x4704, d0 & 0x80 != 0)) return back.enter(st, cy);
    st.ww(0x0E64, 1);
    d0 &= 0x0F;
    st.set_d(0, d0, 1);
    cy.run(0x4708, 0x4714);
    if (!cy.br(0x4714, d0 != 0)) {
        st.wb(0x424E, 0);
        cy.run(0x4716, 0x471E);
        return false;
    }
    var d1: i64 = 6;
    const n = (st.rb(0x424E) - 1) & 0xFF;
    st.wb(0x424E, n);
    cy.run(0x471E, 0x4728);
    if (cy.br(0x4728, 0 < s8(n))) {
        st.set_d(1, d1, 1);
        cy.one(0x46CA);
        return false;
    }
    if (!cy.br(0x472A, s8(n) < 0)) {
        d1 = 2;
        cy.one(0x472C);
    }
    st.set_d(1, d1, 1);
    st.wb(0x424E, d1);
    cy.run(0x4730, 0x473A);
    if (!cy.br(0x473A, d0 & 1 == 0)) {
        var c = (st.rb(0x0E66) + 1) & 0xFF;
        cy.run(0x473C, 0x474A);
        if (!cy.br(0x474A, c != 0x5B)) {
            c = 0x20;
            cy.one(0x474C);
        }
        cy.one(0x4754);
        if (!cy.br(0x475C, c != 0x21)) {
            c = 0x41;
            cy.run(0x4760, 0x476C); // move.b #'A' ; bra.w $483a
        }
        st.wb(0x0E66, c);
        back.put_char(st, cy);
        return false;
    }
    cy.one(0x476C);
    if (!cy.br(0x4770, d0 & 2 == 0)) {
        var c = (st.rb(0x0E66) - 1) & 0xFF;
        cy.run(0x4772, 0x4780);
        if (!cy.br(0x4780, c != 0x40)) {
            c = 0x20;
            cy.one(0x4782);
        }
        cy.one(0x478A);
        if (!cy.br(0x4792, c != 0x1F)) {
            c = 0x5A;
            cy.run(0x4796, 0x47A2);
        }
        st.wb(0x0E66, c);
        back.put_char(st, cy);
        return false;
    }
    cy.one(0x47A2);
    if (!cy.br(0x47A6, d0 & 4 == 0)) return back.left(st, cy);
    cy.one(0x47B8);
    if (cy.br(0x47BC, d0 & 8 == 0)) {
        cy.one(0x46CA);
        return false;
    }
    return back.right(st, cy);
}
