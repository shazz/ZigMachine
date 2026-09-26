// --------------------------------------------------------------------------
// $73C0 (the model's d_waves._eggs): the egg wave lays its eggs on random
// surfaces, 8 or more pixels apart.
// --------------------------------------------------------------------------
const State = @import("state.zig");
const cyc = @import("cyc.zig");
const St = State.St;
const V = State.V;
const Cy = cyc.Cy;
const BASE = State.BASE;
const back = @import("flow_nextwave.zig");

/// $73C0: the egg wave lays its eggs on random surfaces, 8+ pixels apart.
pub fn eggs(st: *St, cy: *Cy, w: i64, d0_in: i64) i64 {
    var d0 = d0_in;
    cy.run(0x73C0, 0x73E2);
    var a1: i64 = 0x1040;
    var a5: i64 = 0x81CC;
    var a3: i64 = 0;
    var a4: ?i64 = null;
    var d6 = (0xA5 - w) & 0xFF;
    st.ww(0x0E5A, 0);
    var d1 = st.regs[1];
    var d2 = st.regs[2];
    outer: while (true) { // $73E2
        st.s(V.rng_ptr, st.g(V.rng_ptr) + 0xC4);
        cy.run(0x73E2, 0x73F2); // addi.l, jsr
        back.rng_exact(st, cy, d0);
        a3 = st.g(V.rng_ptr);
        const v = (st.rd(a3, 2) + st.rd(a3 + 2, 2)) & 0xFFFF;
        a3 += 4;
        d0 = (d0 & 0xFFFF0000) | v;
        cy.run(0x73F2, 0x73FC);
        if (cy.br(0x73FC, v == 0)) continue;
        const s = v & 0x38;
        d0 = (d0 & 0xFFFF0000) | s;
        st.ww(a5, s);
        st.ww(a1 + 0x22, (st.rw(0x1822 + s) + 0x0C) & 0xFFFF);
        d1 = (d1 & 0xFFFF0000) | ((st.rw(0x1822 + s + 6) - st.rw(0x1822 + s + 4)) & 0xFFFF);
        d2 = (st.rd(a3, 2) + st.rd(a3 + 2, 2)) & 0xFFFF;
        a3 += 4;
        cy.run(0x73FE, 0x741E);
        if (cy.br(0x741E, d2 == 0)) continue;
        const div = d1 & 0xFFFF;
        if (div == 0) {
            st.oob += 1; // the model raises: divide by zero at $7420
            continue;
        }
        const qt = @divFloor(d2, div);
        const rm = @mod(d2, div);
        d2 = (qt << 16) | rm;
        cy.run(0x7420, 0x742A); // divu, swap, cmp.w
        if (cy.br(0x742A, rm == st.rw(0x0E5A))) continue;
        st.ww(0x0E5A, rm);
        const x = (rm + st.rw(0x1822 + s + 4)) & 0xFFFF;
        d2 = (qt << 16) | x;
        st.ww(a1 + 0x20, x);
        st.ww(a5 + 2, x);
        cy.run(0x742C, 0x7442);
        if (!cy.br(0x7442, s != 0x18)) {
            cy.one(0x7444);
            if (cy.br(0x744C, State.s16(rm) <= 5)) continue;
        }
        cy.run(0x744E, 0x7456); // movea.l, subq.w
        var p4: i64 = 0x81CC - 4;
        var bad = false;
        while (true) {
            p4 += 4;
            a4 = p4;
            cy.run(0x7456, 0x745A);
            if (cy.br(0x745A, p4 == a5)) break;
            d2 = (d2 & 0xFFFF0000) | st.rw(p4);
            cy.run(0x745C, 0x7460);
            if (cy.br(0x7460, st.rw(p4) != st.rw(a5))) continue;
            const dd = (st.rw(p4 + 2) - st.rw(a5 + 2)) & 0xFFFF;
            d2 = (d2 & 0xFFFF0000) | dd;
            cy.run(0x7462, 0x746E);
            if (cy.br(0x746E, dd <= 8)) {
                bad = true;
                break;
            }
            cy.one(0x7472);
            if (cy.br(0x7476, dd >= 0xFFF8)) {
                bad = true;
                break;
            }
            cy.one(0x747A);
        }
        if (bad) continue;
        a5 += 4;
        d6 = (d6 + 7) & 0xFF;
        st.wb(a1 + 0x29, 6);
        st.wb(a1 + 0x28, 4);
        st.wb(a1 + 0x1F, d6);
        st.wb(a1 + 0x32, 7);
        st.wl(a1 + 0x2A, st.g(V.screen_base));
        st.wl(a1 + 0x2E, BASE + 0x8CFC);
        st.wb(a1 + 0x34, 1);
        cy.run(0x747C, 0x74B4);
        var done = false;
        const cnts = [_][2]i64{ .{ 0x0D95, 0x74AE }, .{ 0x0D96, 0x74BC }, .{ 0x0D97, 0x74CA } };
        for (cnts, 0..) |ca, kk| {
            const n = (st.rb(ca[0]) - 1) & 0xFF;
            st.wb(ca[0], n);
            if (kk != 0) cy.one(ca[1]);
            const neg = n & 0x80 != 0;
            if (kk < 2) {
                if (cy.br(ca[1] + 6, !neg)) break;
                st.wb(a1 + 0x34, @as(i64, @intCast(kk)) + 2);
                cy.one(ca[1] + 8);
            } else if (cy.br(ca[1] + 6, neg)) {
                done = true;
            }
        }
        if (done) break :outer;
        st.wb(a1 + 0x1E, 0x22);
        a1 += 0x4E;
        cy.run(0x74D2, 0x74E2);
        if (!cy.br(0x74E2, a1 < 0x13E8)) break;
    }
    st.regs[1] = d1;
    st.regs[2] = d2;
    st.set_d(6, d6, 1);
    st.set_a(1, BASE + a1);
    st.set_a(2, BASE + 0x1822);
    st.set_a(3, a3);
    if (a4) |p| st.set_a(4, BASE + p);
    st.set_a(5, BASE + a5);
    return d0;
}
