// --------------------------------------------------------------------------
// Call 17, $450E (the model's d_gameover.py): after GAME OVER ($0D50 set when
// the GAME OVER message expires) the better player's score against the high
// score $86FB; a new high score clears the screen and runs the name entry
// (flow_name.zig) until Return / fire, then jmp $6 (the title). Also the
// screen clear $02E8.
// --------------------------------------------------------------------------
const State = @import("state.zig");
const cyc = @import("cyc.zig");
const name = @import("flow_name.zig");
const St = State.St;
const V = State.V;
const Cy = cyc.Cy;
const BASE = State.BASE;
const SCREEN = State.SCREEN;
const P1 = State.P1;
const P2 = State.P2;
const s8 = State.s8;

pub const HI: i64 = 0x86FB; // the high score digits

const Cmp = enum { gt, lt, end };

/// The compare loop at lo ($4530 / $4566): d0 = (a0)+ is also the loop count
/// (a bug: equal bytes just go on to the next pair).
fn cmp(st: *St, cy: *Cy, a0_in: i64, a1_in: i64, lo: i64) Cmp {
    var a0 = a0_in;
    var a1 = a1_in;
    var d0: i64 = 0;
    var r: Cmp = .end;
    while (true) {
        d0 = st.rb(a0);
        a0 += 1;
        const b = st.rb(a1);
        a1 += 1;
        cy.run(lo, lo + 4); // move.b (a0)+,d0 ; cmp.b (a1)+,d0
        if (cy.br(lo + 4, s8(d0) > s8(b))) {
            r = .gt;
            break;
        }
        if (cy.br(lo + 6, s8(d0) < s8(b))) {
            r = .lt;
            break;
        }
        d0 = (d0 - 1) & 0xFF;
        cy.one(lo + 8);
        if (!cy.br(lo + 10, d0 != 0)) {
            r = .end;
            break;
        }
    }
    st.set_d(0, d0, 1);
    st.set_a(0, BASE + a0);
    st.set_a(1, BASE + a1);
    return r;
}

/// Call 17. Returns true when the name entry started (the caller runs it,
/// resumably, to its jmp $6).
pub fn call_450e_game_over(st: *St, ne: *name.NameEntry) bool {
    var cy = Cy.init(st);
    cy.add(20);
    if (name_entry_or_rts(st, &cy, ne)) return true;
    cy.done();
    return false;
}

/// $450E body (after the jsr). True when a new high score starts the name
/// entry (it leaves through jmp $6, never by the rts).
pub fn name_entry_or_rts(st: *St, cy: *Cy, ne: *name.NameEntry) bool {
    cy.one(0x450E);
    if (!cy.br(0x4514, st.g(V.new_game) != 0)) {
        cy.one(0x4516);
        return false;
    }
    cy.run(0x4518, 0x4530); // a0/a1 = the two score strings, move.b #7,d0
    var win: i64 = undefined;
    if (cmp(st, cy, P1 + 0x3E, P2 + 0x3E, 0x4530) == .lt) {
        win = P2;
        cy.run(0x4548, 0x4552);
    } else {
        win = P1;
        cy.run(0x453C, 0x4548); // move.l, bra
    }
    st.wl(0x0E5E, BASE + win);
    cy.run(0x4552, 0x4566);
    if (cmp(st, cy, win + 0x3E, HI, 0x4566) != .gt) {
        cy.one(0x4572);
        return false;
    }
    name.begin(st, cy, win, ne);
    return true;
}

/// $02E8 body (after the jsr): colour 0..15 -> planes (only bit 0 is tested, 4 times).
pub fn clear_screen(st: *St, cy: *Cy, colour: i64) void {
    cy.run(0x02E8, 0x02F2); // movea.l, move.w 4(a7),d0
    cy.one(0x02F2); // bsr.b $304
    cy.run(0x0304, 0x0308);
    var d1: i64 = 0;
    for ([_]i64{ 0x0308, 0x0314, 0x0320, 0x032C }) |at| {
        cy.one(at);
        if (!cy.br(at + 4, colour & 1 == 0)) {
            d1 = 0xFFFF0000;
            cy.one(at + 6);
        }
    }
    cy.one(0x0338); // rts
    cy.one(0x02F4); // move.l #$fa0,d3
    var a = st.g(V.screen_base);
    const body = cyc.span(0x02FA, 0x02FE);
    for (0..0xFA1) |i| {
        for ([_]i64{ d1, 0 }) |v| {
            if (SCREEN <= a and a < SCREEN + 32000) st.wr(a, 4, v);
            a += 4;
        }
        cy.add(body);
        cy.add(if (i < 0xFA0) 12 else 16); // dbra
    }
    cy.one(0x0302);
    st.regs[1] = d1;
    st.regs[2] = 0;
    st.regs[3] = 0x0000FFFF;
    st.set_a(0, a);
}
