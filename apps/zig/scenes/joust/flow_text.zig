// --------------------------------------------------------------------------
// Package D: the text printer $073E (fonts $84E4 small 3-px / $820C 8x8 at a
// 6-px pitch) and $85F4 (x, y -> screen address + shift) -- the model's
// d_text.py. print_text(st, cy, s): the body of `jsr $73e` with the string at
// absolute address s, from the movem at $073E to its rts; the caller counts
// its own push / jsr / stack fix-up. `cy` is any counter with run/one/br/add
// (package D's Cy, or package B's Clk when call 10 prints a score).
// --------------------------------------------------------------------------
const State = @import("state.zig");
const cyc = @import("cyc.zig");
const St = State.St;
const V = State.V;
const BASE = State.BASE;
const M32 = State.M32;
const shr = State.shr;

const TEXT_MODE: i64 = 0x0E7F; // b7: 8x8 font, b4: paper on
const FONT_SMALL: i64 = BASE + 0x84E4;
const FONT_BIG: i64 = BASE + 0x820C;

/// The compare chain at $075C: (code, address of its cmp.b).
const CODES = [_][2]i64{ .{ 1, 0x075C }, .{ 2, 0x0764 }, .{ 3, 0x076C }, .{ 4, 0x0774 }, .{ 5, 0x077C }, .{ 6, 0x0784 }, .{ 7, 0x078C }, .{ 8, 0x0794 }, .{ 9, 0x079C }, .{ 10, 0x07A4 }, .{ 13, 0x07AC } };

pub const XY = struct { addr: i64, shift: i64 };

/// $85F4 body (from its first instruction to the rts).
pub fn xy_to_screen(st: *St, cy: anytype, x: i64, y: i64) XY {
    cy.run(0x85F4, 0x8628);
    var a0 = (st.g(V.screen_base) + (((((y & 0xFFFF) * 0xA0) & 0xFFFF) ^ 0x8000) - 0x8000)) & M32;
    const q = @divFloor(x & 0xFFFF, 16);
    const r = @mod(x & 0xFFFF, 16);
    a0 = (a0 + ((((q * 8) & 0xFFFF) ^ 0x8000) - 0x8000)) & M32;
    return .{ .addr = a0, .shift = r };
}

/// One character cell: rows x 4 planes; returns the new a2.
fn glyph(st: *St, cy: anytype, a2_0: i64, d3: i64, rows: usize, a1: i64, mask0: i64, big: bool) i64 {
    var a2 = a2_0;
    const mode = st.rb(TEXT_MODE);
    const paper = st.rb(0x0E7E);
    const ink = st.rb(0x0E7D);
    const lo_sp: i64 = if (big) 0x086A else 0x07D2;
    const d5 = shr(mask0, d3) & M32;
    // move.l #mask,d5 ; lsr.l d3,d5
    cy.one(lo_sp);
    cy.add(cyc.shm(d3, true));
    const base: i64 = if (big) 0x0872 else 0x07DA; // row loop
    for (0..rows) |row| {
        const b = st.rd(a1 + @as(i64, @intCast(row)), 1);
        const d2 = shr(b << 24, d3) & M32;
        cy.run(base, base + 8); // clr.l, move.b (a1)+, lsl.l #8, swap
        cy.add(cyc.shm(d3, true)); // lsr.l d3,d2
        cy.one(base + 10); // clr.l d4
        const p = base + 12; // $7E6 / $87E: plane loop
        var q: i64 = 0;
        for (0..4) |d4| {
            cy.one(p); // btst #4,$e7f
            if (!cy.br(p + 8, mode & 0x10 == 0)) {
                cy.one(p + 10); // btst d4,$e7e
                if (!cy.br(p + 16, !State.bit(paper, @intCast(d4)))) {
                    st.wr(a2 + 8, 2, st.rd(a2 + 8, 2) | (d5 & 0xFFFF));
                    st.wr(a2, 2, st.rd(a2, 2) | shr(d5, 16));
                    cy.run(p + 18, p + 30); // or, swap, or, swap, bra
                } else {
                    const nd = ~d5 & M32;
                    st.wr(a2 + 8, 2, st.rd(a2 + 8, 2) & (nd & 0xFFFF));
                    st.wr(a2, 2, st.rd(a2, 2) & shr(nd, 16));
                    cy.run(p + 30, p + 44);
                }
            }
            q = p + 44; // $812 / $8AA
            cy.one(q); // btst d4,$e7d
            if (!cy.br(q + 6, !State.bit(ink, @intCast(d4)))) {
                st.wr(a2 + 8, 2, st.rd(a2 + 8, 2) | (d2 & 0xFFFF));
                st.wr(a2, 2, st.rd(a2, 2) | shr(d2, 16));
                cy.run(q + 8, q + 18); // or, swap, or (a2)+, bra
            } else {
                const nd = ~d2 & M32;
                st.wr(a2 + 8, 2, st.rd(a2 + 8, 2) & (nd & 0xFFFF));
                st.wr(a2, 2, st.rd(a2, 2) & shr(nd, 16));
                cy.run(q + 18, q + 30); // not, and, swap, and (a2)+, not
            }
            a2 = (a2 + 2) & M32;
            cy.run(q + 30, q + 38); // swap d2, addq.b, cmp.b
            _ = cy.br(q + 38, d4 < 3); // blt
        }
        a2 = (a2 + 0x98) & M32;
        cy.run(q + 40, q + 46); // adda.w #$98, subq.b
        _ = cy.br(q + 46, row < rows - 1); // bne
    }
    return a2;
}

pub fn print_text(st: *St, cy: anytype, s: i64) void {
    cy.run(0x073E, 0x0754); // movem, movea.l $28(a7), clr.l d3, move.b, movea.l
    var d3 = st.g(V.text_shift);
    var a2 = st.g(V.text_cursor);
    var p = s;
    while (true) {
        cy.run(0x0754, 0x0758); // clr.l d0, move.b (a0)+,d0
        const c = st.rd(p, 1);
        p += 1;
        if (cy.br(0x0758, c == 0)) break;
        var hit: ?i64 = null;
        for (CODES) |ca| {
            cy.one(ca[1]);
            if (cy.br(ca[1] + 4, c == ca[0])) {
                hit = ca[0];
                break;
            }
        }
        const h = hit orelse {
            cy.one(0x07B4); // btst #7,$e7f
            const big = st.rb(TEXT_MODE) & 0x80 != 0;
            _ = cy.br(0x07BC, big);
            const ch = (c - 0x20) & 0xFF;
            if (big) {
                cy.run(0x085A, 0x0868); // movea.l, sub.b, lsl.l #3, adda.w
                cy.one(0x0868); // moveq #8
                const a1 = (FONT_BIG + ch * 8) & M32;
                a2 = glyph(st, cy, a2, d3, 8, a1, 0xFC000000, true);
                a2 = (a2 - 0x500) & M32;
                d3 = (d3 + 6) & 0xFF;
                cy.run(0x08DA, 0x08E4);
                if (!cy.br(0x08E4, d3 & 0x10 == 0)) {
                    a2 = (a2 + 8) & M32;
                    d3 &= ~@as(i64, 0x10);
                    cy.run(0x08E6, 0x08EE);
                }
                cy.one(0x08EE); // bra.w $754
            } else {
                cy.run(0x07C0, 0x07D0); // movea.l, sub.b, mulu, adda.w
                cy.one(0x07D0); // moveq #5
                const a1 = (FONT_SMALL + ch * 5) & M32;
                a2 = glyph(st, cy, a2, d3, 5, a1, 0xF0000000, false);
                a2 = (a2 - 0x320) & M32;
                d3 = (d3 + 4) & 0xFF;
                cy.run(0x0842, 0x084C);
                if (!cy.br(0x084C, d3 & 0x10 == 0)) {
                    a2 = (a2 + 8) & M32;
                    d3 &= ~@as(i64, 0x10);
                    cy.run(0x084E, 0x0856);
                }
                cy.one(0x0856);
            }
            continue;
        };
        switch (h) {
            1 => {
                const x = st.rd(p, 2);
                const y = st.rd(p + 2, 2);
                p += 4;
                st.s(V.text_x, x);
                st.s(V.text_y, y);
                cy.run(0x0904, 0x092A); // 2 moves, movem, 2 pushes, clr.w, clr.l, jsr
                const xy = xy_to_screen(st, cy, x, y);
                a2 = xy.addr;
                d3 = (d3 & 0xFFFF0000) | xy.shift;
                cy.run(0x092A, 0x093A); // movea.l (a7)+, move.w (a7)+, adda.w, movem, bra.w
            },
            2 => {
                st.wb(0x0E7D, st.rd(p, 1));
                p += 1;
                cy.run(0x093A, 0x0944);
            },
            3 => {
                const v = st.rd(p, 1);
                p += 1;
                st.wb(TEXT_MODE, st.rb(TEXT_MODE) | 0x10);
                st.wb(0x0E7E, v);
                cy.run(0x0944, 0x0952);
                if (!cy.br(0x0952, v != 0)) {
                    st.wb(TEXT_MODE, st.rb(TEXT_MODE) & ~@as(i64, 0x10));
                    cy.run(0x0956, 0x0962);
                }
            },
            4 => cy.one(0x0962),
            5 => cy.one(0x0966),
            6 => cy.one(0x096A),
            7 => cy.one(0x096E),
            8 => {
                d3 = (d3 - 6) & M32;
                cy.one(0x0972);
                if (!cy.br(0x0974, d3 & 0x80000000 == 0)) {
                    d3 = (d3 + 0x10) & M32;
                    a2 = (a2 - 8) & M32;
                    cy.run(0x0978, 0x0988);
                }
            },
            9 => {
                const v = st.rd(p, 1);
                p += 1;
                cy.one(0x0988);
                if (cy.br(0x098A, v != 0)) {
                    st.wb(TEXT_MODE, st.rb(TEXT_MODE) | 0x80);
                    cy.run(0x0998, 0x09A4);
                } else {
                    st.wb(TEXT_MODE, st.rb(TEXT_MODE) & ~@as(i64, 0x80));
                    cy.run(0x098C, 0x0998);
                }
            },
            10 => cy.one(0x09A4),
            else => cy.one(0x09A8),
        }
    }
    cy.run(0x08F2, 0x0904); // store a2, d3, movem, rts
    st.s(V.text_cursor, a2);
    st.s(V.text_shift, d3 & 0xFF);
}
