// Headless DARK SIDE OF THE SPOON menu (cart 80, apps/zig/scenes/ulm_dsots.zig)
// against shazz's melonJS remake itself: apps/ulm_dsots_ref.json.gz is the
// remake run in Chrome over the same timelines (apps/ulm_dsots_ref.mjs).
//
//   alloc   the menu's two built views (mirrored griffin, tiled background)
//           came from zg.mem with no refusal, and the scene says it is ready
//   physics every step of both runs = the remake's MainEntity (pos, vel, frame,
//           facing), viewport and parallax offset, exactly (f64 for double)
//   render  at every shot frame the 384x270 canvas = the remake's canvas at
//           its even pixels, pixel for pixel, and the plane around it is black
//   door    Space in mid-air opens nothing; Space on the temple's platform, at
//           the frame the remake's DoorEntity fires (it saves entityPos, then
//           throws: INTRO is unregistered), asks for the ulm_spoon_distorter cart
//   exit    Escape asks the host for the menu disk (-1)
//   rate    on a 144 Hz display the menu still steps 60 times a second
//   cost    the mean host frame (cart frame + plane render) is within budget
//
//   node apps/ulm_dsots_headless.mjs [outdir]            (menu shots in outdir)
//   node apps/ulm_dsots_headless.mjs --break alloc|physics|render|door [outdir]
//       a refused zg.mem allocation / "up" let go one frame late / the canvas
//       read one pixel to the right / Space pressed before the door: passes
//       only if the check it breaks catches it
import { readFile, mkdir } from "node:fs/promises";
import { gunzipSync } from "node:zlib";
import { boot, frame, canvas, outsideNotBlack, writePng, CANVAS } from "./ulm_dsots_machine.mjs";
import { TIMELINES, DOOR_FRAME } from "./ulm_dsots_timelines.mjs";

const BREAKS = ["alloc", "physics", "render", "door"];
const bi = process.argv.indexOf("--break");
const broke = bi > 0 ? process.argv[bi + 1] : null;
if (bi > 0 && !BREAKS.includes(broke)) throw new Error(`--break ${BREAKS.join(" | ")}`);
const outdir = process.argv.slice(2).find((a, i, v) => !a.startsWith("--") && v[i - 1] !== "--break") || "/tmp/ulm_dsots";
const DIR = { up: 0, left: 2, right: 3, space: 5 };
const WANT_TAG = "ulm_spoon_distorter";
const COST_MS = 4; // a 60 Hz frame is 16.7 ms; this screen measured well under 1
const STATE = ["x", "y", "vx", "vy", "view x", "view y", "parallax", "sprite", "flip"];
const ref = JSON.parse(gunzipSync(await readFile("apps/ulm_dsots_ref.json.gz")));
const errors = [];
const fail = (check, msg) => errors.push(`${check}: ${msg}`);
await mkdir(outdir, { recursive: true });

/// The timeline's keys for frame f, as a host sends them: a held key repeats
/// every frame (an OS auto-repeat), and comes up with inputRelease.
function keys(m, hold, f) {
    for (const [k, from, to] of hold) {
        if (f >= from && f < to) m.demo.input(DIR[k]);
        if (f === to) m.demo.inputRelease(DIR[k]);
    }
}

function tweak(name, tl) {
    const hold = tl.hold.map((h) => [...h]);
    if (broke === "physics" && name === "tour") hold.find((h) => h[0] === "up")[2] += 1;
    if (broke === "door" && name === "door") hold.find((h) => h[0] === "space").splice(1, 2, 100, 102);
    return hold;
}

async function run(name, tl) {
    const m = await boot();
    if (broke === "alloc") m.machine.hwRamAlloc(0xfffffff0, 1);
    const refused = m.machine.hwRamAllocFailures();
    if (refused || m.val(10) !== 1) fail("alloc", `${refused} zg.mem allocation(s) refused, ready ${m.val(10)}`);
    const want = ref[name], hold = tweak(name, tl), requests = [];
    let diverged = null;
    for (let f = 0; f < tl.frames; f++) {
        keys(m, hold, f);
        const req = frame(m);
        if (req) requests.push([f, req, m.tag()]);
        const got = STATE.map((_, i) => m.val(i));
        const bad = got.findIndex((v, i) => v !== want.trace[f][i]);
        if (bad >= 0 && !diverged) diverged = `${name} step ${f}: ${STATE[bad]} ${got[bad]}, remake ${want.trace[f][bad]}`;
        if (tl.shots.includes(f)) await shot(m, name, f, want.shots[f]);
    }
    if (diverged) fail("physics", diverged);
    else console.log(`  physics: ${name}, ${tl.frames} steps = the remake's, ${STATE.length} values each`);
    return { m, requests, want };
}

async function shot(m, name, f, b64) {
    const got = canvas(m, broke === "render" ? 1 : 0), want = Buffer.from(b64, "base64");
    let bad = 0;
    for (let i = 0; i < got.length; i += 3) if (got[i] !== want[i] || got[i + 1] !== want[i + 1] || got[i + 2] !== want[i + 2]) bad++;
    const border = outsideNotBlack(m);
    const file = `${outdir}/${name}-${String(f).padStart(4, "0")}.png`;
    await writePng(file, got, CANVAS.w, CANVAS.h);
    if (bad || border) fail("render", `${name} frame ${f}: ${bad} canvas px differ from the remake's, ${border} px of the border not black (${file})`);
    else console.log(`  render: ${name} frame ${f} = the remake's canvas (${file})`);
}

function doors(tour, door) {
    if (tour.requests.length) fail("door", `the tour (Space in mid-air) asked for ${JSON.stringify(tour.requests)}`);
    const fired = door.want.trace.findIndex((s) => s[9] === 1);
    if (fired !== DOOR_FRAME) fail("door", `the remake's door fired at ${fired}, the timeline expects ${DOOR_FRAME}`);
    const [f, req, tag] = door.requests[0] ?? [];
    if (door.requests.length !== 1 || f !== DOOR_FRAME || req !== 1 || tag !== WANT_TAG)
        fail("door", `wanted one cart request for ${WANT_TAG} at ${DOOR_FRAME}, got ${JSON.stringify(door.requests)}`);
    else console.log(`  door: Space at the temple door (step ${f}) asks for demo-${tag}; none in mid-air`);
}

async function exitAndRate() {
    const m = await boot();
    frame(m);
    m.demo.key(0xe012);
    const req = frame(m);
    if (req !== -1) fail("exit", `Escape asked for ${req}, not the menu (-1)`);
    else console.log("  exit: Escape asks for the menu disk");
    const r = await boot();
    for (let f = 0; f < 144; f++) frame(r, 1000 / 144);
    const steps = r.val(9);
    const j = await boot(); // a 60 Hz display's frames, jittered +-2 ms
    for (let f = 0; f < 600; f++) frame(j, 1000 / 60 + (f % 2 ? 2 : -2));
    if (Math.abs(steps - 60) > 1) fail("rate", `144 frames at 144 Hz ran ${steps} steps, not 60`);
    else if (j.val(9) !== 600) fail("rate", `600 jittered 60 Hz frames ran ${j.val(9)} steps, not one each`);
    else console.log(`  rate: one second at 144 Hz = ${steps} steps; 600 jittered 60 Hz frames = 600 steps`);
}

const tour = await run("tour", TIMELINES.tour);
const door = await run("door", TIMELINES.door);
doors(tour, door);
await exitAndRate();
const all = [...tour.m.cost, ...door.m.cost];
const mean = all.reduce((a, b) => a + b, 0) / all.length;
if (!broke && mean > COST_MS) fail("cost", `mean frame ${mean.toFixed(3)} ms > ${COST_MS} ms`);
console.log(`  cost: mean ${mean.toFixed(3)} ms, max ${Math.max(...all).toFixed(3)} ms a frame (cart + plane render)`);

if (broke) {
    const hit = errors.find((e) => e.startsWith(`${broke}:`));
    console.log(hit ? `ulm_dsots: PASS (--break ${broke} caught: ${hit})` : `ulm_dsots: FAILED -- --break ${broke} was not caught (${errors.join("; ")})`);
    process.exit(hit ? 0 : 1);
}
console.log(errors.length ? `ulm_dsots: FAILED -- ${errors.join("; ")}` : "ulm_dsots: all pass");
process.exit(errors.length ? 1 : 0);
