// --------------------------------------------------------------------------
// Package D: the score add + redraw ($4250 generic / $4256 P2 / $4262 P1) and
// the lives display ($4336 both / $433E P1 / $4350 P2) -- the model's
// d_score.py. Each is the routine body from its entry to its rts (the caller
// counts its own jsr/bsr); `cy` is D's Cy or B's Clk.
//
// The score is 7 ASCII digits at slot+$3E (leading spaces): the callers add
// points straight into a digit, $4250 then propagates the carries (every carry
// into the ten-thousands digit that makes it even = an extra life, SFX 1) and
// prints slot+$3C (a 2-byte control prefix + the digits).
// --------------------------------------------------------------------------
const State = @import("state.zig");
const sound = @import("sound.zig");
const text = @import("flow_text.zig");
const St = State.St;
const V = State.V;
const BASE = State.BASE;
const P1 = State.P1;
const P2 = State.P2;

const TEXT_MODE: i64 = 0x0E7F;

/// entry 0x4250 (a = the slot TEXT offset, the caller's a0), 0x4256 (P2), 0x4262 (P1).
pub fn score_add(st: *St, cy: anytype, entry: i64, a_in: i64) void {
    var a = a_in;
    if (entry == 0x4250) {
        cy.run(0x4250, 0x4256); // movem, bra
    } else if (entry == 0x4256) {
        a = P2;
        cy.run(0x4256, 0x4262); // movem, movea.l, bra
    } else {
        a = P1;
        cy.run(0x4262, 0x426C); // movem, movea.l
    }
    const save_d0 = st.regs[0];
    cy.one(0x426C); // move.l #$3e,d0
    var d: i64 = 0x3E;
    while (true) {
        cy.one(0x4272);
        if (cy.br(0x4278, st.rb(a + d) != 0x20)) break;
        d += 1;
        cy.run(0x427A, 0x4280);
        if (!cy.br(0x4280, d != 0x44)) {
            cy.one(0x4282); // bra $429a
            break;
        }
    }
    if (d != 0x44) {
        while (true) {
            const v = st.rb(a + d);
            cy.one(0x4284);
            if (!cy.br(0x428A, (v ^ 0x80) >= (0x30 ^ 0x80))) { // bge (signed)
                st.wb(a + d, v + 0x10);
                cy.one(0x428C);
            }
            d += 1;
            cy.run(0x4292, 0x4298);
            if (!cy.br(0x4298, d != 0x44)) break;
        }
    }
    st.wb(TEXT_MODE, st.rb(TEXT_MODE) | 0x80);
    cy.run(0x429A, 0x42A8); // bset #7, move.l #$44,d0
    d = 0x44;
    while (true) {
        cy.one(0x42A8);
        if (cy.br(0x42AE, st.rb(a + d) <= 0x39)) {
            d -= 1;
            cy.run(0x42EA, 0x42F0); // subq.b, cmp.b
            if (!cy.br(0x42F0, d != 0x3D)) break;
            continue;
        }
        cy.one(0x42B0);
        if (!cy.br(0x42B6, st.rb(a + d - 1) != 0x20)) {
            st.wb(a + d - 1, 0x30);
            cy.one(0x42B8);
        }
        st.wb(a + d - 1, st.rb(a + d - 1) + 1);
        st.wb(a + d, st.rb(a + d) - 10);
        cy.run(0x42BE, 0x42CC); // addq.b, subi.b, cmp.b
        if (cy.br(0x42CC, d != 0x41)) continue;
        cy.one(0x42CE);
        if (cy.br(0x42D4, st.rb(a + d - 1) & 1 != 0)) continue;
        st.wb(a + 0x4C, st.rb(a + 0x4C) + 1);
        cy.run(0x42D6, 0x42DC); // addq.b lives, bsr $4336
        lives_both(st, cy, a);
        cy.run(0x42DC, 0x42E6); // push, jsr $a94
        call_sfx(st, cy, 1);
        cy.run(0x42E6, 0x42EA); // addq.w, bra
    }
    st.wb(TEXT_MODE, st.rb(TEXT_MODE) | 0x10);
    st.wb(0x0E7E, 0x0F);
    st.s(V.text_shift, st.rb(a + 0x3B));
    st.s(V.text_cursor, st.rl(a + 0x36));
    cy.run(0x42F2, 0x4322); // bset, move.b, move.w, move.b, move.l, push, addi, jsr
    text.print_text(st, cy, BASE + a + 0x3C);
    st.wb(TEXT_MODE, st.rb(TEXT_MODE) & ~@as(i64, 0x10));
    cy.run(0x4322, 0x4336); // adda.l, bclr, movem, rts
    st.regs[0] = save_d0;
}

/// $4336 (bsr from the score add): a0 = the slot.
pub fn lives_both(st: *St, cy: anytype, a: i64) void {
    cy.one(0x4336);
    if (cy.br(0x433C, a == P2)) lives(st, cy, 2) else lives(st, cy, 1);
}

/// $433E (n=1) / $4350 (n=2) body, to the rts.
pub fn lives(st: *St, cy: anytype, n: u8) void {
    var a: i64 = undefined;
    var d1: i64 = undefined;
    if (n == 1) {
        a = P1;
        d1 = BASE + 0x8980;
        cy.run(0x433E, 0x4350); // movem, movea.l, move.l, bra
    } else {
        a = P2;
        d1 = BASE + 0x898C;
        cy.run(0x4350, 0x4360);
    }
    st.s(V.text_cursor, st.rl(a + 0x36) + 0x10);
    st.s(V.text_shift, st.rb(a + 0x3B) + 0x0A);
    st.wb(TEXT_MODE, st.rb(TEXT_MODE) | 0x90);
    st.wb(0x0E7E, 0x0F);
    cy.run(0x4360, 0x439C); // ... moveq #5,d0
    var d0: i64 = 5;
    while (true) {
        const lv = State.s8(st.rb(a + 0x4C));
        cy.one(0x439C); // cmp.b $4c(a0),d0
        if (cy.br(0x43A0, d0 <= lv)) {
            cy.run(0x43B0, 0x43B8); // push d1, jsr
            text.print_text(st, cy, d1);
        } else {
            cy.run(0x43A2, 0x43AE); // push #$897e, jsr
            text.print_text(st, cy, BASE + 0x897E);
            cy.one(0x43AE); // bra
        }
        cy.run(0x43B8, 0x43BE); // adda.w, subq.b
        d0 -= 1;
        if (!cy.br(0x43BE, d0 != 0)) break;
    }
    st.wb(TEXT_MODE, st.rb(TEXT_MODE) & ~@as(i64, 0x10));
    cy.run(0x43C0, 0x43CE); // bclr, movem, rts
}

/// $0A94 body (after the push + jsr): priority test, Dosound. Registers preserved.
pub fn call_sfx(st: *St, cy: anytype, n: i64) void {
    cy.run(0x0A94, 0x0A9E); // movem, clr.l, move.w
    cy.one(0x0A9E); // cmp.w $d8c,d0
    if (cy.br(0x0AA4, n > st.g(V.sfx_prio))) {
        cy.run(0x0AC2, 0x0AC8);
        return;
    }
    cy.run(0x0AA6, 0x0ABC); // move.w d0,$d8c, lsl.l #2, movea.l, 2 pushes
    cy.flush(); // the trap: Dosound acts at its start
    _ = sound.play_sfx(st, n);
    cy.add(300); // trap #14 (xbios shim cost)
    cy.run(0x0ABE, 0x0AC8); // adda.w, movem, rts
}
