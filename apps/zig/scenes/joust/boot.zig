// --------------------------------------------------------------------------
// The start-up $0086 (transcribed from the 68000 with its cycles; the model
// starts after the title): Getrez, the desktop palette saved (Setcolor -1 x16),
// Super, the keyclick off, Kbdvbase (joyvec -> $02E0, mousevec -> $02D8), IKBD
// $15 (joystick interrogate mode), Setscreen low res, Physbase, JOUST.MUR into
// the BSS and HIGH.SCO into $86E8.
//
// There is no TOS here: each trap does what the harness's TOS shim does and
// costs what it charges (GEMDOS 600, BIOS/XBIOS 300, Ikbdws +40 a byte, Fread
// +1 per 4 bytes read). The monochrome check and the dead disk protection are
// skipped exactly as this build skips them.
// --------------------------------------------------------------------------
const State = @import("state.zig");
const cyc = @import("cyc.zig");
const St = State.St;
const V = State.V;
const Cy = cyc.Cy;
const BASE = State.BASE;

pub const STACK_TOP: i64 = 0xF0000;
const KBDVECS: i64 = 0x0E00;
const XBIOS: i64 = 300;
const GEMDOS: i64 = 600;

/// $0086..$02B8 body (after the jsr).
pub fn init(st: *St, cy: *Cy) void {
    cy.run(0x0086, 0x008A);
    cy.add(XBIOS); // Getrez
    st.regs[0] = 0;
    cy.run(0x008C, 0x0092);
    _ = cy.br(0x0092, true); // bne.w $144: colour
    st.s(V.saved_rez, 0);
    st.ww(0x0E5A, 0);
    st.wl(0x0E56, BASE + 0x0D66); // relocated, like every address immediate
    cy.run(0x0144, 0x015A);
    for (0..16) |n| { // Setcolor(n, -1): the desktop palette, saved at $0D66
        cy.run(0x015A, 0x0168);
        cy.add(XBIOS);
        st.regs[0] = st.pal[n];
        const a0 = st.rl(0x0E56);
        st.wr(a0, 2, st.regs[0]);
        st.wl(0x0E56, a0 + 2);
        st.ww(0x0E5A, st.rw(0x0E5A) + 1);
        st.set_a(0, a0 + 2);
        cy.run(0x016A, 0x0188);
        _ = cy.br(0x0188, n < 15);
    }
    cy.run(0x018A, 0x0190);
    cy.add(GEMDOS); // Super(0): d0 = the old stack
    st.regs[0] = (STACK_TOP - 8 - 4 - 6) & State.M32;
    cy.run(0x0192, 0x01A6);
    st.s(V.saved_conterm, 0); // the byte at $484 as the harness leaves it (it writes the word $0007 there)
    cy.run(0x01A6, 0x01AC);
    cy.add(XBIOS); // Kbdvbase
    st.regs[0] = KBDVECS;
    cy.run(0x01AE, 0x01D2);
    st.set_a(0, KBDVECS);
    st.s(V.saved_mousevec, 0x0E3E); // the vectors TOS had (an rts in the harness)
    st.s(V.saved_joyvec, 0x0E3E);
    cy.run(0x01D2, 0x01DE);
    cy.add(XBIOS + 40); // Ikbdws($15): joystick interrogate mode
    cy.run(0x01E0, 0x01F4);
    cy.add(XBIOS); // Setscreen(-1, -1, 0)
    cy.run(0x01F6, 0x0200);
    cy.add(XBIOS); // Physbase
    st.regs[0] = State.SCREEN;
    st.s(V.screen_base, State.SCREEN);
    cy.run(0x0202, 0x020C);
    cy.run(0x022A, 0x0238); // bra.b $22a (the protection's jsr skipped)
    cy.add(GEMDOS); // Fopen JOUST.MUR -> handle 6
    st.regs[0] = 6;
    cy.run(0x023A, 0x0242);
    _ = cy.br(0x0242, false);
    st.ww(0x0E5A, 6);
    cy.run(0x0244, 0x0256);
    cy.add(GEMDOS + 32000 / 4); // Fread 32000 bytes into the BSS (loaded with the image)
    st.regs[0] = 32000;
    cy.run(0x0258, 0x0266);
    cy.add(GEMDOS); // Fclose
    st.regs[0] = 0;
    cy.run(0x0268, 0x0278);
    cy.add(GEMDOS); // Fopen HIGH.SCO -> handle 7
    st.regs[0] = 7;
    cy.run(0x027A, 0x0282);
    _ = cy.br(0x0282, false);
    st.ww(0x0E5A, 7);
    cy.run(0x0284, 0x0296);
    cy.add(GEMDOS + 26 / 4); // Fread the 26 bytes of HIGH.SCO
    for (State.HIGH_SCO, 0..) |b, i| st.wb(0x86E8 + @as(i64, @intCast(i)), b);
    st.regs[0] = 26;
    cy.run(0x0298, 0x02AE);
    st.wb(0x86DA, 0x20);
    cy.add(GEMDOS); // Fclose
    st.regs[0] = 0;
    cy.run(0x02B0, 0x02B8);
    st.s(V.two_player, 0);
    cy.one(0x02B8); // rts
}
