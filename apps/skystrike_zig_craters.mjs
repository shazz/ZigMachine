// SKYSTRIKE ZIG-mode harness, the craters (zig_craters.zig; apps/
// skystrike_zig.mjs drives). The plane waits on its runway (sector 0); an
// enemy fighter is sent into the ground of sector 1, next door, until one
// crash leaves a hole (the dice of 316 say when). With the setting at its
// default (zig_settings.zig's crater_life_vbls):
//   - the hole is there, and still there a pass before its time;
//   - by its time the sector's gun bits and wreck table (ghx9, sno9, so9)
//     are byte for byte what they were before the crash;
//   - the ring's slot of sector 1 was drawn again and is, pixel for pixel,
//     what it was before the crash.
// In ORIGINAL the same crash's hole stays.
// --break crater: the setting at 0 (never).
import { readFile } from "node:fs/promises";
import { onRunway, CRATER_LIFE, RING_W } from "./skystrike_zig_session.mjs";
import { ENEMY } from "./skystrike_session.mjs";

const src = await readFile("apps/zig/scenes/skystrike/zig_settings.zig", "utf8");
const LIFE = Number(src.match(/crater_life_vbls: u32 = (\d+)/)[1]);
const E = { sx: 0, al: 2, x: 4, y: 6, fre: 8, er: 10 }, SEC = 1, VBL = 8, PASS = 4;

/// Sector 1's ground bytes: its gun bits, wreck count, four wreck images.
function ground(s) {
    const [ghx9, sno9, so9] = [366, 367, 368].map((k) => s.val(k));
    return [s.val(ghx9 + SEC), s.val(sno9 + SEC), ...[0, 1, 2, 3].map((k) => s.val(so9 + SEC * 4 + k))].join(",");
}

/// The ring's slot of sector 1 (column 2 when the ring is round sector 0),
/// the ground row.
function slot(s) {
    const r = s.ring(), out = [];
    for (let y = 320; y < 496; y++) out.push(...r.subarray(y * RING_W + 640, y * RING_W + 960));
    return out;
}

/// Crash enemy 0 into sector 1 until a hole is made.
function crash(s) {
    const made = s.z("cratersMade");
    for (let i = 0; i < 60 && s.z("cratersMade") === made; i++) {
        s.poke(ENEMY + E.sx, SEC); s.poke(ENEMY + E.al, 0); s.poke(ENEMY + E.x, 100 + (i * 37) % 120);
        s.poke(ENEMY + E.y, 158); s.poke(ENEMY + E.er, 12); s.poke(ENEMY + E.fre, 0);
        s.pass();
    }
    return s.z("cratersMade") !== made;
}

async function run(zig, life, errors) {
    const s = await onRunway(zig);
    s.poke(CRATER_LIFE, life);
    s.run(5);
    const g0 = ground(s), px0 = slot(s);
    if (!crash(s)) return errors.push(`craters: ${zig ? "ZIG" : "ORIGINAL"}: 60 crashes in sector 1 left no hole`);
    const t0 = s.val(VBL), g1 = ground(s);
    if (g1 === g0) errors.push("craters: the crash changed nothing in sector 1's ground");
    s.run(2);
    const holed = zig && slot(s).some((p, i) => p !== px0[i]);
    const drawn = s.z("slots");
    // t0 is the end of the crash's pass: the crash was up to a pass before
    while (s.val(VBL) - t0 < LIFE - PASS) s.run(1);
    const early = ground(s);
    while (s.val(VBL) - t0 < LIFE + 1) s.run(1);
    const g2 = ground(s), px2 = slot(s);
    return { g0, g1, early, g2, holed, same: px2.every((p, i) => p === px0[i]), redrawn: s.z("slots") - drawn, filled: s.z("cratersFilled") };
}

export async function craters(broke) {
    const errors = [];
    const z = await run(true, broke === "crater" ? 0 : LIFE, errors);
    const o = await run(false, LIFE, errors);
    if (typeof z !== "object" || typeof o !== "object") return errors;
    if (z.early !== z.g1) errors.push(`craters: the hole filled in before ${LIFE} VBLs`);
    if (z.g2 !== z.g0) errors.push(`craters: after ${LIFE} VBLs sector 1's ground is ${z.g2}, not ${z.g0} as before the crash (${z.g1} with the hole)`);
    if (!z.holed) errors.push("craters: the ring's slot of sector 1 never showed the hole");
    if (!z.same || !z.redrawn) errors.push(`craters: the ring's slot of sector 1 is not what it was before the crash (${z.redrawn} slots drawn since)`);
    if (o.g2 !== o.g1) errors.push("craters: ORIGINAL's hole filled in");
    console.log(`  craters: ZIG: a hole in sector 1 (ghx9,sno9,so9 ${z.g0} -> ${z.g1}) there at ${LIFE - PASS} VBLs, gone by ${LIFE} (${z.g2}), its ring slot redrawn = before; ORIGINAL keeps it`);
    return errors;
}
