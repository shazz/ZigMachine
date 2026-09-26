// --------------------------------------------------------------------------
// Call 4, $26A4: the die / egg / hatch driver (the model's a_eggs.py).
//
// For every slot whose +$1E sequence timer runs: copy its aux sprite
// (+$2A/+$2E/+$20/+$22/+$32/+$33) to $0E56/$0E5E/$0E5A/$0E5C/$0E64/$0E62,
// then by +$1E:
//   $24          sinking in the lava (shrink, move down; at 0: erase, stop)
//   $21          egg resting (wave-3 bridge check $2798, hatch countdown +$1F)
//   $22,$23,>$24 egg flying: $2B0C landing (eggs_land.zig), egg physics
//   $0B          hatch jump (the knight pops up 4 lines)
//   5            hatched: becomes a riderless mount's rider (flags from +$34)
//   < $21 other  count down the anim table $1AC2 (sprite, $2936 draw / $29A2 redraw)
// A label machine like riders_move.zig; the hatch, the countdown and the aux
// sprite's draw are eggs_seq.zig.
// --------------------------------------------------------------------------
const seq = @import("eggs_seq.zig");
const State = @import("state.zig");
const cyc = @import("cyc.zig");
const aux = @import("riders_aux.zig");
const land = @import("eggs_land.zig");
const St = State.St;
const V = State.V;
const Cy = cyc.Cy;
const BASE = State.BASE;
const M32 = State.M32;
const s8 = State.s8;
const s16 = State.s16;
const setw = State.setw;

const END = BASE + 0x13E8;

pub fn o_of(st: *St) i64 {
    return st.regs[8] - BASE;
}

fn L26AA(st: *St, cy: *Cy) u32 {
    cy.run(0x26AA, 0x26AE);
    if (cy.br(0x26AE, st.rb(o_of(st) + 0x1E) != 0)) return 0x26BE;
    return 0x26B0;
}

fn L26B0(st: *St, cy: *Cy) u32 {
    const R = &st.regs;
    cy.run(0x26B0, 0x26BA);
    R[8] = (R[8] + 0x4E) & M32;
    if (cy.br(0x26BA, R[8] != END)) return 0x26AA;
    cy.run(0x26BC, 0x26BE);
    return 0;
}

fn L26BE(st: *St, cy: *Cy) u32 {
    const o = o_of(st);
    cy.run(0x26BE, 0x26F4);
    st.s(V.tmp_sprite_e5e, st.rl(o + 0x2E));
    st.s(V.tmp_ptr_e56, st.rl(o + 0x2A));
    st.ww(0x0E5A, st.rw(o + 0x20));
    st.ww(0x0E5C, st.rw(o + 0x22));
    st.wb(0x0E64, st.rb(o + 0x32));
    st.wb(0x0E62, st.rb(o + 0x33));
    const t = st.rb(o + 0x1E);
    if (cy.br(0x26F4, t == 0x24)) return 0x2770;
    cy.run(0x26F8, 0x26FE);
    if (cy.br(0x26FE, t == 0x21)) return 0x2798;
    if (cy.br(0x2702, s8(t) < 0x21)) return 0x2816;
    return 0x2706;
}

fn L2706(st: *St, cy: *Cy) u32 {
    cy.run(0x2706, 0x270A); // bsr.w $2B0C
    return land.egg_land(st, cy);
}

pub fn L270A(st: *St, cy: *Cy) u32 {
    const R = &st.regs;
    const o = o_of(st);
    cy.run(0x270A, 0x270E);
    const v = (st.rb(o + 0x29) - 1) & 0xFF;
    st.wb(o + 0x29, v);
    if (!cy.br(0x270E, v != 0)) {
        cy.run(0x2710, 0x271C);
        st.wb(o + 0x29, 6);
        if (!cy.br(0x271C, st.rw(o + 0x26) == 4)) {
            cy.run(0x271E, 0x2722);
            st.ww(o + 0x26, st.rw(o + 0x26) + 1);
        }
    }
    cy.run(0x2722, 0x272E);
    const d0 = st.rw(o + 0x24);
    var t = s16(st.rw(0x0E5A)) + s16(d0);
    st.ww(0x0E5A, t);
    if (!cy.br(0x272E, t >= 0)) {
        cy.run(0x2730, 0x273A);
        st.ww(0x0E5A, st.rw(0x0E5A) + 0x140);
    } else {
        cy.run(0x273A, 0x2742);
        if (!cy.br(0x2742, s16(st.rw(0x0E5A)) < 0x140)) {
            cy.run(0x2744, 0x274C);
            st.ww(0x0E5A, st.rw(0x0E5A) - 0x140);
        }
    }
    cy.run(0x274C, 0x2756);
    const vy = st.rw(o + 0x26);
    R[0] = vy;
    t = s16(st.rw(0x0E5C)) + s16(vy);
    st.ww(0x0E5C, t);
    if (cy.br(0x2756, t >= 0)) return 0x293E;
    cy.run(0x275A, 0x2764);
    st.ww(0x0E5C, 0);
    if (cy.br(0x2764, s16(st.rw(o + 0x26)) >= 0)) return 0x293E;
    cy.run(0x2768, 0x2770);
    st.ww(o + 0x26, -st.rw(o + 0x26));
    return 0x293E;
}

fn L2770(st: *St, cy: *Cy) u32 {
    const o = o_of(st);
    cy.run(0x2770, 0x2776);
    const h = (st.rb(0x0E64) - 1) & 0xFF;
    st.wb(0x0E64, h);
    if (!cy.br(0x2776, h == 0)) {
        cy.run(0x2778, 0x278C);
        st.ww(0x0E5C, st.rw(0x0E5C) + 1);
        st.s(V.tmp_ptr_e56, (st.g(V.tmp_ptr_e56) + 0xA0) & M32);
        return 0x29A2;
    }
    cy.run(0x278C, 0x2794);
    st.wb(o + 0x1E, 0);
    aux.aux_erase(st, cy);
    cy.run(0x2794, 0x2798);
    return 0x26B0;
}

fn L2798(st: *St, cy: *Cy) u32 {
    const R = &st.regs;
    const o = o_of(st);
    cy.run(0x2798, 0x27A0);
    if (!cy.br(0x27A0, st.g(V.wave) != 3)) {
        cy.run(0x27A2, 0x27B2);
        const d0 = (st.g(V.screen_base) + 0x6380) & M32;
        R[0] = d0;
        if (!cy.br(0x27B2, d0 >= st.rl(o + 0x2A))) {
            cy.run(0x27B4, 0x27BE);
            const px = s16(st.rw(o + 0x20));
            R[0] = setw(R[0], st.rw(0x1826));
            var go = cy.br(0x27BE, s16(st.rw(0x1826)) >= px);
            if (!go) {
                cy.run(0x27C0, 0x27CA);
                R[0] = setw(R[0], st.rw(0x1828));
                go = !cy.br(0x27CA, s16(st.rw(0x1828)) >= px);
            }
            if (go) {
                cy.run(0x27CC, 0x27DC);
                st.wb(o + 0x1E, 0x22);
                st.wb(o + 0x1F, 0x5B);
                return 0x2706;
            }
        }
    }
    cy.run(0x27DC, 0x27E4);
    if (!cy.br(0x27E4, s8(st.g(V.live_objects)) >= 8)) {
        cy.run(0x27E6, 0x27EA);
        const v = (st.rb(o + 0x1F) - 1) & 0xFF;
        st.wb(o + 0x1F, v);
        if (!cy.br(0x27EA, v != 0)) {
            cy.run(0x27EC, 0x27F8);
            st.wb(o + 0x1E, 0x12);
            st.s(V.live_objects, st.g(V.live_objects) + 1);
        }
    }
    return 0x27F8;
}

fn step(st: *St, cy: *Cy, pc: u32) u32 {
    return switch (pc) {
        0x26AA => L26AA(st, cy),
        0x26B0 => L26B0(st, cy),
        0x26BE => L26BE(st, cy),
        0x2706 => L2706(st, cy),
        0x270A => L270A(st, cy),
        0x2770 => L2770(st, cy),
        0x2798 => L2798(st, cy),
        0x27F8 => seq.L27F8(st, cy),
        0x2816 => seq.L2816(st, cy),
        0x2914 => seq.L2914(st, cy),
        0x2936 => seq.L2936(st, cy),
        0x293E => seq.L293E(st, cy),
        0x29A2 => seq.L29A2(st, cy),
        0x29B6 => seq.L29B6(st, cy),
        else => blk: {
            st.oob += 1;
            break :blk 0;
        },
    };
}

/// Call 4.
pub fn call_26a4_die_egg_hatch(st: *St) void {
    var cy = Cy.init(st);
    cy.add(20); // jsr
    cy.run(0x26A4, 0x26AA);
    st.regs[8] = BASE + 0x0FA4;
    var pc: u32 = 0x26AA;
    while (pc != 0) pc = step(st, &cy, pc);
    cy.done();
}
