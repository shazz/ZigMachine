// SKYSTRIKE ZIG-mode harness, the crossings (apps/skystrike_zig.mjs drives):
//   (a) a sector crossed left and right, a layer crossed up and down, in ZIG:
//       the pass that draws the new screen takes a plain pass's VBLs (no
//       21-VBL pause), a frame is shown every VBL, and the camera glides: it
//       moves at most MAXSTEP a frame, never stands still two frames running
//       while the plane flies, and keeps the plane in the middle of the view
//   (b) the ring's slot for the screen about to be entered = the back screen
//       the game's own line 1000 then draws there, pixel for pixel (the bonus
//       bar's box aside: in ZIG it is HUD)
import { onRunway, takeOff, steer, Z, RING_W } from "./skystrike_zig_session.mjs";

export const MAXSTEP = 16; // zig_scroll.zig
const BAR = { x0: 14, x1: 306, y0: 2, y1: 12 }; // zig_ring.zig
const SP = 11; // testapi: SP# x 1000

/// The ring slot of sector sx, layer al: its top-left in the ring, its lines.
function slotOf(s, sx, al) {
    const col = ((sx - s.z("cx") + 1) % 51 + 51) % 51;
    const row = s.z("base") + 2 - al;
    if (col > 2 || row < 0 || row > 2) return null;
    // the ground keeps all 176 lines; a sky slot's last 16 are the layer below's
    return { x0: col * 320, y0: row * 160, lines: row === 2 && al === 0 ? 176 : 160 };
}

function snapSlot(s, sx, al) {
    const at = slotOf(s, sx, al);
    if (!at) return null;
    const ring = s.ring();
    const px = new Uint8Array(320 * at.lines);
    for (let y = 0; y < at.lines; y++) px.set(ring.subarray((at.y0 + y) * RING_W + at.x0, (at.y0 + y) * RING_W + at.x0 + 320), y * 320);
    return { sx, al, lines: at.lines, px };
}

/// The snapshot against the capture of the draw that just happened there.
function compareSlot(snap, cap) {
    let bad = 0, first = null;
    for (let y = 0; y < snap.lines; y++) for (let x = 0; x < 320; x++) {
        if (y >= BAR.y0 && y <= BAR.y1 && x >= BAR.x0 && x <= BAR.x1) continue;
        if (snap.px[y * 320 + x] !== cap[y * 320 + x]) { bad++; first ??= `x ${x} y ${y}: ring ${snap.px[y * 320 + x]}, drawn ${cap[y * 320 + x]}`; }
    }
    return bad ? `${bad} pixels differ (first ${first})` : null;
}

/// One pass flown with the camera watched frame by frame.
function flyPass(s, log) {
    return s.pass(() => {
        log.push({ cx: s.z("camX"), cy: s.z("camY"), sx: s.z("sx"), live: s.z("liveSx"), al: s.z("liveAl") });
    });
}

/// Fly until the live screen is (sx, al) != the start, snapshotting the four
/// neighbours each pass; check (a) and (b) for that crossing.
function crossing(s, name, keep, errors, notes, broke) {
    const from = [s.z("liveSx"), s.z("liveAl")];
    const log = [];
    let snaps = [], vbls = [];
    for (let p = 0; p < 300; p++) {
        keep();
        const [lx, la] = [s.z("liveSx"), s.z("liveAl")];
        snaps = [[lx - 1, la], [lx + 1, la], [lx, la + 1], [lx, la - 1]].map(([x, a]) => snapSlot(s, (x + 51) % 51, a)).filter(Boolean);
        if (broke === "ring") for (const sn of snaps) sn.px[100 * 320 + 100] ^= 1;
        const draws = s.z("draws");
        vbls.push(flyPass(s, log));
        if (s.z("draws") === draws || (s.z("liveSx") === from[0] && s.z("liveAl") === from[1])) continue;
        vbls.push(flyPass(s, log)); // the pass that follows the new screen's draw
        const to = [s.z("liveSx"), s.z("liveAl")];
        const snap = snaps.find((n) => n.sx === to[0] && n.al === to[1]);
        const diff = snap ? compareSlot(snap, s.capture()) : "no ring slot held the screen entered";
        if (diff) errors.push(`(b) ${name}: sector ${to[0]} layer ${to[1]}: ${diff}`);
        judge(s, name, log, vbls, errors, notes, to);
        return;
    }
    errors.push(`(a) ${name}: no crossing in 300 passes from sector ${from[0]} layer ${from[1]}`);
}

/// Over the last WINDOW frames, the crossing's approach and arrival.
const WINDOW = 45;

function judge(s, name, all, vbls, errors, notes, to) {
    const log = all.slice(-WINDOW);
    const worst = Math.max(...vbls.slice(-2));
    if (worst > 5) errors.push(`(a) ${name}: a pass at the new screen took ${worst} VBLs (the redraw pause)`);
    let step = 0, still = 0, maxStill = 0;
    for (let i = 1; i < log.length; i++) {
        const dx = Math.abs(((log[i].cx - log[i - 1].cx + 8160) % 16320 + 16320) % 16320 - 8160), dy = Math.abs(log[i].cy - log[i - 1].cy);
        step = Math.max(step, dx, dy);
        still = dx || dy ? 0 : still + 1;
        maxStill = Math.max(maxStill, still);
    }
    if (step > MAXSTEP) errors.push(`(a) ${name}: the camera jumped ${step} px in a frame`);
    if (maxStill > 1) errors.push(`(a) ${name}: the camera stood still ${maxStill} frames running`);
    notes.push(`${name} -> ${to.join("/")}: passes ${Math.min(...vbls)}-${worst} VBLs, camera steps <= ${step} px`);
}

/// Four crossings in ZIG (in ORIGINAL with --break pause).
export async function flight(broke) {
    const errors = [], notes = [];
    const s = await onRunway(broke !== "pause");
    const fast = () => s.poke(SP, 11000);
    takeOff(s, 20);
    crossing(s, "left", fast, errors, notes, broke);
    steer(s, 8);
    crossing(s, "right", fast, errors, notes, broke);
    steer(s, 5);
    crossing(s, "up", fast, errors, notes, broke);
    crossing(s, "up again", fast, errors, notes, broke);
    steer(s, 11);
    crossing(s, "down", fast, errors, notes, broke);
    crossing(s, "down again", fast, errors, notes, broke);
    steer(s, 8);
    for (let p = 0; p < 4; p++) { fast(); s.pass(); }
    const ring = { slots: s.z("slots"), shifts: s.z("shifts"), rebuilds: s.z("rebuilds"), leaks: s.z("leaks") };
    if (ring.leaks) errors.push(`(b) ${ring.leaks} sandboxed draws made a sound`);
    console.log(`  (a)(b) crossings: ${notes.join("; ")}; ring: ${ring.slots} slots drawn, ${ring.shifts} shifts, ${ring.rebuilds} rebuild(s); each entered screen = its ring slot`);
    return { errors, s };
}
