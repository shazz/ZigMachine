// Headless RACER, the R82 bug pass (Matt's board session, 27 Nov; docs/ports/kestrel_racing/BUGPASS.md). Checks:
//   1. decals: an ARCADE race on Salt Flats (the AI pilot, key L) run on two machines in lockstep, one with the decals off
//      (key d): every pixel of a car colour (the car ramps 12..18) in the decals-off view is the same in the decals-on view,
//      every frame from the grid through the start line and a lap's first part: no decal (the start line, a road marking)
//      paints over a car standing on it (racer/under.zig). This race never puts a car where the old rule failed: the rule's
//      own sweep and its mutant (--break under, key O) are the native under_test.zig (every decal of Salt and Glacier, 626
//      cars painted over by the old rule, 0 now).
//   2. sound: an ARCADE race on Salt Flats on the PUBLIC cart (no -Dracer_music) with a fake BARD queue host (as
//      racer_audio_check.mjs): the engine keyed on FM 6 and its pitch written as the rpm moves (many fnums), the skid noise
//      switched on while a tyre slides, the impact keyed on FM 5 at a knock: the three effects of M4 in the default physics.
//      --break mute (key h before the race: the effects off) must be caught.
//   3. visibility (item 2, "track faces sometimes disappear"): the oracle (key 2, racer/oracle.zig) on the flyby lap of
//      Salt Flats, Neon Docks and Glacier Pass: no face kept by the camera's real view wedge is missing from the baked PVS
//      (racer,pvs lost = 0 every frame), no polygon dropped at the cap. --break pvs (key @: the PVS list thinned) must be
//      caught.
//   4. the race HUD over the picture (item 5, racer/hudpic.zig): an ARCADE race on Salt Flats, the default (picture) against
//      key 0 (the two bands): in the race the bands are blank and every pixel that differs is in the HUD's places (the top
//      and bottom strips of the view, the map's box); during the countdown the digit is in the middle; the view with the HUD
//      is the same on the CPU and AFFINE fills; pinned. --break hud (key 0 on the default machine) must be caught.
//   node apps/harness/racer_bugpass.mjs [<shot dir>] [--break <mode>]
import { createHash } from "node:crypto";
import { mkdir, readFile } from "node:fs/promises";
import { diskHook, ZMD } from "./racer_disk.mjs";
import { bootObj, key } from "./obj_machine.mjs";
import { png } from "./skystrike_zig_frame.mjs";

const argv = process.argv.slice(2);
const MODES = ["mute", "pvs", "hud"];
const PINS = { hud: "e990beea5096" }; // the Salt race frame 660 with the picture HUD
const BREAK = argv.includes("--break") ? argv[argv.indexOf("--break") + 1] : null;
if (BREAK !== null && !MODES.includes(BREAK)) { console.error(`racer_bugpass: unknown --break ${BREAK}`); process.exit(1); }
const PRINT = argv.includes("--print-pins");
const OUT = argv[0] && !argv[0].startsWith("--") ? argv[0] : null;
if (OUT) await mkdir(OUT, { recursive: true });
const W = 320, H = 200, Y0 = 12, Y1 = 188, REG_FB_BASE = 0x44, OFF_PAL = 0x0100, SALT_TAPS = 2;
const CAR_LO = 16 + 12 * 8, CAR_HI = 16 + 19 * 8; // the car ramps 12..18
const errors = [], notes = [];
const fail = (m) => errors.push(m);

export async function bootRacer(taps = SALT_TAPS, host = null) {
    const log = [];
    const disk = diskHook(new Uint8Array(await readFile(ZMD)));
    const S = await bootObj("site/carts/demo-racer.wasm", (s) => log.push(s), (env) => { disk(env); if (host) host(env); });
    const run = (n) => { for (let i = 0; i < n; i++) S.frame(); };
    const shown = () => [0, 1].filter((p) => S.demo.isPlaneEnabled(p))[0] ?? 0;
    const view = () => {
        const vb = S.machine.hwVideoBase(), dv = new DataView(S.memory.buffer, vb, OFF_PAL);
        return new Uint8Array(S.memory.buffer, vb + dv.getUint32(REG_FB_BASE + 4 * shown(), true), W * H).slice();
    };
    const lines = (kind) => log.filter((l) => l.startsWith(`racer,${kind},`)).map((l) => l.split(",").slice(2));
    for (let i = 0; i < taps; i++) { key(S, "t"); run(3); }
    return { S, log, run, view, lines };
}

async function shot(name, B, px) {
    if (!OUT) return;
    const vb = B.S.machine.hwVideoBase(), pal = new Uint32Array(B.S.memory.buffer, vb + OFF_PAL, 256).slice();
    await png(`${OUT}/${name}`, Uint32Array.from(px, (v) => (v ? pal[v] : 0xff000000)), W, H);
}

/** The race on Salt, the player on the AI pilot: the grid, then `frames` frames after the start; `each(i)` every frame. */
async function pilotRace(setup) {
    const B = await bootRacer();
    setup(B);
    key(B.S, "e"); B.run(2);
    key(B.S, "L"); B.run(40);
    B.S.demo.input(5); B.S.demo.inputRelease(5);
    return B;
}

async function decals() {
    const on = await pilotRace(() => {});
    const off = await pilotRace((B) => key(B.S, "d"));
    let bad = 0, frames = 0, carpx = 0, worst = null;
    for (let f = 0; f < 900; f++) {
        on.S.frame(); off.S.frame();
        const a = on.view(), b = off.view();
        let n = 0;
        for (let i = Y0 * W; i < Y1 * W; i++) {
            if (b[i] < CAR_LO || b[i] >= CAR_HI) continue;
            carpx++;
            if (a[i] !== b[i]) n++;
        }
        if (n) { bad += n; frames++; if (!worst || n > worst.n) worst = { f, n, a, b }; }
    }
    if (worst) { await shot("bugpass_decal_on.png", on, worst.a); await shot("bugpass_decal_off.png", off, worst.b); }
    if (carpx < 100000) fail(`decals: only ${carpx} car pixels seen in 900 frames (the race did not run?)`);
    if (bad) fail(`decals: ${bad} car pixels painted over by a decal in ${frames} frames (worst frame ${worst.f}: ${worst.n})`);
    else notes.push(`decals: ${carpx} car pixels over 900 frames of an ARCADE race on Salt Flats, the same with the decals off`);
}

/** The effects' writes in an ARCADE race (the fake queue host of racer_audio_check.mjs: drained every frame). */
async function sound(classic = false) {
    const cmds = [];
    let block = 0;
    const B = await bootRacer(SALT_TAPS, (env) => { env.hostBardAttach = (b) => { block = b; return b ? 1 : 0; }; });
    B.S.machine.hwSetCaps(0x7f);
    const drain = () => {
        if (!block) return;
        const u = new Uint32Array(B.S.memory.buffer), h = block >> 2, head = u[h + 4];
        for (let t = u[h + 5]; t !== head; t = (t + 1) >>> 0) { const c = h + 16 + 4 * (t % 256); cmds.push([u[c + 1], u[c + 2]]); }
        u[h + 5] = head;
        u[h + 7] = u[h + 7] + 735; u[h + 8] = 1;
    };
    B.S.frame(); drain();
    if (BREAK === "mute") key(B.S, "h");
    if (classic) key(B.S, "T"); // the PHYSICS option CLASSIC (the M5 / M6 cards' only model)
    key(B.S, "e"); B.S.frame(); drain();
    B.S.demo.input(5); B.S.demo.inputRelease(5);
    for (let f = 0; f < 240; f++) { B.S.frame(); drain(); } // the countdown
    B.S.demo.input(5); // a player's race: the throttle held (no AI pilot), straight on into the first bend's wall
    for (let f = 0; f < 900; f++) { B.S.frame(); drain(); }
    B.S.demo.inputRelease(5);
    const driven = new Set(cmds.filter(([a]) => a === 0xc1a2).map(([, v]) => v)).size;
    key(B.S, "L"); // ... then the AI pilot flies the player (its engine note follows the revs too)
    for (let f = 0; f < 600; f++) { B.S.frame(); drain(); }
    const keyOn = (code) => cmds.filter(([a, v]) => a === 0xc028 && v === (0xf0 | code)).length;
    const fnums = new Set(cmds.filter(([a]) => a === 0xc1a2).map(([, v]) => v));
    const skid = cmds.filter(([a, v]) => a === 0xc200 && v === 0xf5).length;
    const piloted = fnums.size - driven;
    const got = { engine: keyOn(6), driven, piloted, skid, impact: keyOn(5), commands: cmds.length };
    const model = classic ? "CLASSIC" : "ARCADE";
    if (got.engine < 1 || driven < 8 || piloted < 4 || got.skid < 1 || got.impact < 1) fail(`sound: ${classic ? "a" : "an"} ${model} race's effects missing ${JSON.stringify(got)}`);
    else notes.push(`sound: ${classic ? "a" : "an"} ${model} race on the public cart: the engine keyed on (${got.engine}), ${driven} engine pitches driven, ${piloted} more on the AI pilot, the skid noise on ${got.skid} times, ${got.impact} impacts (${got.commands} queue commands)`);
}

/** The visibility oracle over each committed Kit track's flyby lap (720 frames, its three POVs). */
async function visibility() {
    for (const [taps, name] of [[2, "SALT"], [3, "NEON"], [4, "GLACIER"]]) {
        const B = await bootRacer(taps);
        if (BREAK === "pvs") key(B.S, "@");
        key(B.S, "2"); key(B.S, "l");
        B.run(720);
        const rows = B.lines("pvs").map((r) => r.map(Number));
        const lost = rows.reduce((a, r) => a + r[0], 0), dropped = Math.max(...rows.map((r) => r[3]));
        const blinks = rows.reduce((a, r) => a + r[2], 0);
        if (rows.length < 700) fail(`visibility ${name}: ${rows.length} racer,pvs lines (the oracle did not run)`);
        else if (lost || dropped) fail(`visibility ${name}: the PVS lost ${lost} kept faces over the flyby, ${dropped} polygons dropped at the cap`);
        else notes.push(`visibility ${name}: the flyby's ${rows.length} frames, no face of the view wedge missing from the PVS, none dropped (${blinks} one-frame blinks: the flyby camera's yaw at the screen edge, edge-on faces)`);
    }
}

/** The race HUD over the picture against the bands, and on both fills. */
async function hud() {
    const pic = await pilotRace((B) => { if (BREAK === "hud") key(B.S, "0"); });
    const bands = await pilotRace((B) => key(B.S, "0"));
    const aff = await pilotRace((B) => { if (BREAK === "hud") key(B.S, "0"); key(B.S, "f"); });
    const step = (n) => { for (let i = 0; i < n; i++) { pic.S.frame(); bands.S.frame(); aff.S.frame(); } };
    const MAP = [250, 44, 64, 56];
    const inMid = (x, y) => y >= 62 && y < 102 && x >= 64 && x < 256; // the middle's messages: EXTEND TIME, FINISH
    const inHud = (x, y) => y < 46 || y >= 150 || inMid(x, y) || (x >= MAP[0] - 2 && x < MAP[0] + MAP[2] + 3 && y >= MAP[1] - 2 && y < MAP[1] + MAP[3] + 3);
    step(60); // the countdown
    let a = pic.view(), b = bands.view(), mid = 0;
    for (let i = Y0 * W; i < Y1 * W; i++) if (a[i] !== b[i] && inMid(i % W, (i / W) | 0)) mid++;
    if (mid < 100) fail(`hud: no countdown digit in the middle of the view (${mid} pixels)`);
    step(600);
    a = pic.view(); b = bands.view();
    const c = aff.view();
    let diff = 0, stray = 0, ink = 0;
    for (let i = Y0 * W; i < Y1 * W; i++) if (a[i] !== b[i]) { diff++; if (!inHud(i % W, (i / W) | 0)) stray++; }
    for (let i = 0; i < W * H; i++) if ((i < Y0 * W || i >= Y1 * W) && a[i] !== 2 && a[i] !== 0) ink++; // PAPER or index 0: black
    await shot("bugpass_hud.png", pic, a);
    if (diff < 1500) fail(`hud: the picture HUD draws ${diff} pixels in the race (none?)`);
    if (stray) fail(`hud: ${stray} pixels changed outside the HUD's places`);
    if (ink) fail(`hud: ${ink} band pixels not blank under the picture HUD`);
    if (c.some((v, i) => v !== a[i])) fail("hud: the view with the HUD differs between the CPU and AFFINE fills");
    const h = createHash("sha256").update(a).digest("hex").slice(0, 12);
    if (PRINT) console.log(`PIN hud "${h}"`);
    else if (!BREAK && h !== PINS.hud) fail(`hud: the race frame's hash ${h} != the pin ${PINS.hud}`);
    notes.push(`hud: ${diff} pixels of HUD over the race's picture, all in its places, the bands blank, CPU = AFFINE; the countdown's digit ${mid} pixels in the middle`);
}

if (BREAK === "mute") await sound();
else if (BREAK === "hud") await hud();
else if (BREAK === "pvs") await visibility();
else { await decals(); await sound(); await sound(true); await visibility(); await hud(); }
if (BREAK) { // a mutant must be caught: the harness passes when its checks fail
    if (errors.length === 0) { console.error(`racer_bugpass --break ${BREAK}: NOT caught`); process.exit(1); }
    console.log(`racer_bugpass --break ${BREAK}: caught (${errors[0]})`);
    process.exit(0);
}
for (const n of notes) console.log(`  ${n}`);
console.log(errors.length ? `racer_bugpass: FAILED -- ${errors.join("; ")}` : "racer_bugpass: PASS");
process.exitCode = errors.length ? 1 : 0;
