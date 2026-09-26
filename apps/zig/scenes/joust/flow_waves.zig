// --------------------------------------------------------------------------
// Call 15, $7B8E (the model's d_waves.py): the wave state machine $0D46 (0
// playing, 2 -> 1 banners, 1 -> 0 next wave), the four wave-type countdowns
// $0D40-$0D43, the banners and the bonuses. The next wave itself ($71A6) is
// in flow_nextwave.zig.
// --------------------------------------------------------------------------
const State = @import("state.zig");
const cyc = @import("cyc.zig");
const popups = @import("flow_popups.zig");
const score = @import("flow_score.zig");
const nextwave = @import("flow_nextwave.zig");
const St = State.St;
const V = State.V;
const Cy = cyc.Cy;
const BASE = State.BASE;
const P1 = State.P1;
const P2 = State.P2;

/// A message record's fields; null = not written.
pub const Fill = struct {
    text: ?i64 = null,
    off: ?i64 = null,
    kind: ?i64 = null,
    timer: ?i64 = null,
    ink: ?i64 = null,
    shift: ?i64 = null,
};

/// Write a message record at TEXT offset a (null: the original writes into
/// low RAM at 0..$b, outside everything the model holds).
pub fn fill(st: *St, a: ?i64, f: Fill) void {
    const p = a orelse return;
    if (f.text) |v| st.wl(p + 8, BASE + v);
    if (f.off) |v| st.wl(p + 4, st.g(V.screen_base) + v);
    if (f.kind) |v| st.wb(p, v);
    if (f.timer) |v| st.wb(p + 1, v);
    if (f.ink) |v| st.wb(p + 2, v);
    if (f.shift) |v| st.wb(p + 3, v);
}

/// jsr $44f0 at jsr_at, then the straight-line fill [lo, hi).
pub fn new(st: *St, cy: *Cy, jsr_at: i64, lo: i64, hi: i64, f: Fill) ?i64 {
    cy.one(jsr_at);
    const a = popups.alloc(st, cy);
    cy.run(lo, hi);
    fill(st, a, f);
    return a;
}

/// Call 15.
pub fn call_7b8e_waves(st: *St) void {
    var cy = Cy.init(st);
    cy.add(20);
    cy.one(0x7B8E);
    if (cy.br(0x7B94, st.g(V.phase) == 0)) phase0(st, &cy) else banner_phase(st, &cy);
    cy.done();
}

fn banner_phase(st: *St, cy: *Cy) void {
    cy.run(0x7B98, 0x7BA6); // movea.l, clr.l d0, move.b $d46,d0
    const ph = st.g(V.phase);
    st.regs[0] = ph;
    var a: i64 = 0x0E84;
    while (true) {
        cy.one(0x7BA6);
        if (cy.br(0x7BAA, st.rb(a) == ph)) {
            st.set_a(0, BASE + a);
            return showing(st, cy);
        }
        a += 12;
        cy.run(0x7BAE, 0x7BB8);
        if (!cy.br(0x7BB8, a != 0x0FA4)) break;
    }
    cy.one(0x7BBA);
    a = 0x1428;
    while (true) {
        cy.one(0x7BC0);
        if (cy.br(0x7BC4, st.rw(a) != 0)) {
            st.set_a(0, BASE + a);
            return showing(st, cy);
        }
        a += 0x20;
        cy.run(0x7BC8, 0x7BD2);
        if (!cy.br(0x7BD2, a != 0x14A8)) break;
    }
    st.set_a(0, BASE + a);
    cy.one(0x7BD4);
    if (!cy.br(0x7BDC, st.g(V.wave) != 3)) {
        cy.run(0x7BDE, 0x7BE8);
        st.set_a(0, BASE + 0x0DAA);
        const w = st.rw(0x0DAA);
        if (cy.br(0x7BE8, 0 < w and w < 0x8000)) return showing(st, cy);
    }
    st.s(V.phase, st.g(V.phase) - 1);
    cy.one(0x7BEC);
    if (cy.br(0x7BF2, st.g(V.phase) == 0)) return nextwave.next_wave(st, cy);
    banners(st, cy);
}

/// $7EFA: a banner (or a pterodactyl, or the lava bridge) is still up.
fn showing(st: *St, cy: *Cy) void {
    cy.one(0x7EFA);
    if (cy.br(0x7F02, st.g(V.phase) != 1)) return cy.one(0x7EF8);
    cy.one(0x7F04);
    if (cy.br(0x7F0A, st.g(V.wave) != 0)) return cy.one(0x7EF8);
    cy.run(0x7F0C, 0x7F18);
    st.set_a(0, BASE + 0x0E84);
    if (cy.br(0x7F18, st.rb(0x0E85) != 0x4B)) return cy.one(0x7EF8);
    cy.one(0x7F1A);
    const a = popups.alloc(st, cy);
    cy.one(0x7F20);
    if (cy.br(0x7F26, a == null)) return cy.one(0x7EF8);
    cy.run(0x7F28, 0x7F5A);
    fill(st, a, .{ .text = 0x879F, .off = 0x44F8, .kind = 1, .ink = 1, .timer = 0x4B, .shift = 9 });
}

/// Phase 2 -> 1: WAVE n and the wave-type banners; the countdowns tick.
fn banners(st: *St, cy: *Cy) void {
    cy.one(0x7BF6);
    const w = st.g(V.wave);
    if (!cy.br(0x7BFC, w != 0)) {
        cy.run(0x7BFE, 0x7C32);
        st.set_a(0, BASE + 0x0E84);
        fill(st, 0x0E84, .{ .text = 0x878C, .off = 0x3238, .shift = 0, .ink = 1, .kind = 1, .timer = 0x64 });
    }
    var a = new(st, cy, 0x7C32, 0x7C38, 0x7C62, .{ .text = 0x87AF, .off = 0x2C00, .ink = 1, .kind = 1, .timer = 0x64 });
    cy.one(0x7C62);
    if (cy.br(0x7C6A, w < 9)) {
        cy.one(0x7C74);
        fill(st, a, .{ .shift = 0x0B });
    } else {
        cy.run(0x7C6C, 0x7C74);
        fill(st, a, .{ .shift = 8 });
    }
    cy.one(0x7C7A);
    a = popups.alloc(st, cy);
    cy.one(0x7C80);
    if (!cy.br(0x7C86, a == null)) {
        cy.run(0x7C88, 0x7CB2);
        fill(st, a, .{ .text = 0x0D32, .off = 0x2C10, .ink = 1, .kind = 1, .timer = 0x64 });
        cy.one(0x7CB2);
        if (cy.br(0x7CBA, w < 9)) {
            cy.one(0x7CC4);
            fill(st, a, .{ .shift = 8 });
        } else {
            cy.run(0x7CBC, 0x7CC4);
            fill(st, a, .{ .shift = 0x0E });
        }
    }
    st.s(V.cd_egg, st.g(V.cd_egg) - 1);
    cy.one(0x7CCA);
    if (!cy.br(0x7CD0, st.g(V.cd_egg) != 0))
        _ = new(st, cy, 0x7CD2, 0x7CD8, 0x7D08, .{ .text = 0x8834, .off = 0x3240, .shift = 7, .timer = 0x64, .kind = 1, .ink = 1 });
    st.s(V.cd_survival_team, st.g(V.cd_survival_team) - 1);
    cy.one(0x7D08);
    if (!cy.br(0x7D0E, st.g(V.cd_survival_team) != 0)) {
        st.s(V.survival_lost, 0);
        cy.run(0x7D12, 0x7D20);
        if (cy.br(0x7D20, st.g(V.players) == 2)) {
            _ = new(st, cy, 0x7D5A, 0x7D60, 0x7D90, .{ .text = 0x87C6, .off = 0x3240, .shift = 4, .timer = 0x64, .kind = 1, .ink = 1 });
            _ = new(st, cy, 0x7D90, 0x7D96, 0x7DC6, .{ .text = 0x87D2, .off = 0x57A0, .shift = 0x0F, .timer = 0x64, .kind = 1, .ink = 1 });
        } else {
            _ = new(st, cy, 0x7D22, 0x7D28, 0x7D5A, .{ .text = 0x87B6, .off = 0x3238, .shift = 7, .timer = 0x64, .kind = 1, .ink = 1 });
        }
    }
    st.s(V.cd_ptero, st.g(V.cd_ptero) - 1);
    cy.one(0x7DC6);
    if (!cy.br(0x7DCC, st.g(V.cd_ptero) != 0)) {
        _ = new(st, cy, 0x7DCE, 0x7DD4, 0x7E04, .{ .text = 0x883F, .off = 0x3238, .shift = 2, .timer = 0x64, .kind = 1, .ink = 1 });
        _ = new(st, cy, 0x7E04, 0x7E0A, 0x7E3A, .{ .text = 0x8852, .off = 0x3858, .shift = 1, .timer = 0x64, .kind = 1, .ink = 1 });
    }
    st.s(V.cd_gladiator, st.g(V.cd_gladiator) - 1);
    cy.one(0x7E3A);
    if (cy.br(0x7E40, st.g(V.cd_gladiator) != 0)) return cy.one(0x7EF8);
    cy.one(0x7E44);
    if (cy.br(0x7E4C, st.g(V.players) != 2)) return cy.one(0x7EF8);
    st.s(V.team_flag, 0);
    cy.one(0x7E50);
    _ = new(st, cy, 0x7E56, 0x7E5C, 0x7E8C, .{ .text = 0x87F0, .off = 0x3238, .shift = 4, .timer = 0x64, .kind = 1, .ink = 1 });
    _ = new(st, cy, 0x7E8C, 0x7E92, 0x7EC2, .{ .text = 0x8801, .off = 0x57B0, .shift = 1, .timer = 0x64, .kind = 1, .ink = 1 });
    _ = new(st, cy, 0x7EC2, 0x7EC8, 0x7EF8, .{ .text = 0x8819, .off = 0x5CA8, .shift = 8, .timer = 0x64, .kind = 1, .ink = 1 });
    cy.one(0x7EF8);
}

fn phase0(st: *St, cy: *Cy) void {
    cy.one(0x7F5A);
    if (cy.br(0x7F60, st.g(V.busy_objects) != 0)) return cy.one(0x7EF8);
    cy.run(0x7F62, 0x7F70); // clr.l d0, move.b $d30,d0, cmp.b $d48,d0
    st.regs[0] = st.g(V.players);
    if (cy.br(0x7F70, st.g(V.players) != st.g(V.live_objects))) return cy.one(0x7EF8);
    st.s(V.phase, 2);
    cy.run(0x7F72, 0x7F80);
    if (cy.br(0x7F80, st.g(V.cd_survival_team) != 0)) return rearm(st, cy);
    st.s(V.cd_survival_team, 5);
    cy.run(0x7F84, 0x7F94);
    if (!cy.br(0x7F94, st.g(V.players) != 1)) {
        cy.one(0x7F98);
        if (!cy.br(0x7F9E, st.g(V.survival_lost) == 0)) {
            _ = new(st, cy, 0x7FA0, 0x7FA6, 0x7FD6, .{ .text = 0x88E9, .off = 0x5D58, .kind = 2, .ink = 1, .timer = 0x64, .shift = 0 });
            return cy.one(0x7FD6);
        }
        const a = new(st, cy, 0x7FD8, 0x7FDE, 0x8014, .{ .text = 0x88CA, .off = 0x5D40, .kind = 2, .ink = 2, .timer = 0x64, .shift = 0x0C });
        st.set_a(1, BASE + P1);
        cy.one(0x8014);
        if (!cy.br(0x8018, st.rw(P1) == 0)) {
            st.wb(P1 + 0x41, st.rb(P1 + 0x41) + 3);
            cy.run(0x801A, 0x8024);
            score.score_add(st, cy, 0x4262, 0);
            cy.run(0x8024, 0x802C);
            fill(st, a, .{ .ink = 7 });
            return;
        }
        st.set_a(1, BASE + P2);
        st.wb(P2 + 0x41, st.rb(P2 + 0x41) + 3);
        cy.run(0x802C, 0x803C);
        score.score_add(st, cy, 0x4256, 0);
        return cy.one(0x803C);
    }
    cy.one(0x803E);
    if (!cy.br(0x8044, st.g(V.survival_lost) == 0)) {
        _ = new(st, cy, 0x8046, 0x804C, 0x807C, .{ .text = 0x88A5, .off = 0x5D38, .kind = 2, .ink = 1, .timer = 0x64, .shift = 0x0A });
        return cy.one(0x807C);
    }
    _ = new(st, cy, 0x807E, 0x8084, 0x80B4, .{ .text = 0x887A, .off = 0x5D30, .kind = 2, .ink = 1, .timer = 0x64, .shift = 8 });
    st.wb(P1 + 0x41, st.rb(P1 + 0x41) + 3);
    st.wb(P2 + 0x41, st.rb(P2 + 0x41) + 3);
    st.set_a(0, BASE + P2);
    cy.run(0x80B4, 0x80CE);
    score.score_add(st, cy, 0x4262, 0);
    cy.one(0x80CE);
    score.score_add(st, cy, 0x4256, 0);
    cy.one(0x80D4);
}

/// $80D6: the countdowns that hit 0 last wave restart at 5.
fn rearm(st: *St, cy: *Cy) void {
    cy.one(0x80D6);
    if (!cy.br(0x80DC, st.g(V.cd_egg) != 0)) {
        st.s(V.cd_egg, 5);
        return cy.run(0x80DE, 0x80E8);
    }
    cy.one(0x80E8);
    if (!cy.br(0x80EE, st.g(V.cd_ptero) != 0)) {
        st.s(V.cd_ptero, 5);
        return cy.run(0x80F0, 0x80FA);
    }
    cy.one(0x80FA);
    if (!cy.br(0x8100, st.g(V.cd_gladiator) == 0)) return cy.one(0x8102);
    st.s(V.cd_gladiator, 5);
    cy.run(0x8104, 0x8114);
    if (!cy.br(0x8114, st.g(V.players) == 2)) return cy.one(0x8116);
    cy.one(0x8118);
    const tf = st.g(V.team_flag);
    if (cy.br(0x8120, tf == 1)) {
        _ = new(st, cy, 0x815C, 0x8162, 0x8192, .{ .text = 0x8910, .off = 0x5D20, .kind = 2, .ink = 7, .timer = 0x64, .shift = 0 });
        return cy.one(0x8192);
    }
    if (cy.br(0x8122, tf > 1 and tf < 0x80)) {
        _ = new(st, cy, 0x8194, 0x819A, 0x81CA, .{ .text = 0x8910, .off = 0x5D80, .kind = 2, .ink = 2, .timer = 0x64, .shift = 2 });
        return cy.one(0x81CA);
    }
    _ = new(st, cy, 0x8124, 0x812A, 0x815A, .{ .text = 0x88FC, .off = 0x5D50, .kind = 2, .ink = 1, .timer = 0x64, .shift = 0x0D });
    cy.one(0x815A);
}
