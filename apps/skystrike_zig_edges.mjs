// SKYSTRIKE ZIG-mode harness, three places things went missing or appeared
// (apps/skystrike_zig.mjs drives):
//   landed  FIRE on the home airfield, stopped: the guns take a round a pass
//           and 101 rearms in the same pass, so the ammo never moves. The
//           tracers still fly, on the heading line; ORIGINAL draws none
//   border  an enemy just past the world's left end (sector -1, and 400, the
//           number 255 wraps it to) while the plane is at sector 0: drawn in
//           the frame's left border, as one in sector 1 is in the right one
//   ghost   a bomb bursting on the plane's own screen leaves no plane in the
//           back screen (1950: OFF, 993's WAIT VBL takes the sprites off
//           before 1956 copies the screen to back) -- both modes
// --break landed: the streaks looked for off the heading, turned 90 degrees;
// --break left: the left enemy put two sectors away; --break ghost: the
// ground band searched instead of the air above it.
import { onRunway, takeOff, WIN_W } from "./skystrike_zig_session.mjs";
import { ENEMY } from "./skystrike_session.mjs";
import { grab, lowres, png } from "./skystrike_zig_frame.mjs";
import { tracerLine } from "./skystrike_zig_view.mjs";

const FIRE = 0x80, LEFT = 4, E = { sx: 0, al: 2, x: 4, y: 6, er: 10 };

async function landed(outdir, broke, errors) {
    const out = [];
    for (const zig of [true, false]) {
        const s = await onRunway(zig);
        const ammo = s.v("ammo");
        s.stick(FIRE);
        let most = { count: 0, off: 0 };
        for (let p = 0; p < 4; p++) s.pass(() => { const t = tracerLine(s, broke === "landed" ? "tracer" : null); if (t.count > most.count) most = t; });
        if (zig && outdir) await png(`${outdir}/zig_tracers_landed.png`, lowres(grab(s)), 400, 280);
        s.stick(0);
        if (s.v("ld") !== 1 || s.v("sx") !== 0) errors.push(`landed: the plane left the airfield (ld ${s.v("ld")}, sector ${s.v("sx")})`);
        if (zig && (most.count < 3 || most.off > 4)) errors.push(`landed: FIRE on the runway drew ${most.count} tracer pixels, up to ${most.off.toFixed(1)} px off the heading`);
        if (!zig && s.val(360)) errors.push(`landed: ORIGINAL drew ${s.val(360)} streaks`);
        out.push(`${zig ? "ZIG" : "ORIGINAL"} ammo ${ammo} -> ${s.v("ammo")}${zig ? `, ${most.count} tracer px` : ""}`);
    }
    return out.join("; ");
}

/// Overlay pixels an enemy at (esx, ex) adds in columns x0..x1, at the pan
/// the last frame used (lockstep: frame() redraws, no VBL runs).
function added(s, esx, ex, x0, x1) {
    const draw = () => { s.machine.hwClear(); s.demo.frame(20); return s.overlay().slice(); };
    s.poke(ENEMY + E.sx, 20);
    const without = draw();
    s.poke(ENEMY + E.sx, esx); s.poke(ENEMY + E.x, ex);
    const withIt = draw();
    let n = 0;
    for (let y = 0; y < 236; y++) for (let x = x0; x <= x1; x++) if (withIt[y * WIN_W + x] !== without[y * WIN_W + x]) n++;
    return n;
}

async function border(outdir, broke, errors) {
    const s = await onRunway(true);
    takeOff(s, 20);
    for (let p = 0; p < 200 && s.v("x") > 150 && s.v("sx") === 0; p++) s.pass();
    if (s.v("sx") !== 0) return errors.push(`border: the plane left sector 0 (${s.v("sx")})`);
    s.poke(ENEMY + E.al, s.v("al")); s.poke(ENEMY + E.y, s.v("y")); s.poke(ENEMY + E.er, 8);
    const camX = ((s.z("cx") - 1) * 320 + s.z("sx") + 16320 * 2) % 16320;
    const wrap = (w) => ((w % 16320) + 16320 + 8160) % 16320 - 8160;
    const leftEx = wrap(camX + 20) + 320, rightEx = wrap(camX + 380) - 320;
    const got = {};
    for (const [k, esx, ex, x0, x1] of [["-1", broke === "left" ? -2 : -1, leftEx, 0, 39], ["400", 400, leftEx, 0, 39], ["1", 1, rightEx, 360, 399]]) {
        got[k] = added(s, esx, ex, x0, x1);
        if (!got[k]) errors.push(`border: an enemy in sector ${esx} at x ${ex} shows nothing in the ${x0 ? "right" : "left"} border`);
    }
    s.poke(ENEMY + E.sx, -1); s.poke(ENEMY + E.x, leftEx);
    s.machine.hwClear(); s.demo.frame(20);
    if (outdir) await png(`${outdir}/zig_enemy_left_border.png`, lowres(grab(s)), 400, 280);
    return `sector -1: ${got["-1"]} px in the left border, 400: ${got["400"]}, sector 1: ${got["1"]} in the right`;
}

async function ghost(broke, errors) {
    const out = [];
    for (const zig of [false, true]) {
        const s = await onRunway(zig);
        takeOff(s, 40);
        const before = s.screen("back").slice();
        s.stick(FIRE | LEFT); s.pass(); s.stick(0);
        for (let p = 0; p < 40 && s.v("bf"); p++) s.pass();
        s.pass(); s.pass();
        const after = s.screen("back"), [y0, y1] = broke === "ghost" ? [150, 176] : [0, 148];
        let n = 0;
        for (let y = y0; y < y1; y++) for (let x = 0; x < 320; x++) if (before[y * 320 + x] !== after[y * 320 + x]) n++;
        if (n) errors.push(`ghost: ${zig ? "ZIG" : "ORIGINAL"}: the bomb's burst changed ${n} back-screen pixels in lines ${y0}-${y1 - 1}, above the ground (the plane's ghost)`);
        out.push(n);
    }
    return `a bomb's burst on the home screen: ${out.join(" / ")} back pixels changed above the ground (ORIGINAL / ZIG)`;
}

export async function edges(outdir, broke) {
    const errors = [];
    const notes = [await landed(outdir, broke, errors), await border(outdir, broke, errors), await ghost(broke, errors)];
    console.log(`  edges: landed: ${notes[0]}; border: ${notes[1]}; ghost: ${notes[2]}`);
    return errors;
}
