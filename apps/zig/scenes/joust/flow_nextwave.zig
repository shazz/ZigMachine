// --------------------------------------------------------------------------
// $71A6, the next wave (the model's d_waves.next_wave and after): the wave
// number (after 50 it loops to 41), the lava, the lava bridge (waves 3-4),
// the platforms from the wave table $1BC6, the eggs of the egg wave
// (flow_eggwave.zig), the enemy speeds and records, the pterodactyl period.
// --------------------------------------------------------------------------
const eggwave = @import("flow_eggwave.zig");
const State = @import("state.zig");
const cyc = @import("cyc.zig");
const core = @import("core.zig");
const St = State.St;
const V = State.V;
const Cy = cyc.Cy;
const BASE = State.BASE;
const P1 = State.P1;
const P2 = State.P2;
const M32 = State.M32;

/// $05EA with its exact cycles (the wrap uses the caller's d0).
pub fn rng_exact(st: *St, cy: *Cy, d0: i64) void {
    const before = st.g(V.rng_ptr);
    core.rng_step(st, d0);
    cy.run(0x05EA, 0x05FA);
    const wrapped = ((before + 2) & M32) >= BASE + 0x7B84;
    if (!cy.br(0x05FA, !wrapped)) cy.run(0x05FC, 0x0616);
    cy.one(0x0616);
}

pub fn next_wave(st: *St, cy: *Cy) void {
    var w = (st.g(V.wave) + 1) & 0xFF;
    st.s(V.wave, w);
    cy.run(0x71A6, 0x71B4);
    if (!cy.br(0x71B4, w != 0x33)) {
        w = 0x29;
        st.s(V.wave, w);
        cy.one(0x71B6);
    }
    st.wb(0x0D35, st.rb(0x0D35) + 1);
    cy.run(0x71BE, 0x71CC);
    if (!cy.br(0x71CC, st.rb(0x0D35) != 0x3A)) {
        st.wb(0x0D35, 0x30);
        st.wb(0x0D34, st.rb(0x0D34) + 1);
        cy.run(0x71CE, 0x71E4);
        if (!cy.br(0x71E4, st.rb(0x0D34) != 0x21)) {
            st.wb(0x0D34, 0x31);
            cy.one(0x71E6);
        }
    }
    const ws = State.s8(w);
    cy.one(0x71EE);
    if (!cy.br(0x71F6, ws > 3)) {
        st.s(V.lava_lines, st.g(V.lava_lines) + 5);
        st.s(V.lava_delay, 7);
        cy.run(0x71F8, 0x7206);
    }
    cy.one(0x7206);
    if (!cy.br(0x720E, ws < 3)) {
        cy.one(0x7212);
        if (!cy.br(0x721A, ws > 4)) bridge(st, cy, w);
    }
    const d0 = platforms(st, cy, w);
    enemy_setup(st, cy, w, d0);
}

fn bridge(st: *St, cy: *Cy, w: i64) void {
    const b: i64 = 0x0DAA;
    st.set_a(0, BASE + b);
    st.ww(b, 1);
    st.ww(b + 2, 0);
    st.wl(b + 4, BASE + 0x8998);
    st.wl(b + 0x10, BASE + 0x8B48);
    st.wl(b + 8, 0x7398); // not relocated
    st.wl(b + 0x14, 0x7438);
    st.ww(b + 0x0E, 1);
    st.ww(b + 0x1A, 0xFFFF);
    st.ww(b + 0x0C, 0x0A);
    st.ww(b + 0x18, 0x0C);
    cy.run(0x721C, 0x726C);
    if (cy.br(0x726C, w == 3)) return;
    st.wl(b + 8, 0x73B0);
    st.wl(b + 0x14, 0x7428);
    st.ww(b + 0x0E, 0);
    st.ww(b + 0x1A, 0);
    st.ww(b + 0x0C, 0);
    st.ww(b + 0x18, 0x0A);
    cy.run(0x726E, 0x7292);
}

fn platforms(st: *St, cy: *Cy, w: i64) i64 {
    var d0 = st.regs[0];
    const ew = State.s8(w);
    d0 = (d0 & 0xFFFF0000) | (ew & 0xFFFF);
    d0 = ((d0 & 0xFFFF) * 4) & M32;
    const old = st.rb(0x0D94);
    st.wl(0x0D94, st.rl(0x1BC6 + State.s16(d0 & 0xFFFF)));
    const new = st.rb(0x0D94);
    const d2m = (~new) & 0xFF;
    var d1 = old & d2m;
    cy.run(0x7292, 0x72C4); // ... moveq #1,d2, movea.l #$13e8
    var d2: i64 = 1;
    var a: i64 = 0x13E8;
    while (true) {
        const c = d1 & 1;
        d1 >>= 1;
        cy.one(0x72C4); // lsr.b #1,d1
        if (!cy.br(0x72C6, c == 0)) {
            st.ww(a + 2, d2);
            a += 0x10;
            cy.run(0x72C8, 0x72D0);
        }
        d2 += 1;
        cy.run(0x72D0, 0x72D6);
        if (!cy.br(0x72D6, d2 != 9)) break;
    }
    cy.run(0x72D8, 0x72E4); // movea.l #$d38, move.b $d94,d0
    var v = new;
    for (0..8) |i| {
        st.wb(0x0D38 + @as(i64, @intCast(i)), v & 1);
        v >>= 1;
        cy.run(0x72E4, 0x72F2);
        _ = cy.br(0x72F2, i < 7);
    }
    d0 = (d0 & 0xFFFFFF00) | v;
    d1 = (d1 & 0xFFFFFF00) | st.rb(0x0D3F);
    st.set_d(1, d1, 1);
    st.regs[2] = 9;
    st.set_a(0, BASE + 0x0D40);
    return d0;
}

fn enemy_setup(st: *St, cy: *Cy, w: i64, d0_in: i64) void {
    var d0 = (d0_in & 0xFFFFFF00) | ((w >> 4) & 0x0F);
    d0 = (d0 & 0xFFFF0000) | (((d0 & 0xFFFF) + 1) & 0xFFFF);
    st.s(V.egg_hatch_speed, 5 - (d0 & 0xFF));
    st.wb(P1 + 0x35, 0);
    st.wb(P2 + 0x35, 0);
    st.ww(0x0D9E, 0);
    cy.run(0x72F4, 0x7332); // ... move.w #0,d0, move.b wave,d0, subq.b #4,d0
    const s = (w - 4) & 0xFF;
    d0 = s;
    if (!cy.br(0x7332, s & 0x80 == 0)) {
        d0 = 0;
        cy.one(0x7334);
    }
    d0 >>= 2;
    st.s(V.speed_bounder, d0);
    d0 >>= 1;
    st.s(V.speed_hunter, d0);
    d0 >>= 1;
    st.s(V.speed_shadow, d0);
    cy.run(0x7336, 0x734E);
    for ([_][2]i64{ .{ 0x0D98, 0x734E }, .{ 0x0D9A, 0x7366 }, .{ 0x0D9C, 0x737E } }) |oa| {
        const v = (st.rw(oa[0]) + 1) & 0xFFFF;
        st.ww(oa[0], v);
        cy.run(oa[1], oa[1] + 14);
        if (!cy.br(oa[1] + 14, State.s16(v) <= 4)) {
            st.ww(oa[0], 4);
            cy.one(oa[1] + 16);
        }
    }
    cy.one(0x7396);
    var a: i64 = 0x1040;
    while (a < 0x13E8) : (a += 2) {
        st.ww(a, 0);
        cy.run(0x739C, 0x73A4);
        _ = cy.br(0x73A4, a + 2 != 0x13E8);
    }
    st.s(V.materialise_busy, 0);
    st.s(V.spawn_pad_ptr, BASE + 0x19D2);
    cy.run(0x73A6, 0x73BC);
    st.set_a(0, BASE + 0x13E8);
    st.regs[0] = d0;
    if (!cy.br(0x73BC, st.g(V.cd_egg) != 0)) d0 = eggwave.eggs(st, cy, w, d0);
    ptero_and_records(st, cy, w, d0);
}

fn ptero_and_records(st: *St, cy: *Cy, w: i64, d0_in: i64) void {
    var d0 = d0_in;
    const per = (0x640 - ((w << 4) & 0xFFFF)) & 0xFFFF;
    st.s(V.ptero_period, per);
    st.s(V.ptero_timer, per);
    st.set_d(1, (w << 4) & 0xFFFF, 2);
    cy.run(0x74E6, 0x750E);
    for (0..4) |i| {
        st.ww(0x1428 + 0x20 * @as(i64, @intCast(i)), 0);
        cy.run(0x750E, 0x751C);
        _ = cy.br(0x751C, i < 3);
    }
    cy.one(0x751E);
    if (!cy.br(0x7524, st.g(V.cd_ptero) != 0)) {
        st.ww(0x1428, 1);
        cy.run(0x7526, 0x753A);
        if (!cy.br(0x753A, w <= 0x0F)) {
            st.s(V.ptero_timer, 0x30);
            cy.one(0x753C);
        }
    }
    var a: i64 = 0x1040;
    cy.one(0x7544);
    const kinds = [_][4]i64{ .{ 0x0D95, 0x81, 0x754A, 1 }, .{ 0x0D96, 0x82, 0x757C, 0 }, .{ 0x0D97, 0x83, 0x75AE, 1 } };
    for (kinds) |kd| {
        const cnt = kd[0];
        const kind = kd[1];
        const at = kd[2];
        const odd_taken = kd[3] != 0;
        cy.one(at);
        var n = st.rb(cnt);
        if (cy.br(at + 6, n == 0 or n & 0x80 != 0)) continue;
        while (true) {
            st.ww(a, kind);
            cy.run(at + 8, at + 22); // move.w #k, btst
            const odd = st.rb(cnt) & 1;
            const skip = if (odd_taken) odd == 0 else odd != 0;
            if (!cy.br(at + 22, skip)) {
                d0 = (d0 & 0xFFFF0000) | (st.rw(a) | 0x8000);
                st.ww(a, d0 & 0xFFFF);
                cy.run(at + 24, at + 36);
            }
            a += 0x4E;
            n = (st.rb(cnt) - 1) & 0xFF;
            st.wb(cnt, n);
            cy.run(at + 36, at + 48);
            if (!cy.br(at + 48, n != 0)) break;
        }
    }
    st.set_a(0, BASE + a);
    st.regs[0] = d0;
    cy.one(0x75E0);
}
