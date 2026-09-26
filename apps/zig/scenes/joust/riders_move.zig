// --------------------------------------------------------------------------
// Call 9, $2D8C: the rider update loop (the model's a_riders.py): physics and
// the platform landing $33F0. Continued in riders_draw.zig (the sprite choice,
// erase/draw), riders_edge.zig (edge bumps, lava, walking), riders_spawn.zig
// and riders_mat.zig (a free pad, materialising, the pad glow).
//
// A label machine, as the model: each Lxxxx runs the basic block(s) at $xxxx
// and returns the next label (0 = the final rts). d0 is the slot's flags word.
// --------------------------------------------------------------------------
const draw = @import("riders_draw.zig");
const State = @import("state.zig");
const cyc = @import("cyc.zig");
const sub = @import("riders_sub.zig");
const edge = @import("riders_edge.zig");
const spawn = @import("riders_spawn.zig");
const mat = @import("riders_mat.zig");
const St = State.St;
const V = State.V;
const Cy = cyc.Cy;
const BASE = State.BASE;
const M32 = State.M32;
const s8 = State.s8;
const s16 = State.s16;

const END = BASE + 0x13E8;

pub fn o_of(st: *St) i64 {
    return st.regs[8] - BASE;
}

// ---------------------------------------------------------------- loop head
pub fn L2D94(st: *St, cy: *Cy) u32 {
    const R = &st.regs;
    cy.run(0x2D94, 0x2DA0);
    R[8] = (R[8] + 0x4E) & M32;
    if (cy.br(0x2DA0, R[8] != END)) return 0x2DA4;
    cy.run(0x2DA2, 0x2DA4); // rts
    return 0;
}

fn L2DA4(st: *St, cy: *Cy) u32 {
    const R = &st.regs;
    const o = o_of(st);
    const d0 = st.rw(o);
    R[0] = d0;
    cy.run(0x2DA4, 0x2DAA);
    if (cy.br(0x2DAA, d0 == 0)) return 0x2D94;
    const tests = [_][3]i64{ .{ 0x2DAC, 14, 0x3126 }, .{ 0x2DB4, 8, 0x3290 }, .{ 0x2DBC, 7, 0x3466 }, .{ 0x2DC4, 9, 0x32F0 } };
    for (tests) |t| {
        cy.run(t[0], t[0] + 4);
        if (cy.br(t[0] + 4, State.bit(d0, t[1]))) return @intCast(t[2]);
    }
    cy.run(0x2DCC, 0x2DD0);
    if (cy.br(0x2DD0, d0 & 0x10 == 0)) {
        cy.run(0x2DEE, 0x2DF2);
        const tv = st.rw(o + 0xC);
        if (cy.br(0x2DF2, tv == 0)) return 0x2E00;
        if (cy.br(0x2DF4, s16(tv) > 0)) {
            cy.run(0x2DFC, 0x2E00);
            R[0] = d0 | 0x8000;
            return 0x2E00;
        }
        cy.run(0x2DF6, 0x2DFC);
        R[0] = d0 & ~@as(i64, 0x8000);
        return 0x2E00;
    }
    cy.run(0x2DD2, 0x2DE2);
    st.ww(o + 6, 0);
    const d1 = st.rb(o + 0xB);
    R[1] = d1;
    if (cy.br(0x2DE2, s8(d1) <= s8(st.g(V.egg_hatch_speed)))) return 0x2E00;
    cy.run(0x2DE4, 0x2DEE);
    st.wb(o + 0xB, st.g(V.egg_hatch_speed));
    return 0x2E00;
}

fn L2E00(st: *St, cy: *Cy) u32 {
    const R = &st.regs;
    const o = o_of(st);
    var d0 = R[0];
    cy.run(0x2E00, 0x2E04);
    if (cy.br(0x2E04, d0 & 0x800 == 0)) return 0x2E62;
    cy.run(0x2E06, 0x2E0A);
    if (cy.br(0x2E0A, d0 & 0x400 != 0)) return 0x2E66;
    cy.run(0x2E0C, 0x2E16);
    d0 = d0 | 0x400;
    R[0] = d0;
    if (!cy.br(0x2E16, R[8] >= BASE + 0x1040)) sub.sfx_site(st, cy, 0xA, 0x2E18, 0x2E26);
    cy.run(0x2E26, 0x2E2A);
    if (!cy.br(0x2E2A, d0 & 0x10 != 0)) {
        cy.run(0x2E2C, 0x2E30);
        const tv = st.rw(o + 0xC);
        if (!cy.br(0x2E30, tv == 0)) {
            cy.run(0x2E32, 0x2E3C);
            const vx = st.rw(o + 6);
            R[1] = vx;
            if (!cy.br(0x2E3C, vx == tv)) {
                if (cy.br(0x2E3E, s16(vx) > s16(tv))) {
                    cy.run(0x2E46, 0x2E4A);
                    st.ww(o + 6, vx - 1);
                } else {
                    cy.run(0x2E40, 0x2E46);
                    st.ww(o + 6, vx + 1);
                }
            }
        }
    }
    cy.run(0x2E4A, 0x2E56);
    var d1 = (st.rw(o + 8) - 2) & 0xFFFF;
    if (!cy.br(0x2E56, s16(d1) >= -4)) {
        cy.run(0x2E58, 0x2E5C);
        d1 = 0xFFFC;
    }
    R[1] = d1;
    cy.run(0x2E5C, 0x2E62);
    st.ww(o + 8, d1);
    return 0x2E88;
}

fn L2E62(st: *St, cy: *Cy) u32 {
    cy.run(0x2E62, 0x2E66);
    st.regs[0] &= ~@as(i64, 0x400);
    return 0x2E66;
}

fn L2E66(st: *St, cy: *Cy) u32 {
    const R = &st.regs;
    const o = o_of(st);
    cy.run(0x2E66, 0x2E6A);
    const v = (st.rb(o + 0xB) - 1) & 0xFF;
    st.wb(o + 0xB, v);
    if (cy.br(0x2E6A, v != 0)) return 0x2E88;
    cy.run(0x2E6C, 0x2E80);
    st.wb(o + 0xB, 5);
    const vy = (st.rw(o + 8) + 1) & 0xFFFF;
    st.ww(o + 8, vy);
    R[1] = vy;
    if (cy.br(0x2E80, s16(vy) <= 4)) return 0x2E88;
    cy.run(0x2E82, 0x2E88);
    st.ww(o + 8, 4);
    return 0x2E88;
}

pub fn L2E88(st: *St, cy: *Cy) u32 {
    const R = &st.regs;
    const o = o_of(st);
    cy.run(0x2E88, 0x2E92);
    const vy = st.rw(o + 8);
    R[1] = vy;
    const t = s16(st.rw(o + 4)) + s16(vy);
    st.ww(o + 4, t);
    if (!cy.br(0x2E92, t >= 0)) {
        cy.run(0x2E94, 0x2EA0);
        st.ww(o + 4, 0);
        st.ww(o + 8, -vy);
        return 0x2EB6;
    }
    cy.run(0x2EA0, 0x2EAA);
    R[1] = 0xB4;
    if (cy.br(0x2EAA, 0xB4 >= s16(st.rw(o + 4)))) return 0x2EB6;
    cy.run(0x2EAC, 0x2EB6);
    st.ww(o + 4, 0xB4);
    st.ww(o + 8, 0);
    return 0x2EB6;
}

pub fn L2EB6(st: *St, cy: *Cy) u32 {
    const R = &st.regs;
    const o = o_of(st);
    cy.run(0x2EB6, 0x2EC0);
    const vx = st.rw(o + 6);
    R[1] = vx;
    const t = s16(st.rw(o + 2)) + s16(vx);
    st.ww(o + 2, t);
    if (!cy.br(0x2EC0, t >= 0)) {
        cy.run(0x2EC2, 0x2ECA);
        st.ww(o + 2, st.rw(o + 2) + 0x140);
        return 0x2EDA;
    }
    cy.run(0x2ECA, 0x2ED2);
    const x = st.rw(o + 2);
    R[1] = x;
    if (cy.br(0x2ED2, s16(x) <= 0x13F)) return 0x2EDA;
    cy.run(0x2ED4, 0x2EDA);
    st.ww(o + 2, x - 0x140);
    return 0x2EDA;
}

fn L2EDA(st: *St, cy: *Cy) u32 {
    cy.run(0x2EDA, 0x2EDE); // bsr.w $33F0
    landing(st, cy);
    return 0x2EDE;
}

/// $33F0: the platform landing test against the surfaces $1822 (enabled by $0D38..).
fn landing(st: *St, cy: *Cy) void {
    const R = &st.regs;
    const o = o_of(st);
    cy.run(0x33F0, 0x33FE);
    var a1: i64 = 0x1822;
    var a2: i64 = 0x0D38;
    const d0 = R[0];
    var d3: i64 = 0;
    while (true) {
        cy.run(0x33FE, 0x3400);
        const on = st.rb(a2);
        a2 += 1;
        var hit = false;
        if (cy.br(0x3400, on == 0)) {} else {
            cy.run(0x3402, 0x3408);
            const y = st.rw(o + 4);
            d3 = y;
            if (cy.br(0x3408, s16(y) < s16(st.rw(a1)))) {} else {
                cy.run(0x340A, 0x340E);
                if (cy.br(0x340E, s16(y) > s16(st.rw(a1 + 2)))) {} else {
                    cy.run(0x3410, 0x3418);
                    const x = st.rw(o + 2);
                    d3 = x;
                    if (cy.br(0x3418, s16(x) < s16(st.rw(a1 + 4)))) {} else {
                        cy.run(0x341A, 0x341E);
                        hit = !cy.br(0x341E, s16(x) > s16(st.rw(a1 + 6)));
                    }
                }
            }
        }
        if (hit) {
            cy.run(0x3420, 0x342E);
            st.ww(o + 4, st.rw(a1));
            R[0] = d0 | 0x200;
            R[1] = 4;
            if (!cy.br(0x342E, st.rw(o + 0xE) != 4)) {
                cy.run(0x3430, 0x3434);
                st.ww(o + 4, st.rw(o + 4) + 1);
            }
            cy.run(0x3434, 0x3436);
            break;
        }
        cy.run(0x3436, 0x3442);
        a1 += 8;
        if (cy.br(0x3442, a1 != 0x1862)) continue;
        cy.run(0x3444, 0x3448);
        if (!cy.br(0x3448, d0 & 0x200 != 0)) {
            cy.run(0x344A, 0x344C);
            break;
        }
        cy.run(0x344C, 0x3466);
        st.wb(o + 0xA, 3);
        st.ww(o + 0xE, 0);
        st.wb(o + 0xB, 5);
        st.ww(o + 8, 0);
        R[0] = d0 & ~@as(i64, 0x200);
        break;
    }
    R[3] = d3;
    R[9] = BASE + a1;
    R[10] = BASE + a2;
}

// ---------------------------------------------------------------- sprite choice
// ---------------------------------------------------------------- position, erase, draw
fn step(st: *St, cy: *Cy, pc: u32) u32 {
    return switch (pc) {
        0x2D94 => L2D94(st, cy),
        0x2DA4 => L2DA4(st, cy),
        0x2E00 => L2E00(st, cy),
        0x2E62 => L2E62(st, cy),
        0x2E66 => L2E66(st, cy),
        0x2E88 => L2E88(st, cy),
        0x2EB6 => L2EB6(st, cy),
        0x2EDA => L2EDA(st, cy),
        0x2EDE => draw.L2EDE(st, cy),
        0x2F3C => draw.L2F3C(st, cy),
        0x302E => draw.L302E(st, cy),
        0x30B4 => draw.L30B4(st, cy),
        0x30E6 => draw.L30E6(st, cy),
        0x30F0 => draw.L30F0(st, cy),
        0x3126 => edge.L3126(st, cy),
        0x3290 => edge.L3290(st, cy),
        0x32F0 => edge.L32F0(st, cy),
        0x3466 => spawn.L3466(st, cy),
        0x35C0 => mat.L35C0(st, cy),
        0x362C => mat.L362C(st, cy),
        0x3698 => mat.L3698(st, cy),
        else => blk: {
            st.oob += 1;
            break :blk 0;
        },
    };
}

/// Call 9.
pub fn call_2d8c_riders(st: *St) void {
    var cy = Cy.init(st);
    cy.add(20); // jsr
    cy.run(0x2D8C, 0x2D94);
    st.regs[8] = BASE + 0x0FA4;
    var pc: u32 = 0x2DA4;
    while (pc != 0) pc = step(st, &cy, pc);
    cy.done();
}
