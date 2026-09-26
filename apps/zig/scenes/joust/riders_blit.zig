// --------------------------------------------------------------------------
// Package A: the block blits and the platform redraw (the model's a_blit.py):
//   or_blit       $045C OR a block of groups x rows onto the screen
//   left_ledge    $04F0 the early waves' extra bottom-left ledge
//   call 11       $0540 redraw every platform whose countdown ($0D38..) runs
// --------------------------------------------------------------------------
const State = @import("state.zig");
const cyc = @import("cyc.zig");
const St = State.St;
const V = State.V;
const Cy = cyc.Cy;
const BASE = State.BASE;
const M32 = State.M32;
const setb = State.setb;
const s8 = State.s8;
const span = cyc.span;
const brc = cyc.brc;

/// $045C(dst.l, src.l, groups.w, rows.w) called by bsr.
pub fn or_blit(st: *St, cy: *Cy, dst: i64, src: i64, groups: i64, rows: i64) void {
    const R = &st.regs;
    cy.add(20); // bsr
    cy.run(0x45C, 0x46C);
    var a0 = dst;
    var a1 = src;
    var a2: i64 = 0;
    var d0: i64 = 0;
    var d1 = rows & 0xFFFF;
    var d3 = R[3];
    while (true) {
        cy.add(span(0x46C, 0x472));
        a2 = a0;
        d0 = groups & 0xFFFF;
        while (true) {
            for (0..2) |_| {
                d3 = st.rd(a1, 4);
                a1 += 4;
                st.wr(a2, 4, st.rd(a2, 4) | d3);
                a2 += 4;
            }
            cy.add(span(0x472, 0x47C));
            d0 = (d0 & 0xFF00) | ((d0 - 1) & 0xFF);
            if (cy.br(0x47C, d0 & 0xFF != 0)) continue;
            break;
        }
        cy.add(span(0x47E, 0x484));
        a0 = (a0 + 0xA0) & M32;
        d1 = (d1 & 0xFF00) | ((d1 - 1) & 0xFF);
        if (cy.br(0x484, d1 & 0xFF != 0)) continue;
        break;
    }
    cy.run(0x486, 0x488); // rts
    R[0] = d0;
    R[1] = d1;
    R[3] = d3;
    R[8] = a0;
    R[9] = a1;
    R[10] = a2;
}

/// $04F0 by bsr: the early waves' extra ledge (registers restored by movem).
pub fn left_ledge(st: *St, cy: *Cy) void {
    cy.add(20 + span(0x4F0, 0x50A));
    var a0 = (st.g(V.screen_base) + 0x6AE0) & M32;
    for (0..4) |_| {
        for ([_]i64{ 0xFFFF, 0xFFFFFFFF }) |v| {
            for ([_]i64{ 0x80, 0x120, 0x1C0, 0xA0, 0x140 }) |off| st.wr(a0 + off, 4, v);
            st.wr(a0, 4, v);
            a0 += 4;
        }
    }
    cy.add(4 * span(0x50A, 0x538) + 3 * brc(0x538, true) + brc(0x538, false));
    cy.run(0x53A, 0x540);
}

/// move.b hi,d0; cmp.b lo,d0; beq; bgt -> both bytes become the signed max.
fn max_pair(st: *St, cy: *Cy, a_lo: i64, a_hi: i64, pc: i64) void {
    const R = &st.regs;
    const hi = st.rb(a_hi);
    const lo = st.rb(a_lo);
    R[0] = setb(R[0], hi);
    cy.run(pc, pc + 12);
    if (cy.br(pc + 12, s8(hi) == s8(lo))) return;
    if (cy.br(pc + 14, s8(hi) > s8(lo))) {
        cy.run(pc + 0x1C, pc + 0x26); // move.b hi,lo
        st.wb(a_lo, hi);
    } else {
        cy.run(pc + 0x10, pc + 0x1C); // move.b lo,hi; bra
        st.wb(a_hi, lo);
    }
}

/// Call 11: redraw the platforms whose countdown byte (platform_on, $0D38..)
/// is > 0; each blit list entry at $1A42 = [counter ptr.l, rows.w, groups.w,
/// src.l, screen offset.l].
pub fn call_0540_platform_redraw(st: *St) void {
    const R = &st.regs;
    var cy = Cy.init(st);
    cy.add(20); // jsr
    cy.run(0x540, 0x548);
    R[7] = 8;
    max_pair(st, &cy, 0x0D3A, 0x0D3B, 0x548);
    max_pair(st, &cy, 0x0D3E, 0x0D3F, 0x56E);
    var a6 = BASE + 0x1A42;
    for (0..8) |n| {
        const e = a6 - BASE;
        const a0 = st.rl(e);
        R[8] = a0;
        const v0 = st.rd(a0, 1);
        cy.run(0x594, 0x598);
        if (cy.br(0x598, v0 == 0 or v0 & 0x80 != 0)) {} else {
            cy.run(0x59A, 0x5A0);
            if (!cy.br(0x5A0, n != 0)) {
                cy.run(0x5A2, 0x5AA);
                const w = st.g(V.wave);
                if (!cy.br(0x5AA, (w ^ 0x80) >= 0x83)) left_ledge(st, &cy);
            }
            R[0] = st.rl(e + 8);
            cy.run(0x5B0, 0x5B6);
            const v = (st.rd(a0, 1) - 1) & 0xFF;
            st.wr(a0, 1, v);
            if (!cy.br(0x5B6, v != 0)) {
                cy.run(0x5B8, 0x5BC);
                st.wr(a0, 1, 0xFF);
            }
            cy.run(0x5BC, 0x5D4);
            const dst = (st.g(V.screen_base) + st.rl(e + 12)) & M32;
            R[8] = dst;
            or_blit(st, &cy, dst, st.rl(e + 8), st.rw(e + 6), st.rw(e + 4));
            cy.run(0x5D8, 0x5DE);
        }
        cy.run(0x5DE, 0x5E6);
        a6 += 0x10;
        R[7] = 7 - @as(i64, @intCast(n));
        _ = cy.br(0x5E6, n != 7);
    }
    R[14] = a6;
    cy.run(0x5E8, 0x5EA); // rts
    cy.done();
}
