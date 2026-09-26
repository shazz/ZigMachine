// --------------------------------------------------------------------------
// The high-score name entry (the model's d_gameover._name_entry and after).
// It never returns: each round it polls the keyboard ($4668), the joystick
// ($46CC, an IKBD interrogate and its busy-wait), burns $3E80 x 16 cycles and
// flashes colour 10 (Setcolor) -- until Return or fire, then jmp $6.
//
// Here it runs across host frames: loop() suspends at the top of a round once
// the machine is due to hand back to the host, and carries on from there. The
// joystick poll is flow_name_joy.zig.
// --------------------------------------------------------------------------
const joyin = @import("flow_name_joy.zig");
const State = @import("state.zig");
const cyc = @import("cyc.zig");
const sound = @import("sound.zig");
const keys = @import("keys.zig");
const text = @import("flow_text.zig");
const gameover = @import("flow_gameover.zig");
const St = State.St;
const V = State.V;
const Cy = cyc.Cy;
const BASE = State.BASE;
const P1 = State.P1;
const P2 = State.P2;
const M32 = State.M32;
const s8 = State.s8;

pub const NAME: i64 = 0x86E8; // the 16-character name
const TEXT_MODE: i64 = 0x0E7F;

pub const NameEntry = struct {
    cy: Cy,
    win: i64,
};

pub const Status = enum { suspended, restart };

/// Everything before the loop: silence, the new high score, the screen
/// cleared, the prompt, the blank name, the cursor box.
pub fn begin(st: *St, cy_in: *Cy, win: i64, ne: *NameEntry) void {
    ne.cy = cy_in.*;
    ne.win = win;
    const cy = &ne.cy;
    cy.run(0x4574, 0x457C); // addq.w #4,a7 ; push #$157d
    cy.one(0x457C);
    cy.flush();
    sound.dosound_silence(st); // Dosound(sfx 0's script): silence
    cy.add(300);
    st.wb(0x86DA, 0x20);
    for (0..7) |i| {
        const o: i64 = @intCast(i);
        st.wb(gameover.HI + o, st.rb(win + 0x3E + o));
    }
    cy.run(0x4582, 0x45A2);
    for (0..7) |i| {
        cy.run(0x45A2, 0x45A6);
        _ = cy.br(0x45A6, i < 6);
    }
    cy.run(0x45A8, 0x45B0); // clr.w -(a7), jsr $2e8
    gameover.clear_screen(st, cy, 0);
    cy.run(0x45B0, 0x45BC);
    if (!cy.br(0x45BC, win != P1)) {
        cy.run(0x45BE, 0x45CA);
        text.print_text(st, cy, BASE + 0x8653);
        cy.run(0x45CA, 0x45CE);
    } else {
        cy.run(0x45CE, 0x45DA);
        text.print_text(st, cy, BASE + 0x8693);
        cy.one(0x45DA);
    }
    cy.run(0x45DC, 0x45E6);
    for (0..16) |i| {
        st.wb(NAME + @as(i64, @intCast(i)), 0x20);
        cy.run(0x45E6, 0x45EC);
        _ = cy.br(0x45EC, i < 15);
    }
    st.wb(TEXT_MODE, st.rb(TEXT_MODE) | 0x10);
    st.wb(0x0E7E, 0);
    st.wb(0x0E7D, 6);
    st.wb(0x424E, 0);
    st.ww(0x0E64, 0);
    st.ww(0x0E66, 0x2000);
    st.ww(0x0E62, 0);
    cy.run(0x45EE, 0x4622); // ... bsr.w $47ec
    box(st, cy);
}

/// The rounds. `joy` = the two joystick bytes as the IKBD would deliver them
/// now (P1 = [0], P2 = [1]); the winner's port is read.
pub fn loop(st: *St, ne: *NameEntry, joy: *const [2]u8, limit: i64) Status {
    const cy = &ne.cy;
    while (true) {
        if (st.pacer.vbl >= limit) return .suspended;
        cy.one(0x4622); // bsr.b $4668
        if (keyboard(st, cy)) return .restart;
        cy.one(0x4624); // bsr.w $46cc
        const j: i64 = if (ne.win == P2) joy[1] else joy[0];
        if (joyin.joystick(st, cy, j)) return .restart;
        st.wb(0x0E5C, 1);
        cy.one(0x4628);
        while (true) {
            cy.one(0x4630); // move.w #$3e80,d0
            cy.add(0x3E80 * (4 + 12) - 4); // subq.w / bne, 16000 times
            st.set_d(0, 0, 2);
            cy.one(0x4638); // bsr.b $4644
            flash(st, cy);
            const n = (st.rb(0x0E5C) - 1) & 0xFF;
            st.wb(0x0E5C, n);
            cy.one(0x463A);
            if (!cy.br(0x4640, n != 0)) break;
        }
        cy.one(0x4642); // bra.b $4622
    }
}

/// $4644: Setcolor(10, $400 | ($0E5A & 7)) -- the old colour comes back in d0.
fn flash(st: *St, cy: *Cy) void {
    const v = (st.rw(0x0E5A) + 1) & 0xFFFF;
    st.ww(0x0E5A, v);
    cy.run(0x4644, 0x4662);
    cy.flush();
    st.regs[0] = st.pal[10];
    st.pal[10] = @intCast((0x400 | (v & 7)) & 0x777);
    cy.add(300);
    cy.run(0x4664, 0x4668);
}

/// $4668. True when it left the call (jmp $6).
fn keyboard(st: *St, cy: *Cy) bool {
    cy.run(0x4668, 0x4670);
    var d0 = keys.bconstat(st, cy);
    st.regs[0] = d0;
    cy.run(0x4672, 0x467E);
    if (cy.br(0x467E, d0 != M32)) {
        cy.one(0x46CA);
        return false;
    }
    cy.run(0x4680, 0x4688);
    d0 = keys.bconin(st, cy);
    st.regs[0] = d0;
    var c = d0 & 0xFF;
    cy.run(0x468A, 0x4694);
    if (cy.br(0x4694, c == 8)) return left(st, cy);
    cy.one(0x4698);
    if (cy.br(0x469C, c == 0x0D)) return enter(st, cy);
    cy.one(0x46A0);
    if (!cy.br(0x46A4, c == 0x20)) {
        cy.one(0x46A6);
        if (!cy.br(0x46AA, c < 0x61)) {
            c = (c - 0x20) & 0xFF;
            cy.one(0x46AC);
        }
        st.set_d(0, c, 1);
        cy.one(0x46B0);
        if (cy.br(0x46B4, s8(c) < 0x41)) {
            cy.one(0x46CA);
            return false;
        }
        cy.one(0x46B6);
        if (cy.br(0x46BA, s8(c) > 0x5A)) {
            cy.one(0x46CA);
            return false;
        }
    }
    st.wb(0x0E66, c);
    cy.run(0x46BC, 0x46C6); // move.b, bsr.w $483a
    put_char(st, cy);
    cy.one(0x46C6); // bra.w $47c0
    return right(st, cy);
}

pub fn left(st: *St, cy: *Cy) bool {
    const v = (st.rw(0x0E62) - 1) & 0xFFFF;
    st.ww(0x0E62, v);
    cy.one(0x47A8);
    if (cy.br(0x47AE, v & 0x8000 == 0)) {
        box(st, cy);
        return false;
    }
    st.ww(0x0E62, 0);
    cy.run(0x47B0, 0x47B8);
    return false;
}

pub fn right(st: *St, cy: *Cy) bool {
    const v = (st.rw(0x0E62) + 1) & 0xFFFF;
    st.ww(0x0E62, v);
    cy.run(0x47C0, 0x47CE);
    if (cy.br(0x47CE, v < 0x10)) {
        box(st, cy);
        return false;
    }
    st.ww(0x0E62, 0x0F);
    cy.run(0x47D0, 0x47DA);
    return false;
}

pub fn enter(st: *St, cy: *Cy) bool {
    cy.one(0x47DA);
    if (cy.br(0x47E0, st.rw(0x0E64) == 0)) {
        cy.one(0x46CA);
        return false;
    }
    cy.run(0x47E4, 0x47EC); // addq.w #4,a7 ; jmp $6
    st.exit = .restart;
    cy.done();
    return true;
}

/// $47EC: the 16-slot underline row, the cursor slot raised.
fn box(st: *St, cy: *Cy) void {
    cy.run(0x47EC, 0x4802);
    var a = st.g(V.screen_base) + 0x57B0;
    var a1 = a;
    for (0..8) |i| {
        st.wr(a, 4, 0xFEFEFEFE);
        st.wr(a + 4, 4, 0);
        a += 8;
        cy.run(0x4802, 0x4808);
        _ = cy.br(0x4808, i < 7);
    }
    var d2 = st.rw(0x0E62);
    cy.run(0x480A, 0x4814);
    var d0: i64 = undefined;
    var d1: i64 = undefined;
    if (!cy.br(0x4814, d2 & 1 != 0)) {
        d0 = 0x00FEFEFE;
        d1 = 0x0000FE00;
        cy.run(0x4816, 0x4824);
    } else {
        d0 = 0xFE00FEFE;
        d1 = 0x000000FE;
        cy.run(0x4824, 0x4830);
    }
    d2 = ((d2 & ~@as(i64, 1)) << 2) & 0xFFFF;
    a1 = (a1 + State.s16(d2)) & M32;
    st.wr(a1, 4, d0);
    st.wr(a1 + 4, 4, d1);
    cy.run(0x4830, 0x483A);
    st.regs[0] = d0;
    st.regs[1] = d1;
    st.regs[2] = d2;
    st.set_a(0, a);
    st.set_a(1, a1 + 4);
}

/// $483A: the name letter at the cursor, printed in the 8x8 font.
pub fn put_char(st: *St, cy: *Cy) void {
    cy.run(0x483A, 0x4850);
    var d2 = st.rw(0x0E62);
    st.wb(NAME + State.s16(d2), st.rb(0x0E66));
    cy.run(0x4850, 0x485C);
    if (!cy.br(0x485C, d2 & 1 != 0)) {
        st.s(V.text_shift, 1);
        cy.run(0x485E, 0x4868);
    } else {
        st.s(V.text_shift, 9);
        cy.one(0x4868);
    }
    d2 = ((d2 & ~@as(i64, 1)) << 2) & 0xFFFF;
    const a1 = (st.g(V.screen_base) + 0x52B0 + State.s16(d2)) & M32;
    st.s(V.text_cursor, a1);
    cy.run(0x4870, 0x4886);
    text.print_text(st, cy, BASE + 0x0E66);
    cy.run(0x4886, 0x488A);
    st.set_d(2, d2, 2);
    st.set_a(1, a1);
    st.set_a(2, BASE + NAME);
}
