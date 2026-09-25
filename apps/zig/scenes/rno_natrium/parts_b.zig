// --------------------------------------------------------------------------
// Sequencer, parts 4-7 ($B360..$BEB8): credits, twister, prism, rotozoom.
// Same contract as parts_a: true = the 68000 now waits for a VBL.
// --------------------------------------------------------------------------
const A = @import("assets.zig");
const st = @import("st.zig");
const box = @import("chunky_box.zig");
const decor = @import("decor.zig");
const tr = @import("transitions.zig");
const envmap = @import("envmap.zig");
const credits = @import("credits.zig");
const twister = @import("twister.zig");
const T = @import("timeline.zig");
const Seq = T.Seq;

/// $E094: the greeting, then the twister, into $CA5C; $BEBA shows it and swaps.
fn twisterFrame(q: *Seq) void {
    twister.greeting(q.frontBuf(), q.counter);
    twister.draw(q.frontBuf(), q.f);
    q.shown = q.front;
    q.front ^= 1;
}

/// $BB32..$BBA8, after each frame's VBL wait.
fn twisterFade(q: *Seq) void {
    const w = twister.fadeWindow(q.f, q.counter) orelse return;
    for (&q.pal, 0..) |*c, i| c.* = A.pal(A.PAL_TWIST, w + i);
    q.pal[0] = 0x000;
}

pub fn run(q: *Seq) bool {
    switch (q.state) {
        .p3_out => { // $B360: shrink what is on screen
            st.copy(q.back(), q.frontBuf());
            q.zoom(true, .p4_init);
        },
        .p4_init => {
            q.setPal(A.PAL_BLACK);
            st.fromIlbm(q.back(), A.girl_recline, 0, 200);
            st.clear(q.frontBuf());
            q.state = .p4_wait;
        },
        .p4_wait => {
            if (q.counter < 0xF00) return true;
            q.setPal(A.PAL_CREDITS);
            q.zoom(false, .p4_pre);
        },
        .p4_pre => {
            // $E6D4, the twister precalc, runs here (~42 VBLs, long before
            // $FC0). Its tables are evaluated per long in twister.zig instead.
            q.f = 0;
            q.strip = 0;
            q.state = .p4_strip_wait;
        },
        .p4_strip_wait => {
            if (q.counter < credits.AT[q.strip]) return true;
            q.state = .p4_strip;
            return true; // clr $144BC / tst: the copy follows a VBL
        },
        .p4_strip => {
            credits.stripRow(q.frontBuf(), q.strip);
            q.strip += 1;
            q.state = if (q.strip < credits.AT.len) .p4_strip_wait else .p4_wipe_wait;
        },
        .p4_wipe_wait => {
            if (q.counter < credits.WIPE_AT) return true;
            q.step = 0;
            q.state = .p4_wipe;
            return true;
        },
        .p4_wipe => {
            credits.whiteWipe(q.frontBuf(), q.step);
            q.step += 1;
            if (q.step < 100) return true;
            q.state = .p4_end;
        },
        .p4_end => {
            if (q.counter < twister.START) return true;
            q.setPal(A.PAL_WHITE);
            st.fillWhite(q.frontBuf()); // $E7C2: both buffers, colour 15
            st.fillWhite(q.back());
            q.stall = 1; // ...and it takes more than one VBL
            q.state = .p5_first;
            return true;
        },
        .p5_first => {
            q.f = 0;
            twisterFrame(q);
            // $BEBA is the only buffer swap in the program, yet the $1500,
            // $1900 and $1C00 snapshots put the screens ONE swap away from a
            // twister that draws every VBL: some $E094 call overran its VBL
            // (f then steps by 2). Which one is not recorded; this takes it here.
            q.stall = 2;
            q.state = .p5_loop;
            return true;
        },
        .p5_loop => {
            twisterFade(q);
            if (q.counter >= twister.END) {
                q.state = .p6_init;
                return false;
            }
            twisterFrame(q);
            return true;
        },
        .p6_init => {
            q.setPal(A.PAL_WHITE);
            q.state = .p6_init_b;
            return true;
        },
        .p6_init_b => {
            q.shown = q.front; // $BBE6
            st.fillColour12(q.frontBuf()); // $BFB4
            st.fromIlbm(q.back(), A.girl_red, 0, 200);
            q.env = envmap.object(A.prism);
            q.f = 0;
            envmap.render(q.env, q.f);
            q.state = .p6_c2p_a;
            return true;
        },
        .p6_c2p_a => {
            envmap.c2p(q.back(), q.flag.toggleWord());
            q.f = 0;
            envmap.render(q.env, q.f);
            q.state = .p6_c2p_b;
            return true;
        },
        .p6_c2p_b => {
            envmap.c2p(q.back(), q.flag.toggleWord());
            q.state = .p6_wait;
        },
        .p6_wait => {
            if (q.counter < 0x1800) return true;
            q.setPal(A.PAL_PRISM);
            q.step = 0;
            q.state = .p6_curtain;
            return true;
        },
        .p6_curtain => { // 100 x (VBL, two lines back -> front)
            tr.curtainCopy(q.frontBuf(), q.back(), q.step);
            q.step += 1;
            if (q.step < 100) return true;
            q.envLoop(0x1AC0, .p6_out);
        },
        .p6_out => {
            st.copy(q.back(), q.frontBuf());
            q.zoom(true, .p7_init);
        },
        .p7_init => {
            q.setPal(A.PAL_BLACK);
            q.stall = T.C06E_VBLS + T.P7_COPIES; // $C06E(skin), $E980, $C722, $BF1A
            q.state = .p7_init_b;
            return true;
        },
        .p7_init_b => {
            decor.decoration(q.back(), box.GROUP_RIGHT); // $E980
            decor.panel(q.back(), A.girl_red, 0x65A, 0); // $C722, a0 = $47A54 + $6DA
            st.clear(q.frontBuf());
            q.f = 0;
            q.pending_f = q.f;
            q.state = .p7_back_a;
            return true;
        },
        .p7_back_a => {
            box.rotozoom(q.back(), q.pending_f, q.flag.toggleLong());
            q.f = 0;
            q.pending_f = q.f;
            q.state = .p7_back_b;
            return true;
        },
        .p7_back_b => {
            box.rotozoom(q.back(), q.pending_f, q.flag.toggleLong());
            q.setPal(A.PAL_ROTO);
            q.state = .p7_wait;
        },
        .p7_wait => {
            if (q.counter < 0x1B00) return true;
            q.zoom(false, .p7_roto_start);
        },
        .p7_roto_start => {
            q.f = 0;
            q.state = .p7_roto_compute;
        },
        .p7_roto_compute => {
            q.pending_f = q.f;
            q.state = .p7_roto;
            return true;
        },
        .p7_roto => {
            box.rotozoom(q.frontBuf(), q.pending_f, q.flag.toggleLong());
            if (q.counter >= 0x1DC0) {
                q.state = .p7_out;
                return false;
            }
            q.state = .p7_roto_compute;
            return false;
        },
        .p7_out => {
            st.copy(q.back(), q.frontBuf());
            q.zoom(true, .p7_end);
        },
        .p7_end => {
            if (q.counter < T.END) return true;
            q.finished = true; // $BEAE: $CA1A restores the machine, SNDH exit, rts
            return true;
        },
        else => unreachable,
    }
    return false;
}
