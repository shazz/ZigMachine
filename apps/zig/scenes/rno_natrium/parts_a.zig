// --------------------------------------------------------------------------
// Sequencer, parts 1-3 ($AB88..$B35E) and the two shared loops (the zoom and
// the env-object loop). Each case returns true where the 68000 waits for a
// VBL, false to fall straight into the next state in the same VBL.
// --------------------------------------------------------------------------
const A = @import("assets.zig");
const st = @import("st.zig");
const dots = @import("tunnel_dots.zig");
const box = @import("chunky_box.zig");
const decor = @import("decor.zig");
const tr = @import("transitions.zig");
const envmap = @import("envmap.zig");
const T = @import("timeline.zig");
const Seq = T.Seq;

/// $D670: toggle the field, draw one pass into the visible buffer.
fn dotPass(q: *Seq) void {
    dots.pass(q.frontBuf(), q.f, q.flag.toggleWord());
}

/// $DDEC into `s`.
fn tunnel(q: *Seq, s: *st.Screen) void {
    box.tunnel(s, q.f, q.flag.postIncWord());
}

/// A part-1 sub-part: until `limit`, one dot pass then (for `steps` steps)
/// one row operation. Returns true when it ran (and so waits).
fn sub(q: *Seq, limit: u32, next: T.State, steps: u16, op: *const fn (*Seq, u16) void) bool {
    if (q.counter >= limit) {
        q.step = 0;
        q.state = next;
        return false;
    }
    dotPass(q);
    if (q.step < steps) {
        op(q, q.step);
        q.step += 1;
    }
    return true;
}

fn wipe(q: *Seq, n: u16) void {
    dots.curtainPlane1(q.frontBuf(), n, 0xFFFF);
}
fn rno(q: *Seq, n: u16) void {
    dots.revealRno(q.frontBuf(), n);
}
fn natrium(q: *Seq, n: u16) void {
    dots.revealFromBack(q.frontBuf(), q.back(), n);
}
fn erase(q: *Seq, n: u16) void {
    dots.eraseRow(q.frontBuf(), n);
}

pub fn run(q: *Seq) bool {
    switch (q.state) {
        .wait_start => {
            if (q.counter < 0xC0) return true;
            q.setPal(A.PAL_TUNNEL);
            q.f = 0;
            q.step = 0;
            q.state = .p1_wipe;
        },
        .p1_wipe => return sub(q, 0x180, .p1_rno, 100, wipe),
        .p1_rno => return sub(q, 0x300, .p1_natrium, 0x38, rno),
        .p1_natrium => return sub(q, 0x480, .p1_erase, 0x38, natrium),
        .p1_erase => return sub(q, 0x540, .p1_clear, 0x38, erase),
        .p1_clear => { // $B08A: ends on the step count, not the counter
            dotPass(q);
            if (q.step < 100) {
                dots.curtainPlane1(q.frontBuf(), q.step, 0);
                q.step += 1;
            }
            if (q.step < 100) return true;
            q.state = .p2_init;
        },
        .p2_init => {
            q.setPal(A.PAL_BLACK);
            decor.decoration(q.back(), box.GROUP_LEFT); // $E828
            decor.panel(q.back(), A.girl_grey, 0x17, 12); // $C722, a0 = $37F54 + $97
            q.stall = T.C06E_VBLS; // $C06E(skin)
            q.state = .p2_init_b;
            return true;
        },
        .p2_init_b => {
            st.clear(q.frontBuf()); // $BF1A
            q.f = 0;
            tunnel(q, q.back());
            q.f = 0;
            tunnel(q, q.back());
            q.state = .p2_wait;
        },
        .p2_wait => {
            if (q.counter < 0x600) return true;
            q.setPal(A.PAL_BOX);
            q.zoom(false, .p2_tunnel_start);
        },
        .p2_tunnel_start => {
            q.f = 0;
            q.busy = T.DDEC_PHASE;
            q.state = .p2_tunnel;
        },
        .p2_tunnel => {
            if (q.counter >= 0x900) {
                q.stall = T.C06E_VBLS; // $C06E(face): the box keeps the last tunnel frame
                q.state = .p2_wobble_start;
                return true;
            }
            if (q.busy < T.VBL_UNITS) { // a call starts during this VBL
                tunnel(q, q.frontBuf());
                q.busy += T.DDEC_COST;
            }
            q.busy -= T.VBL_UNITS;
            return true;
        },
        .p2_wobble_start => {
            q.f = 0;
            q.overrun = true;
            q.state = .p2_wobble_compute;
        },
        .p2_wobble_compute => { // $D7F6 builds its tables, then waits for the VBL
            q.pending_f = q.f;
            q.state = .p2_wobble;
            return true;
        },
        .p2_wobble => {
            box.wobble(q.frontBuf(), q.pending_f, q.flag.toggleLong());
            if (q.counter >= 0xBC0) {
                q.state = .p2_out;
                return false;
            }
            q.state = .p2_wobble_compute;
            if (!q.overrun) return false;
            q.overrun = false; // this draw ran into the next VBL
            q.stall = 1;
            return true;
        },
        .p2_out => {
            st.copy(q.back(), q.frontBuf()); // $BED8
            q.zoom(true, .p3_init);
        },
        .p3_init => {
            q.setPal(A.PAL_BLACK);
            st.fromIlbm(q.back(), A.girl_grey, 0, 200); // $C47E
            st.clear(q.frontBuf());
            q.env = envmap.object(A.cube); // $C5A8, $F020
            q.f = 0;
            envmap.render(q.env, q.f);
            q.state = .p3_c2p_a;
            return true; // $EB42(back) waits for the VBL
        },
        .p3_c2p_a => {
            envmap.c2p(q.back(), q.flag.toggleWord());
            q.state = .p3_c2p_b;
            return true;
        },
        .p3_c2p_b => {
            envmap.c2p(q.back(), q.flag.toggleWord());
            q.setPal(A.PAL_CUBE);
            q.state = .p3_wait;
        },
        .p3_wait => {
            if (q.counter < 0xC00) return true;
            q.zoom(false, .env_start);
            q.env_limit = 0xEC0;
            q.env_after = .p3_out;
        },
        .zoom_compute => { // $D472 / $D570: the table, the field, then the VBL wait
            const n = if (q.zoom_out) tr.zoomOutN(q.step) else tr.zoomInN(q.step);
            tr.zoomTable(n, &q.table);
            q.zoom_par = q.flag.toggleWord();
            q.state = .zoom_copy;
            return true;
        },
        .zoom_copy => {
            tr.zoomCopy(q.frontBuf(), q.back(), &q.table, q.zoom_par);
            q.step += 2;
            q.state = if (q.step < tr.STEPS_DONE) .zoom_compute else q.after;
        },
        .env_start => {
            q.f = 0;
            envmap.render(q.env, q.f);
            q.state = .env_loop;
            return true;
        },
        .env_loop => { // render ~2.x VBLs, then $EB42 waits: a new frame every 3
            if (q.f % 3 != 0) return true;
            envmap.c2p(q.frontBuf(), q.flag.toggleWord());
            if (q.counter >= q.env_limit) {
                q.state = q.env_after;
                return false;
            }
            envmap.render(q.env, q.f);
            return true;
        },
        else => unreachable,
    }
    return false;
}
