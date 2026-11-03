// apps/obj_headless.mjs, checks 3-5: the shading modes, the erase, the sphere
// and GLENZ NEST pins, the HUD and Escape. Split out to keep each file short.
import { OBJ_Y0, OBJ_Y1, key } from "./obj_machine.mjs";

const MODES = ["FLAT", "GLENZ", "WIRE", "SOFT", "GOURAUD", "HIDDEN", "DOTS", "TEXTURE", "ENVMAP"];
const SPHERE_L6_VERTS = 222; // sphere level 6: 2 + 20 x 11
const RAMP = 12, WIRE_INK = 201;

function inks(S) {
    const count = new Map();
    for (const v of S.rows(OBJ_Y0, OBJ_Y1)) if (v) count.set(v, (count.get(v) ?? 0) + 1);
    return count;
}

// 3: S cycles nine distinct modes on the sphere, back to the first on the 10th.
async function cycle({ boot, press, fail }) {
    const S = await boot();
    press(S, "3");
    for (let i = 0; i < 5; i++) press(S, "+");
    const pics = [];
    for (let m = 0; m <= MODES.length; m++) {
        S.frame();
        pics.push({ hash: S.hash(), inks: inks(S) });
        press(S, "s");
        S.frame(); // the next frame advances the turn; compare the same phase below
        S.frame();
    }
    // Mode m's picture at frame 1 + 3m; the turn differs, so compare the last with a fresh FLAT run.
    const R = await boot();
    key(R, "3");
    for (let i = 0; i < 5; i++) key(R, "+");
    for (let f = 0; f < 1 + 3 * MODES.length; f++) R.frame();
    if (pics[MODES.length].hash !== R.hash()) fail("the 10th S press is not FLAT again");
    if (new Set(pics.slice(0, MODES.length).map((p) => p.hash)).size !== MODES.length) fail("S does not give nine different pictures");
    const [flat, glenz, wire, soft, gouraud, hidden, dots, texture, envmap] = pics.map((p) => p.inks);
    const keys = (m) => [...m.keys()];
    if (!keys(flat).length || keys(flat).some((v) => v > RAMP)) fail(`FLAT inks ${keys(flat)}: want the ramp 1..${RAMP}`);
    if (!keys(glenz).some((v) => v > RAMP && v < 64)) fail("GLENZ shows no OR'ed bit combination past the ramp");
    if (keys(gouraud).filter((v) => v >= 1 && v <= 32).length <= RAMP) fail(`GOURAUD uses ${keys(gouraud).length} levels: want more than ${RAMP}`);
    for (const [n, m] of [["WIRE", wire], ["HIDDEN", hidden]]) if (keys(m).join() !== String(WIRE_INK)) fail(`${n} inks ${keys(m)}: want only ${WIRE_INK}`);
    if (!((hidden.get(WIRE_INK) ?? 0) < (wire.get(WIRE_INK) ?? 0))) fail("HIDDEN draws no fewer edge pixels than WIRE");
    if (!keys(soft).length) fail("SOFT draws nothing");
    // DOTS: one byte a vertex at most (shared ones once), inks from the depth ramp
    const ndots = [...dots.values()].reduce((a, b) => a + b, 0);
    if (!(ndots > SPHERE_L6_VERTS / 2 && ndots <= SPHERE_L6_VERTS)) fail(`DOTS sets ${ndots} pixels: want one a vertex, at most ${SPHERE_L6_VERTS}`);
    if (keys(dots).some((v) => v < 1 || v > RAMP) || keys(dots).length < 4) fail(`DOTS inks ${keys(dots)}: want several depth steps of 1..${RAMP}`);
    // TEXTURE / ENVMAP: one CHISEL AFFINE op of texels, the wall's 64 colours / Natrium's env map's 13 greys
    if (keys(texture).some((v) => v < 1 || v > 64) || keys(texture).length < 24) fail(`TEXTURE inks ${keys(texture).length} texels: want many of the wall's 1..64`);
    if (keys(envmap).some((v) => v < 1 || v > 13) || keys(envmap).length < 6) fail(`ENVMAP inks ${keys(envmap)}: want several of Natrium's 13 grey levels (1..13)`);
}

// 4: each frame equals one drawn on cleared rows (B clears them before every frame):
// the sphere in every mode, GLENZ NEST (key 4, the biggest box) in GLENZ, FLAT and DOTS.
const ERASE_RUNS = [...MODES.map((_, m) => ["3++", m]), ["4", 1], ["4", 0], ["4", 6]];
async function erase({ boot, press, fail, BREAK }) {
    for (const [keys, m] of ERASE_RUNS) {
        const A = await boot(), B = await boot();
        for (const S of [A, B]) { for (const k of keys) press(S, k); for (let i = 0; i < m; i++) press(S, "s"); }
        for (let f = 1; f <= 90; f++) {
            if (BREAK === "erase" && f === 45) A.indices()[30 * A.stride() + 5] = 7;
            B.clearRows();
            A.frame();
            B.frame();
            if (A.hash() !== B.hash()) { fail(`${MODES[m]} (keys ${keys}): frame ${f} keeps pixels a cleared plane would not (stale erase)`); break; }
        }
    }
}

// 5: the sphere and GLENZ NEST pins, the HUD, Escape.
async function pins({ boot, press, fail, PINS_SPHERE, PINS_NEST, pinHash, K_ESC, OUT }) {
    for (const [name, { object = "3", level = 0, mode, frames, hash }] of Object.entries({ ...PINS_SPHERE, ...PINS_NEST })) {
        // every CPU/CHISEL split (key C) must give the pinned picture: the CPU
        // rasterisers follow CHISEL's rules, so where a face goes never shows
        for (let split = 0; split < 6; split++) {
            const S = await boot();
            press(S, object);
            for (let i = 0; i < level; i++) press(S, "+");
            for (let i = 0; i < mode; i++) press(S, "s");
            for (let i = 0; i < split; i++) key(S, "c");
            for (let f = 0; f < frames; f++) S.frame();
            const got = pinHash(S);
            if (got !== hash) { fail(`${name}, split preset ${split}: hash ${got}, pinned ${hash}`); break; }
            if (OUT && split === 0) await S.shot(`${OUT}/obj_${object === "4" ? "nest" : "sphere"}_${name}.png`);
        }
    }
    await nestPalette({ boot, press, fail });
    const S = await boot();
    S.frame();
    const hud = () => S.hash(0, OBJ_Y0);
    const top0 = hud();
    if (!S.rows(184, 192).some((v) => v)) fail("no key help on the bottom line");
    press(S, "3");
    S.frame();
    const top1 = hud();
    press(S, "+");
    S.frame();
    if (top0 === top1 || top1 === hud()) fail("the HUD lines do not follow the object and its resolution");
    if (S.demo.pollCartRequest() !== 0) fail("a cart request before Escape");
    key(S, K_ESC);
    if (S.demo.pollCartRequest() !== -1) fail("Escape does not return to the menu");
}

// GLENZ NEST's own GLENZ palette (red and white, palette.zig NEST_GLENZ): only
// while the nest is shown, never white past three layers, and the other
// objects get their GLENZ palette back.
async function nestPalette({ boot, press, fail }) {
    const S = await boot();
    press(S, "s");
    S.frame();
    const old = Array.from(S.pal().slice(1, 64));
    press(S, "4");
    S.frame();
    const p = S.pal(), rgb = (v) => v & 0xffffff, WHITE = 0xf0f0f0; // entries are 0xAABBGGRR
    if (rgb(p[1]) !== WHITE || rgb(p[2]) === WHITE) fail(`nest GLENZ: one layer is not white / red (${p[1].toString(16)}, ${p[2].toString(16)})`);
    for (let i = 1; i < 64; i++) {
        const layers = i.toString(2).split("1").length - 1;
        if (layers >= 4 && ((p[i] >> 8) & 0xff) > 60) fail(`nest GLENZ: ${layers} layers (index ${i}) not a deep red: ${p[i].toString(16)}`);
    }
    press(S, "1");
    S.frame();
    if (Array.from(S.pal().slice(1, 64)).join() !== old.join()) fail("the icosahedron's GLENZ palette does not come back after the nest");
}

export async function checkModes(ctx) {
    await cycle(ctx);
    await erase(ctx);
    await pins(ctx);
}
