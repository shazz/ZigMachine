// --------------------------------------------------------------------------
// Package A's shared subroutines (the model's a_sub.py), with em68 cycles:
//   sfx_call   $0A94 play SFX (its body; core play_sfx at the trap)
//   xy_addr    $85F4 x,y -> screen address + shift
//   draw       $37D8 draw a rider (OR, runtime shift, wrap bits $0E30, lava clip)
//   erase      $38AC erase a rider (AND-NOT at the previous position)
// (the aux sprite's erase and draw are in riders_aux.zig)
// Registers: st.regs, d0-d7 = [0..7], a0-a7 = [8..15] (absolute addresses).
// --------------------------------------------------------------------------
const aux = @import("riders_aux.zig");
const State = @import("state.zig");
const cyc = @import("cyc.zig");
const sound = @import("sound.zig");
const St = State.St;
const V = State.V;
const Cy = cyc.Cy;
const BASE = State.BASE;
const M32 = State.M32;
const s16 = State.s16;
const setw = State.setw;
const span = cyc.span;
const sh = cyc.sh;
const shr = State.shr;

/// $0A94(n) from its first instruction to its rts (the caller counts the
/// push/jsr/pop). Registers are preserved.
pub fn sfx_call(st: *St, cy: *Cy, n: i64) void {
    cy.add(span(0xA94, 0xAA4));
    if (cy.br(0xAA4, n > st.g(V.sfx_prio))) {
        cy.add(span(0xAC2, 0xAC8));
        return;
    }
    cy.add(span(0xAA6, 0xABC));
    cy.flush();
    _ = sound.play_sfx(st, n);
    cy.add(300 + span(0xABE, 0xAC8)); // trap, adda, movem, rts
}

/// A `move.w #n,-(a7); jsr $a94.l; addq/adda #2,a7` site [lo, hi).
pub fn sfx_site(st: *St, cy: *Cy, n: i64, lo: i64, hi: i64) void {
    cy.run(lo, lo + 10);
    sfx_call(st, cy, n);
    cy.run(lo + 10, hi);
}

pub const XY = struct { addr: i64, shift: i64 };

/// $85F4 (jsr'd, counted from the target to its rts): the screen address and
/// shift; leaves d0 = (x/16)*8, d1 = x%16, a0 = the address.
pub fn xy_addr(st: *St, cy: *Cy, x: i64, y: i64) XY {
    const R = &st.regs;
    cy.add(span(0x85F4, 0x8628));
    var a0 = st.g(V.screen_base);
    var d0 = ((y & 0xFFFF) * 0xA0) & M32;
    a0 = (a0 + s16(d0)) & M32;
    const q = @divFloor(x & 0xFFFF, 16);
    const r = @mod(x & 0xFFFF, 16);
    d0 = ((q & 0xFFFF) * 8) & M32;
    a0 = (a0 + s16(d0)) & M32;
    R[0] = d0;
    R[1] = r;
    R[8] = a0;
    return .{ .addr = a0, .shift = r };
}

pub fn wordOr(st: *St, a: i64, v: i64) void {
    st.wr(a, 2, st.rd(a, 2) | v);
}

pub fn wordAndNot(st: *St, a: i64, v: i64) void {
    st.wr(a, 2, st.rd(a, 2) & ~v);
}

/// $37D8 by bsr (the caller counts the bsr). Uses $0E56/$0E5E/$0E62/$0E64/$0E30.
pub fn draw(st: *St, cy: *Cy) void {
    const R = &st.regs;
    const a0 = R[8] - BASE;
    cy.add(span(0x37D8, 0x37E0));
    if (!cy.br(0x37E0, st.rw(a0) != 0)) {
        cy.add(span(0x37E2, 0x37E8));
        return;
    }
    cy.add(span(0x37E8, 0x3804));
    const d0 = st.rb(0x0E62);
    const a1 = st.g(V.tmp_ptr_e56);
    var a2 = st.g(V.tmp_sprite_e5e);
    var d4 = R[4];
    const moveq = span(0x3834, 0x3836);
    if (!cy.br(0x3804, st.g(V.draw_wrap) & 2 != 0)) {
        cy.add(span(0x3806, 0x3810));
        var a3 = a1;
        var d1 = st.rb(0x0E64);
        const lava = st.g(V.lava_top);
        while (true) {
            cy.add(span(0x3810, 0x3816));
            if (!cy.br(0x3816, a3 < lava)) {
                cy.add(span(0x3818, 0x3834));
                const f = st.rw(a0) | 0x100;
                d4 = setw(d4, f);
                st.ww(a0, f);
                d1 = (-(d1 - st.rb(0x0E64))) & 0xFF;
                st.wb(0x0E64, d1);
                break;
            }
            cy.add(moveq);
            for (0..4) |k| {
                const v = shr(st.rd(a2, 2), d0) & 0xFFFF;
                a2 += 2;
                wordOr(st, a3, v);
                a3 += 2;
                cy.add(span(0x3836, 0x383A) + sh(d0, true) + span(0x383C, 0x3840));
                _ = cy.br(0x3840, k != 3);
            }
            cy.add(span(0x3842, 0x3850));
            a3 += 0x98;
            a2 += 8;
            d1 = (d1 - 1) & 0xFF;
            if (!cy.br(0x3850, d1 != 0)) break;
        }
    }
    cy.add(span(0x3852, 0x385A));
    if (!cy.br(0x385A, st.g(V.draw_wrap) & 1 != 0)) {
        cy.add(span(0x385C, 0x387C));
        var d1 = st.rb(0x0E64);
        a2 = st.g(V.tmp_sprite_e5e) + 8;
        var a3 = a1 + 8;
        const x = st.rw(a0 + 2);
        d4 = setw(d4, x);
        if (cy.br(0x387C, s16(x) < 0x130)) {} else {
            cy.run(0x387E, 0x3884);
            a3 -= 0xA0;
        }
        while (true) {
            cy.add(moveq);
            for (0..4) |k| {
                const v = shr((st.rd(a2 - 8, 2) << 16) | st.rd(a2, 2), d0) & 0xFFFF;
                a2 += 2;
                wordOr(st, a3, v);
                a3 += 2;
                cy.add(span(0x3886, 0x388E) + sh(d0, true) + span(0x383C, 0x3840));
                _ = cy.br(0x3894, k != 3);
            }
            cy.add(span(0x3896, 0x38A4));
            a3 += 0x98;
            a2 += 8;
            d1 = (d1 - 1) & 0xFF;
            if (!cy.br(0x38A4, d1 != 0)) break;
        }
    }
    cy.add(span(0x38A6, 0x38AC));
    R[4] = d4;
}

/// One half of an AND-NOT erase: `rows` lines of 4 plane words.
fn eraseRows(st: *St, cy: *Cy, a3_0: i64, a2_0: i64, rows: i64, d0: i64, right: bool) void {
    var a3 = a3_0;
    var a2 = a2_0;
    var d1 = rows;
    while (true) {
        cy.add(span(0x38C6, 0x38C8));
        for (0..4) |k| {
            const v = if (right)
                shr((st.rd(a2 - 8, 2) << 16) | st.rd(a2, 2), d0) & 0xFFFF
            else
                shr(st.rd(a2, 2), d0) & 0xFFFF;
            a2 += 2;
            wordAndNot(st, a3, v);
            a3 += 2;
            if (right) {
                cy.add(span(0x390A, 0x3912) + sh(d0, true) + span(0x3914, 0x391A));
                _ = cy.br(0x391A, k != 3);
            } else {
                cy.add(span(0x38C8, 0x38CC) + sh(d0, true) + span(0x38CE, 0x38D4));
                _ = cy.br(0x38D4, k != 3);
            }
        }
        cy.add(if (right) span(0x391C, 0x392A) else span(0x38D6, 0x38E4));
        a3 += 0x98;
        a2 += 8;
        d1 = (d1 - 1) & 0xFF;
        if (!cy.br(if (right) 0x392A else 0x38E4, d1 != 0)) break;
    }
}

/// $38AC by bsr (the caller counts the bsr): AND-NOT the previous image
/// (+$14/+$18/+$1C/+$1D).
pub fn erase(st: *St, cy: *Cy) void {
    const R = &st.regs;
    const a0 = R[8] - BASE;
    cy.add(span(0x38AC, 0x38C6));
    const d0 = st.rb(a0 + 0x1D);
    const a1 = st.rl(a0 + 0x14);
    eraseRows(st, cy, a1, st.rl(a0 + 0x18), st.rb(a0 + 0x1C), d0, false);
    cy.add(span(0x38E6, 0x3900));
    var a3 = a1 + 8;
    const x = st.rw(a0 + 0x10);
    R[4] = setw(R[4], x);
    if (!cy.br(0x3900, s16(x) < 0x130)) {
        cy.run(0x3902, 0x3908);
        a3 -= 0xA0;
    }
    eraseRows(st, cy, a3, st.rl(a0 + 0x18) + 8, st.rb(a0 + 0x1C), d0, true);
    cy.add(span(0x392C, 0x3932));
}
