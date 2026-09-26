// --------------------------------------------------------------------------
// A new game (the model's d_newgame.py): $0618 reset the game state, $04B8 the
// new-game screen (Setpalette, clear, left ledge $04F0 + platforms $0540,
// scores, lives, the $09AC start-up siren). Fire after GAME OVER runs them
// from inside call 5 ($1ECC, then jmp $18); the title runs them from $0006.
// --------------------------------------------------------------------------
const State = @import("state.zig");
const cyc = @import("cyc.zig");
const blit = @import("riders_blit.zig");
const score = @import("flow_score.zig");
const gameover = @import("flow_gameover.zig");
const name = @import("flow_name.zig");
const St = State.St;
const V = State.V;
const Cy = cyc.Cy;
const BASE = State.BASE;
const M32 = State.M32;

/// XBIOS 17 Random, TOS's LCG (tos.py): the seed is the machine's.
pub fn random(seed: *u32) i64 {
    seed.* = seed.* *% 3141592621 +% 1;
    return (seed.* >> 8) & 0xFFFFFF;
}

pub const Fire = enum { rts_into_frame, name_entry };

/// $1ECC: fire with no player in the game, from inside call 5 (`pre` = its
/// cycles after the packet). Returns .name_entry when the GAME OVER check
/// found a new high score (the name entry then runs to jmp $6); otherwise the
/// new game is set up and the frame is left by jmp $18 (st.exit).
pub fn new_game(st: *St, pre: i64, seed: *u32, ne: *name.NameEntry) Fire {
    st.pacer.joystick(st, 0); // the IKBD wait before the packet was read
    var cy = Cy.init(st);
    cy.add(pre);
    st.regs[15] = (st.regs[15] + 8) & M32;
    st.s(V.new_game, 1);
    cy.run(0x1ECC, 0x1EDC); // addq.w #8,a7, move.b #1,$d50, jsr $450e
    if (gameover.name_entry_or_rts(st, &cy, ne)) return .name_entry;
    cy.one(0x1EDC); // jsr $618
    reset(st, &cy, seed);
    cy.one(0x1EE2);
    if (!cy.br(0x1EE8, st.g(V.two_player) == 0)) {
        st.s(V.players, 2);
        st.wb(0x0FF2 + 0x44, 0x30);
        st.wb(0x0FF2 + 0x4C, 4);
        st.set_a(0, BASE + 0x0FF2);
        cy.run(0x1EEA, 0x1F06);
    } else {
        st.ww(0x0FF2, 0);
        st.s(V.players, 1);
        cy.run(0x1F06, 0x1F14);
    }
    st.wb(0x0FA4 + 0x44, 0x30);
    st.wb(0x0FA4 + 0x4C, 4);
    st.set_a(0, BASE + 0x0FA4);
    cy.run(0x1F14, 0x1F2C); // ... jsr $4b8
    setup(st, &cy);
    cy.one(0x1F2C); // jmp $18
    cy.done();
    st.cycles = st.clocked;
    st.exit = .jmp18;
    return .rts_into_frame;
}

/// $0618 body.
pub fn reset(st: *St, cy: *Cy, seed: *u32) void {
    cy.run(0x0618, 0x0624);
    const nv = 0x157D - 0x1566;
    for (0..nv) |i| {
        const o: i64 = @intCast(i);
        st.wb(0x0D30 + o, st.rb(0x1566 + o));
        cy.run(0x0624, 0x062C);
        _ = cy.br(0x062C, i < nv - 1);
    }
    cy.run(0x062E, 0x063A);
    const nt = 0x1566 - 0x14CA;
    for (0..nt) |i| {
        const o: i64 = @intCast(i);
        st.wb(0x0FA4 + o, st.rb(0x14CA + o));
        cy.run(0x063A, 0x0642);
        _ = cy.br(0x0642, i < nt - 1);
    }
    const sb = st.g(V.screen_base);
    st.wl(0x0FA4 + 0x36, st.rl(0x0FA4 + 0x36) + sb);
    st.wl(0x0FF2 + 0x36, st.rl(0x0FF2 + 0x36) + sb);
    st.regs[0] = sb;
    cy.run(0x0644, 0x0664);
    const clears = [_][6]i64{
        .{ 0x19D2, 0x1A22, 0x14, 1, 0x0664, 0x0670 },
        .{ 0x0E84, 0x0FA4, 12, 1, 0x0678, 0x0686 },
        .{ 0x1428, 0x14A8, 0x20, 2, 0x068E, 0x069C },
    };
    for (clears, 0..) |c, n| {
        var a = c[0];
        while (true) {
            st.put(a, @intCast(c[3]), 0);
            a += c[2];
            cy.run(c[4], c[5]);
            if (!cy.br(c[5], a != c[1])) break;
        }
        if (n == 0) cy.one(0x0672) else if (n == 1) cy.one(0x0688);
    }
    st.s(V.ptero_timer, 0x3E8);
    cy.run(0x069E, 0x06AC);
    var a: i64 = 0x13E8;
    while (a < 0x1428) : (a += 0x10) {
        st.wl(a, 0);
        cy.run(0x06AC, 0x06BA);
        _ = cy.br(0x06BA, a + 0x10 < 0x1428);
    }
    st.ww(0x0E32, 0);
    cy.run(0x06BC, 0x06C8);
    a = 0x0DE2;
    while (a < 0x0E0C) : (a += 1) {
        st.wb(a, 0);
        cy.run(0x06C8, 0x06D0);
        _ = cy.br(0x06D0, a + 1 != 0x0E0C);
    }
    st.ww(0x0DA6, 0);
    cy.run(0x06D2, 0x06DE);
    a = 0x1040;
    while (a < 0x13E8) : (a += 1) {
        st.wb(a, 0);
        cy.run(0x06DE, 0x06E6);
        _ = cy.br(0x06E6, a + 1 != 0x13E8);
    }
    st.s(V.rng_ptr, BASE);
    cy.run(0x06E8, 0x06F6);
    var d0 = random(seed); // XBIOS 17 Random (tos.py's LCG)
    cy.add(360);
    d0 &= 0xFE;
    st.s(V.rng_ptr, st.g(V.rng_ptr) + d0);
    st.regs[0] = d0;
    st.ww(0x0DAA, 0);
    st.s(V.flame_timer, 0x28);
    st.ww(0x1826, 0);
    st.ww(0x1828, 0x13F);
    st.s(V.lava_top, (sb + 0x7D00) & M32);
    st.s(V.new_game, 0);
    st.set_a(0, BASE + 0x13E8);
    st.set_a(1, BASE + 0x14CA + (0x1566 - 0x14CA));
    cy.run(0x06F8, 0x073E);
    st.regs[0] = (sb + 0x7D00) & M32;
}

/// $04B8 body.
pub fn setup(st: *St, cy: *Cy) void {
    cy.run(0x04B8, 0x04C2);
    setpalette(st, 0x14A8);
    cy.add(300); // Setpalette (installed by the next VBL)
    cy.run(0x04C4, 0x04CC); // addq.l, clr.w, bsr.w $2e8
    gameover.clear_screen(st, cy, 0);
    cy.one(0x04CC);
    cy.flush();
    blit.left_ledge(st, cy); // counts its bsr
    cy.flush();
    blit.call_0540_platform_redraw(st); // counts its (b)sr + st.clock
    cy.one(0x04D2);
    score.score_add(st, cy, 0x4262, 0);
    cy.one(0x04D8);
    score.score_add(st, cy, 0x4256, 0);
    cy.one(0x04DE);
    score.lives(st, cy, 1);
    cy.one(0x04E4);
    score.lives(st, cy, 2);
    cy.one(0x04EA);
    siren(st, cy);
    cy.one(0x04EE);
}

/// XBIOS 6 Setpalette: the 16 words at TEXT `table`, installed by the next VBL.
pub fn setpalette(st: *St, table: i64) void {
    for (0..16) |i| st.pending_pal[i] = @intCast(st.rw(table + 2 * @as(i64, @intCast(i))) & 0x777);
    st.pal_pending = true;
}

/// A Giaccess call site starting at lo: its pushes, the trap (the PSG
/// written when reg has b7), the stack fix-up. Returns the register.
fn giaccess(st: *St, cy: *Cy, lo: i64, reg: i64, val: i64) i64 {
    var t = lo;
    while (cyc.flags(t) & 16 == 0 and cyc.len(t) != 0) t += cyc.len(t);
    cy.run(lo, t); // 3 pushes
    cy.flush();
    const r: usize = @intCast(reg & 15);
    if (reg & 0x80 != 0) st.psg[r] = @intCast(val & 0xFF);
    cy.add(300);
    cy.one(t + cyc.len(t)); // adda.l #6,a7
    return st.psg[r];
}

/// $09AC body: tone A/B sweep down, volume 15 -> 0 (Giaccess).
pub fn siren(st: *St, cy: *Cy) void {
    st.logSfx(SIREN);
    _ = giaccess(st, cy, 0x09AC, 0x8A, 0);
    st.ww(0x0D8A, 0x0F);
    cy.one(0x09BE);
    while (true) {
        st.ww(0x0D88, 0x100);
        cy.one(0x09C6);
        while (true) {
            _ = giaccess(st, cy, 0x09CE, 0x81, 0);
            _ = giaccess(st, cy, 0x09E0, 0x83, 0x0C);
            _ = giaccess(st, cy, 0x09F4, 0x88, st.rw(0x0D8A));
            _ = giaccess(st, cy, 0x0A0A, 0x89, st.rw(0x0D8A));
            _ = giaccess(st, cy, 0x0A20, 0x80, st.rw(0x0D88));
            _ = giaccess(st, cy, 0x0A36, 0x82, st.rw(0x0D88));
            var d0 = giaccess(st, cy, 0x0A4C, 0x07, 0);
            d0 = (d0 | 0x3F) & ~@as(i64, 3);
            cy.run(0x0A5E, 0x0A6C);
            _ = giaccess(st, cy, 0x0A6C, 0x87, d0);
            st.regs[0] = st.psg[7];
            const v = (st.rw(0x0D88) - 2) & 0xFFFF;
            st.ww(0x0D88, v);
            cy.one(0x0A7E);
            if (!cy.br(0x0A84, v & 0x8000 == 0)) break;
        }
        const v = (st.rw(0x0D8A) - 1) & 0xFFFF;
        st.ww(0x0D8A, v);
        cy.one(0x0A88);
        if (!cy.br(0x0A8E, v & 0x8000 == 0)) break;
    }
    cy.one(0x0A92);
}

/// The siren's sound, in the SFX log: joust_sfx.sndh's subtune 17.
pub const SIREN: i64 = 16;
