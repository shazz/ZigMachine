// --------------------------------------------------------------------------
// Package D: the player input (the model's pkg_d.py call 5 and d_input.py
// call 6).
//   call 5  $1E10  IKBD interrogate ($16), wait for the packet, then P1 <- port
//                  1, P2 <- port 0. Fire flaps, left/right set the target vx to
//                  -4/+4. Fire with no player in the game starts a new game
//                  ($1ECC, flow_newgame.zig).
//   call 6  $1C92  Bconstat; with a key: ^C quits, P pauses (polls until a key
//                  or a joystick direction -- resumable here, see Call6), R
//                  restarts (jmp $6).
// --------------------------------------------------------------------------
const State = @import("state.zig");
const cyc = @import("cyc.zig");
const sound = @import("sound.zig");
const keys = @import("keys.zig");
const sub = @import("riders_sub.zig");
const life = @import("flow_life.zig");
const St = State.St;
const V = State.V;
const Cy = cyc.Cy;
const BASE = State.BASE;
const SLOTS = State.SLOTS;
const SLOT_SZ = State.SLOT_SZ;
const M32 = State.M32;

const IKBD_BUF: i64 = 0x0E40; // the harness's IKBD packet buffer (low RAM)

const PI = struct { d2: i64, c: i64 };

/// $1E68: apply one joystick byte d0 to the player slot at TEXT offset a.
/// Null = fire with no player in the game ($1ECC takes over; its cycles so far
/// in fire_c).
fn player_input(st: *St, a: i64, d0: i64, fire_c: *i64) ?PI {
    var d2 = st.rw(a);
    var c: i64 = 20 + 12; // bsr, move.w (a0),d2
    if (d2 == 0) {
        c += 12 + 12; // beq taken, btst #7,d0
        if (d0 & 0x80 != 0) {
            if (st.g(V.players) == 0) {
                fire_c.* = c + 8 + 16 + 8; // $1ECC: fire with no player = a new game (jmp $18)
                return null;
            }
            c += 8 + 16 + 12; // beq not taken, tst.b $0D30, bne taken
        } else {
            c += 12; // beq taken
        }
        return .{ .d2 = d2, .c = c + 16 };
    }
    c += 8 + 12; // beq not taken, btst #13
    if (d2 & 0x2000 != 0) {
        const r = riderless(st, a, d2);
        return .{ .d2 = r.d2, .c = c + 12 + r.c };
    }
    c += 12 + 12; // bne.w not taken, btst #7,d0
    if (d0 & 0x80 != 0) {
        d2 |= 0x0840; // b11 fire held, b6 flap pose
        c += 12 + 12 + 12; // bne taken, bset, bset
    } else {
        d2 &= ~@as(i64, 0x0840);
        c += 8 + 16 + 16 + 12; // bne not taken, bclr, bclr, bra
    }
    var tv = st.rw(a + 6); // target = current vx ...
    c += 20 + 12; // move.w 6(a0),$c(a0); btst #7,d2
    if (d2 & 0x80 != 0) {
        tv = 0; // ... or 0 while inactive
        c += 8 + 16;
    } else {
        c += 12;
    }
    c += 12; // btst #3,d0
    if (d0 & 0x08 != 0) {
        tv = 4;
        c += 8 + 16 + 12;
    } else {
        c += 12 + 12; // beq taken, btst #2,d0
        if (d0 & 0x04 != 0) {
            tv = 0xFFFC;
            c += 8 + 16;
        } else {
            c += 12;
        }
    }
    st.ww(a + 0x0C, tv);
    st.ww(a, d2);
    return .{ .d2 = d2, .c = c + 12 + 16 }; // move.w d2,(a0); rts
}

/// $1F32: a player's mount after the rider fell: flies off at +-4 and leaves
/// at the edge. Cycles from $1F32 to the rts.
fn riderless(st: *St, a: i64, d2_in: i64) PI {
    var d2 = d2_in;
    const x = State.s16(st.rw(a + 2));
    var c: i64 = 12; // btst #15,d2
    if (d2 & 0x8000 != 0) {
        c += 8 + 16; // beq not taken, cmpi.w #$13c
        if (x >= 0x13C) return die(st, a, d2, c + 8);
        c += 12;
    } else {
        c += 12 + 16; // beq taken, cmpi.w #$130
        if (0x130 <= x and x <= 0x133) return die(st, a, d2, c + 8 + 16 + 12);
        c += if (x < 0x130) 12 else 8 + 16 + 8; // blt taken | blt no, cmpi.w #$133, ble no
    }
    const vx = st.rw(a + 6);
    st.ww(a + 0x0C, if (vx & 0x8000 != 0) 0xFFFC else 4);
    c += 16 + 12 + @as(i64, if (vx & 0x8000 != 0) 8 + 16 else 12); // move.w #4; tst.w vx; bge / neg.w
    const y = st.rw(a + 4);
    st.set_d(3, y, 2);
    c += 16 + 16; // move.w #$8c,$46; cmpi.w #$64,y
    var tgt: i64 = undefined;
    if (y > 0x64) {
        tgt = 0x8C;
        c += 12;
    } else {
        c += 8 + 16 + 16; // bgt not taken, move.w #$42, cmpi.w #$28
        if (y > 0x28) {
            tgt = 0x42;
            c += 12;
        } else {
            tgt = 0x0A;
            c += 8 + 16;
        }
    }
    st.ww(a + 0x46, tgt);
    const vy = st.rw(a + 8);
    c += 12 + 12; // move.w 4(a0),d3; cmp.w $46(a0),d3
    if (y > tgt) {
        c += 8 + 12; // ble not taken, tst.w vy
        if (vy & 0x8000 == 0) {
            d2 ^= 0x0840;
            st.ww(a, d2);
            return .{ .d2 = d2, .c = c + 8 + 12 + 12 + 12 + 16 }; // blt not taken, bchg, bchg, move.w, rts
        }
        c += 12;
    } else {
        c += 12;
    }
    d2 &= ~@as(i64, 0x0840);
    st.ww(a, d2);
    return .{ .d2 = d2, .c = c + 16 + 16 + 12 + 16 }; // bclr, bclr, move.w, rts
}

/// $1F40: the riderless mount left the screen: erase it ($38AC, package A)
/// and lose a life ($1FBA). Cycles are only accumulated (call 5 reports them
/// to the pacer as a whole).
fn die(st: *St, a: i64, d2: i64, c: i64) PI {
    var cy = Cy.init(st);
    cy.add(c);
    st.set_a(0, BASE + a);
    st.set_d(2, d2, 2);
    cy.one(0x1F40); // jsr $38ac
    sub.erase(st, &cy);
    cy.one(0x1F46); // bsr.w $1fba
    life.lose_life(st, &cy, a);
    cy.one(0x1F4A); // rts
    return .{ .d2 = st.regs[2] & 0xFFFF, .c = cy.pend };
}

pub const Joy5 = union(enum) {
    /// the frame goes on; st.cycles holds the post-packet cycles
    done,
    /// fire with no player: a new game; the pre-trap cycles so far
    new_game: i64,
};

/// Call 5 up to the new-game branch (the caller runs flow_newgame on .new_game).
pub fn call_1e10_joystick(st: *St, joy: [2]u8) Joy5 {
    const p1: i64 = joy[0];
    const p2: i64 = joy[1];
    st.s(V.joy_packet, IKBD_BUF);
    const two = st.g(V.two_player) != 0;
    st.s(V.joy_dirs, (if (two) p1 | p2 else p1) & 0x0F);
    const head: i64 = 20 + 8 + 8 + 16 + 16 + @as(i64, if (two) 8 + 20 else 12) + 24 + 12;
    var pre = head;
    st.set_d(1, p2, 1);
    st.set_d(0, p1, 1);
    var fire_c: i64 = 0;
    st.set_a(0, BASE + SLOTS);
    const r1 = player_input(st, SLOTS, p1, &fire_c) orelse return .{ .new_game = pre + fire_c };
    pre += r1.c + 12 + 4;
    st.regs[0] = st.regs[1];
    st.set_a(0, BASE + SLOTS + SLOT_SZ);
    const r2 = player_input(st, SLOTS + SLOT_SZ, p2, &fire_c) orelse return .{ .new_game = pre + fire_c };
    // after the wait loop: movea.l, 2x move.b, move.b d0,$D52, tst.b $D4F, beq
    // (or.b), andi.b, movea.l, [c1], movea.l, move.l d1,d0, [c2], rts -> the
    // pacer's joystick(post)
    st.cycles = head + r1.c + 12 + 4 + r2.c + 16;
    st.set_d(1, p2, 1);
    st.regs[0] = st.regs[1];
    st.set_d(2, r2.d2, 2);
    st.set_a(0, BASE + SLOTS + SLOT_SZ);
    return .done;
}

// ------------------------------------------------------------------ call 6
/// Call 6 across host frames: the P pause polls until a key or a joystick
/// direction, for as long as the player likes.
pub const Call6 = struct {
    cy: Cy,
    paused: bool,
};

pub const Status = enum { done, suspended };

pub fn call_1c92_keyboard(st: *St, c6: *Call6, limit: i64) Status {
    c6.cy = Cy.init(st);
    c6.paused = false;
    const cy = &c6.cy;
    cy.add(20);
    cy.run(0x1C92, 0x1C9A); // 2 pushes
    var d0 = keys.bconstat(st, cy);
    st.regs[0] = d0;
    cy.run(0x1C9C, 0x1CA8); // adda.l, cmp.l
    if (cy.br(0x1CA8, d0 != M32)) {
        cy.one(0x1DF2);
        cy.done();
        return .done;
    }
    cy.run(0x1CAC, 0x1CB4);
    d0 = keys.bconin(st, cy);
    st.regs[0] = d0;
    const ch = d0 & 0xFF;
    cy.run(0x1CB6, 0x1CC0); // adda.l, cmp.b #3
    if (!cy.br(0x1CC0, ch != 3)) {
        quit(st, cy);
        return .done;
    }
    cy.one(0x1DC6);
    if (!cy.br(0x1DCA, ch == 0x50)) {
        cy.one(0x1DCC);
        if (cy.br(0x1DD0, ch != 0x70)) {
            cy.one(0x1DF4);
            if (!cy.br(0x1DF8, ch == 0x52)) {
                cy.one(0x1DFA);
                if (cy.br(0x1DFE, ch != 0x72)) {
                    cy.one(0x1E0C);
                    cy.done();
                    return .done;
                }
            }
            cy.run(0x1E00, 0x1E0C); // adda.l #4,a7 ; jmp $6
            st.regs[15] = (st.regs[15] + 4) & M32;
            st.exit = .restart;
            cy.done();
            return .done;
        }
    }
    c6.paused = true;
    return pause(st, c6, limit);
}

/// $1DD2: wait for a key or a joystick direction (only call 5 writes $0D52:
/// it stays as it was). Suspends at the top of an iteration once the machine
/// is due to hand back to the host; resume by calling it again.
pub fn pause(st: *St, c6: *Call6, limit: i64) Status {
    const cy = &c6.cy;
    while (true) {
        if (st.pacer.vbl >= limit) return .suspended;
        cy.one(0x1DD2);
        if (cy.br(0x1DD8, st.g(V.joy_dirs) != 0)) break;
        cy.run(0x1DDA, 0x1DE2);
        const d0 = keys.bconstat(st, cy);
        st.regs[0] = d0;
        cy.run(0x1DE4, 0x1DF0);
        if (!cy.br(0x1DF0, d0 != M32)) break;
    }
    cy.one(0x1DF2);
    c6.paused = false;
    cy.done();
    return .done;
}

/// $1CC4: ^C: silence, the HIGH.SCO handle, the OS restored, Pterm.
fn quit(st: *St, cy: *Cy) void {
    sound.dosound_silence(st); // Dosound($157D): script 0's bytes
    if (st.rb(0x86DA) != 0) st.ww(0x0E5A, 8); // the next GEMDOS handle (boot opened two files)
    st.regs[0] = 0; // Super(0) back to user mode
    st.set_a(0, 0x0E00); // Kbdvbase (tos.py's structure)
    cy.done();
    st.exit = .quit;
}

/// Call 16: Giaccess(read mixer reg 7): all 6 tone/noise channels off ->
/// priority back to $10. The register is read 60 cycles in (a Dosound tick
/// due by then has run).
pub fn call_0ac8_sfx_prio(st: *St) void {
    st.clock(60); // jsr, 3 pushes
    const r7: i64 = st.psg[7];
    st.clock(300 + 12 + 8 + 8); // trap (shim cost), adda, andi.b, cmpi.b
    st.clock(if (r7 & 0x3F == 0x3F) 8 + 20 + 16 else 12 + 16);
    st.regs[0] = r7 & 0x3F; // Giaccess returns the register in d0, andi.b #$3f
    if (r7 & 0x3F == 0x3F) st.s(V.sfx_prio, 0x10);
    st.cycles = st.clocked;
}
