// --------------------------------------------------------------------------
// Package D: the message records $0E84 (20 x 12 bytes) -- call 12 ($43CE,
// redraw/expire) and $44F0 (allocate a free record); the model's d_popups.py.
// Record: +0 kind (0 free, 1 banner, 2 bonus, 3 player message, 4 score
// popup), +1 timer, +2 ink, +3 shift, +4 screen address, +8 text address.
// --------------------------------------------------------------------------
const State = @import("state.zig");
const cyc = @import("cyc.zig");
const text = @import("flow_text.zig");
const St = State.St;
const V = State.V;
const Cy = cyc.Cy;
const BASE = State.BASE;
const s32 = State.s32;

const POPUPS: i64 = 0x0E84;
const POPUPS_END: i64 = 0x0FA4;

/// $44F0 body (after the jsr): TEXT offset of the first free record, or null
/// (a0 = 0).
pub fn alloc(st: *St, cy: anytype) ?i64 {
    cy.one(0x44F0); // movea.l #$e84,a0
    var a = POPUPS;
    while (true) {
        cy.one(0x44F6); // tst.b (a0)
        if (!cy.br(0x44FA, st.rb(a) != 0)) {
            cy.one(0x44FC); // rts
            st.set_a(0, BASE + a);
            return a;
        }
        a += 12;
        cy.run(0x44FE, 0x4508); // adda.w, cmpa.l
        if (!cy.br(0x4508, a != POPUPS_END)) {
            cy.run(0x450A, 0x450E); // suba.l a0,a0 ; rts
            st.set_a(0, 0);
            return null;
        }
    }
}

/// $4418: a score popup expiring over a platform re-arms that platform's blit bytes.
fn platform_bonus(st: *St, cy: *Cy, a: i64) void {
    const d0 = (st.rl(a + 4) - st.g(V.screen_base)) & State.M32;
    st.regs[0] = d0;
    const s = s32(d0);
    cy.run(0x4418, 0x4428); // move.l, sub.l, cmpi.l
    if (cy.br(0x4428, s > 0x5498)) return;
    cy.one(0x442C);
    if (!cy.br(0x4432, s < 0x4EF8)) {
        cy.one(0x4434);
        if (cy.br(0x443A, st.rb(0x0D39) == 0)) return;
        st.wb(0x0D39, st.rb(0x0D39) + 2);
        cy.run(0x443E, 0x4446); // addq.b, bra
        return;
    }
    cy.one(0x4446);
    if (cy.br(0x444C, s > 0x4920)) return;
    cy.one(0x444E);
    if (!cy.br(0x4454, s < 0x3E48)) {
        for ([_]i64{ 0x0D3A, 0x0D3B, 0x0D3C }) |o| st.wb(o, st.rb(o) + 2);
        cy.run(0x4456, 0x446A);
        return;
    }
    cy.one(0x446A);
    if (cy.br(0x4470, s > 0x26F0)) return;
    cy.one(0x4472);
    if (!cy.br(0x4478, s < 0x20B0)) {
        cy.one(0x447A);
        if (cy.br(0x4480, st.rb(0x0D3D) == 0)) return;
        st.wb(0x0D3D, st.rb(0x0D3D) + 2);
        cy.run(0x4482, 0x448A);
        return;
    }
    cy.one(0x448A);
    if (cy.br(0x4490, s > 0x1E88)) return;
    cy.one(0x4492);
    if (cy.br(0x4498, s < 0x1900)) return;
    cy.one(0x449A);
    if (cy.br(0x44A0, st.rb(0x0D3E) == 0)) return;
    st.wb(0x0D3E, st.rb(0x0D3E) + 2);
    st.wb(0x0D3F, st.rb(0x0D3F) + 2);
    cy.run(0x44A2, 0x44AE);
}

/// Call 12.
pub fn call_43ce_popups(st: *St) void {
    var cy = Cy.init(st);
    cy.add(20); // jsr
    cy.run(0x43CE, 0x43D6); // movea.l, bra
    var a = POPUPS;
    while (true) {
        cy.one(0x43E4); // tst.b (a0)
        if (!cy.br(0x43E8, st.rb(a) == 0)) {
            const kind = st.rb(a);
            cy.one(0x43EA); // tst.b $d30
            if (!cy.br(0x43F0, st.g(V.players) != 0)) {
                cy.one(0x43F2);
                if (!cy.br(0x43F8, kind == 3)) {
                    st.wb(a + 1, 1);
                    cy.one(0x43FA);
                }
            }
            const t = (st.rb(a + 1) - 1) & 0xFF;
            st.wb(a + 1, t);
            cy.one(0x4400);
            if (cy.br(0x4404, t != 0)) {
                st.wb(0x0E7D, st.rb(a + 2));
                cy.one(0x44C6);
            } else {
                st.wb(0x0E7D, 0);
                cy.run(0x4408, 0x4414); // clr.b $e7d, cmpi.b #4
                if (!cy.br(0x4414, kind != 4)) platform_bonus(st, &cy, a);
                st.wb(a, 0);
                cy.run(0x44AE, 0x44BA); // clr.b, cmpi.l
                if (!cy.br(0x44BA, st.rl(a + 8) != BASE + 0x8928)) {
                    st.s(V.new_game, 1);
                    cy.run(0x44BC, 0x44C6); // move.b #1,$d50 ; bra
                }
            }
            st.s(V.text_cursor, st.rl(a + 4));
            st.s(V.text_shift, st.rb(a + 3));
            cy.run(0x44CE, 0x44E8); // 2 moves, push, jsr
            text.print_text(st, &cy, st.rl(a + 8));
            cy.run(0x44E8, 0x44F0); // adda.w, bra.w
        }
        a += 12;
        cy.run(0x43D6, 0x43E0); // adda.w, cmpa.l
        if (!cy.br(0x43E0, a != POPUPS_END)) {
            cy.one(0x43E2); // rts
            break;
        }
    }
    st.set_a(0, BASE + POPUPS_END);
    cy.done();
}
