// --------------------------------------------------------------------------
// Package A's own transcription of the text printer it calls, $073E (8x8
// font $820C / 5-row font $84E4) -- the model's a_text.py. Package D has its
// own (flow_text.zig); each package keeps its own so the registers they leave
// are the model's. The score and lives routines are in riders_score.zig.
// Counts from its first instruction to its rts; the caller counts its own
// jsr/bsr and the stack pushes and pops.
// --------------------------------------------------------------------------
const score = @import("riders_score.zig");
const State = @import("state.zig");
const cyc = @import("cyc.zig");
const sub = @import("riders_sub.zig");
const St = State.St;
const V = State.V;
const Cy = cyc.Cy;
const M32 = State.M32;
const s16 = State.s16;
const setb = State.setb;
const setw = State.setw;
const shr = State.shr;
const span = cyc.span;
const sh = cyc.sh;

const E7F: i64 = 0x0E7F;
const CODES = [_]i64{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 0xA, 0xD };

const Glyph = struct { d3: i64, a2: i64 };

/// One character (the font path from $07B4 / $085A back to $0754).
fn glyph(st: *St, cy: *Cy, d0: i64, d3_0: i64, a2_0: i64, small: bool) Glyph {
    var d3 = d3_0;
    var a2 = a2_0;
    var a1: i64 = undefined;
    var rows: usize = undefined;
    var d5: i64 = undefined;
    var base: i64 = undefined;
    var back: i64 = undefined;
    var step: i64 = undefined;
    const n = d3 & 63;
    if (small) {
        cy.run(0x7C0, 0x7D8);
        a1 = 0x84E4 + ((d0 - 0x20) & 0xFF) * 5;
        rows = 5;
        d5 = if (n < 32) shr(0xF0000000, n) else 0;
        cy.add(sh(n, true));
        base = 0x7DA;
        back = 0x320;
        step = 4;
    } else {
        cy.run(0x85A, 0x870);
        a1 = 0x820C + s16(((d0 - 0x20) & 0xFF) << 3);
        rows = 8;
        d5 = if (n < 32) shr(0xFC000000, n) else 0;
        cy.add(sh(n, true));
        base = 0x872;
        back = 0x500;
        step = 6;
    }
    const o = base - 0x7DA; // the 8x8 loop is the 5-row loop shifted by $98
    for (0..rows) |r| {
        cy.run(0x7DA + o, 0x7E2 + o);
        var d2 = st.rb(a1) << 24;
        a1 += 1;
        d2 = if (n < 32) shr(d2, n) else 0;
        cy.add(sh(n, true));
        cy.run(0x7E4 + o, 0x7E6 + o);
        for (0..4) |d4| {
            cy.run(0x7E6 + o, 0x7EE + o);
            const paper_on = st.rb(E7F) & 0x10;
            if (!cy.br(0x7EE + o, paper_on == 0)) {
                cy.run(0x7F0 + o, 0x7F6 + o);
                if (!cy.br(0x7F6 + o, !State.bit(st.rb(0x0E7E), @intCast(d4)))) {
                    cy.run(0x7F8 + o, 0x804 + o);
                    st.wr(a2 + 8, 2, st.rd(a2 + 8, 2) | (d5 & 0xFFFF));
                    st.wr(a2, 2, st.rd(a2, 2) | shr(d5, 16));
                } else {
                    cy.run(0x804 + o, 0x812 + o);
                    st.wr(a2 + 8, 2, st.rd(a2 + 8, 2) & ~d5 & 0xFFFF);
                    st.wr(a2, 2, st.rd(a2, 2) & ~shr(d5, 16) & 0xFFFF);
                }
            }
            cy.run(0x812 + o, 0x818 + o);
            if (!cy.br(0x818 + o, !State.bit(st.rb(0x0E7D), @intCast(d4)))) {
                cy.run(0x81A + o, 0x824 + o);
                st.wr(a2 + 8, 2, st.rd(a2 + 8, 2) | (d2 & 0xFFFF));
                st.wr(a2, 2, st.rd(a2, 2) | shr(d2, 16));
            } else {
                cy.run(0x824 + o, 0x830 + o);
                st.wr(a2 + 8, 2, st.rd(a2 + 8, 2) & ~d2 & 0xFFFF);
                st.wr(a2, 2, st.rd(a2, 2) & ~shr(d2, 16) & 0xFFFF);
            }
            a2 += 2;
            cy.run(0x830 + o, 0x838 + o);
            _ = cy.br(0x838 + o, d4 != 3);
        }
        cy.run(0x83A + o, 0x840 + o);
        a2 += 0x98;
        _ = cy.br(0x840 + o, r != rows - 1);
    }
    cy.run(0x842 + o, 0x84C + o);
    a2 = (a2 - back) & M32;
    d3 = setb(d3, d3 + step);
    if (!cy.br(0x84C + o, d3 & 0x10 == 0)) {
        cy.run(0x84E + o, 0x856 + o);
        a2 += 8;
        d3 &= ~@as(i64, 0x10);
    }
    cy.run(0x856 + o, 0x85A + o);
    return .{ .d3 = d3, .a2 = a2 };
}

/// $073E(ptr): prints the string at ptr from $0E78 (screen) / $0E7C (shift).
pub fn text_print(st: *St, cy: *Cy, ptr: i64) void {
    const R = &st.regs;
    cy.add(span(0x73E, 0x754));
    var a0 = ptr;
    var d3 = st.rb(0x0E7C);
    var a2 = st.g(V.text_cursor);
    const saved = R.*;
    while (true) {
        cy.add(span(0x754, 0x758));
        const d0 = st.rd(a0, 1);
        a0 += 1;
        if (cy.br(0x758, d0 == 0)) break;
        var code: ?i64 = null;
        for (CODES, 0..) |c, i| {
            const pc: i64 = 0x75C + 8 * @as(i64, @intCast(i));
            cy.run(pc, pc + 4);
            if (cy.br(pc + 4, d0 == c)) {
                code = c;
                break;
            }
        }
        const k = code orelse {
            cy.run(0x7B4, 0x7BC);
            const small = !cy.br(0x7BC, st.rb(E7F) & 0x80 != 0);
            const gl = glyph(st, cy, d0, d3, a2, small);
            d3 = gl.d3;
            a2 = gl.a2;
            continue;
        };
        switch (k) {
            1 => {
                st.s(V.text_x, st.rd(a0, 2));
                st.s(V.text_y, st.rd(a0 + 2, 2));
                a0 += 4;
                cy.run(0x904, 0x92A);
                const xy = sub.xy_addr(st, cy, st.g(V.text_x), st.g(V.text_y));
                a2 = xy.addr;
                d3 = setw(d3, xy.shift);
                cy.run(0x92A, 0x93A);
            },
            2 => {
                st.wb(0x0E7D, st.rd(a0, 1));
                a0 += 1;
                cy.run(0x93A, 0x944);
            },
            3 => {
                cy.run(0x944, 0x952);
                st.wb(E7F, st.rb(E7F) | 0x10);
                const v = st.rd(a0, 1);
                a0 += 1;
                st.wb(0x0E7E, v);
                if (!cy.br(0x952, v != 0)) {
                    cy.run(0x956, 0x962);
                    st.wb(E7F, st.rb(E7F) & ~@as(i64, 0x10));
                }
            },
            4, 5, 6, 7 => {
                const pc: i64 = switch (k) {
                    4 => 0x962,
                    5 => 0x966,
                    6 => 0x96A,
                    else => 0x96E,
                };
                cy.run(pc, pc + 4);
            },
            8 => {
                cy.run(0x972, 0x974);
                d3 = (d3 - 6) & M32;
                if (!cy.br(0x974, d3 & 0x80000000 == 0)) {
                    cy.run(0x978, 0x988);
                    d3 = (d3 + 0x10) & M32;
                    a2 -= 8;
                }
            },
            9 => {
                cy.run(0x988, 0x98A);
                const v = st.rd(a0, 1);
                a0 += 1;
                if (cy.br(0x98A, v != 0)) {
                    cy.run(0x998, 0x9A4);
                    st.wb(E7F, st.rb(E7F) | 0x80);
                } else {
                    cy.run(0x98C, 0x998);
                    st.wb(E7F, st.rb(E7F) & ~@as(i64, 0x80));
                }
            },
            else => {
                const pc: i64 = if (k == 0xA) 0x9A4 else 0x9A8;
                cy.run(pc, pc + 4);
            },
        }
    }
    cy.add(span(0x8F2, 0x904));
    st.s(V.text_cursor, a2);
    st.wb(0x0E7C, d3);
    R.* = saved; // movem.l d0-d5/a0-a2 restores everything touched
}

// ------------------------------------------------------------------ $433E / $4350 / $4336
// ------------------------------------------------------------------ $4250 score add
// ------------------------------------------------------------------ $44F0
// ------------------------------------------------------------------ $1FBA
