// Headless LEONARD'S SPIRIT check (cart 108, apps/zig/scenes/leonard_spirit.zig):
// Leonard/Oxygene's 312-sprite record redone for many more balls, fullscreen,
// ONE overscan scroll plane. The harness holds the cart to its OWN model
// (apps/leonard_spirit_model.mjs, from the scene's documented maths):
//
//   count    the cart draws NB = SNAKES x 312 balls a frame (lsState(0))
//   show     every frame, the borders open exactly when the show says (180
//            still frames, then the sides, the bottom, the top each shake
//            open/closed with shortening intervals, then stay open), and the
//            scroll phase follows the ease-in (0, then (n/240)^2, then 1 path
//            frame a frame) to cruise
//   pixels   every frame of the show and a whole scrolltext lap: the window
//            the hardware shows (buffer at the pan) is the model byte for byte
//            (back.raw tiled from the first frame's place, the balls, the ink)
//   borders  every frame, the composed 800x280 raster: an open border shows the
//            plane (the merged palette's colours), a closed one the closed
//            border colour, never noise; the picture area always the plane
//   planes   only plane 0 is enabled (one overscan scroll plane)
//   music    sos.sndh requested at start
//
//   node apps/leonard_spirit_headless.mjs [--break pixels|count|music|palette|border|scroll] [--ppm F]
//     each --break must be caught (the model or the machine is wrong on purpose)
import { readFileSync, writeFileSync } from "node:fs";
import { cartRam } from "../docs/wasm_hiwater.js";
import * as M from "./leonard_spirit_model.mjs";

const PAGES = 112; // SHARED_PAGES in machine/sdk/memmap.zig
const argv = process.argv.slice(2);
const opt = (n) => { const i = argv.indexOf(n); return i < 0 ? null : argv[i + 1]; };
const BREAKS = ["pixels", "count", "music", "palette", "border", "scroll"];
const brk = opt("--break");
if (brk && !BREAKS.includes(brk)) throw new Error(`--break ${BREAKS.join("|")}`);
const ppm = opt("--ppm");

// ---------------- boot (--break border: line 137 never reaches the cart) ------
const memory = new WebAssembly.Memory({ initial: PAGES, maximum: PAGES });
let demo;
const hbl = (id, p, l, x) => (brk === "border" && l === 137 ? undefined : demo.hblDispatch(id, p, l, x));
const machine = (await WebAssembly.instantiate(readFileSync("docs/machine-video.wasm"), { env: { memory, hblDispatch: hbl } })).instance.exports;
const romEnv = { memory, hwVideoBase: machine.hwVideoBase, hwBlit: machine.hwBlit };
const rom = (await WebAssembly.instantiate(readFileSync("docs/rom.wasm"), { env: romEnv })).instance.exports;
const cartBytes = readFileSync("docs/demo-leonard_spirit.wasm");
const env = { ...romEnv, ...rom };
for (const k of Object.keys(machine)) if (/^hw(Rom)?Ram/.test(k)) env[k] = machine[k];
for (const imp of WebAssembly.Module.imports(new WebAssembly.Module(cartBytes)))
    if (imp.module === "env" && !(imp.name in env)) env[imp.name] = () => {};
demo = (await WebAssembly.instantiate(cartBytes, { env })).instance.exports;
machine.hwSetCartHigh(cartRam(cartBytes).high ?? 0);
machine.hwInit();
demo.boot();
demo.skipBoot();

const errors = [];
const ok = (cond, msg) => { console.log(`  ${cond ? "ok  " : "FAIL"} ${msg}`); if (!cond) errors.push(msg); };
const st = (k) => demo.lsState(k); // 0 NB, 1 ball frame, 2 tick, 4 lap, 5 t, 6 scroll phase, 7 open mask

// ---------------- 1. music, count, scroller ----------------------------------
{
    const pending = demo.pollSongRequest();
    const name = new TextDecoder().decode(new Uint8Array(memory.buffer, demo.songNamePtr(), demo.songNameLen()));
    const want = brk === "music" ? "mad_max_sos.sndh" : "sos.sndh";
    ok(pending === 1 && name === want, `music: asked for ${name} (want ${want})`);
    const nb = M.NB + (brk === "count" ? 1 : 0);
    ok(st(0) === nb, `count: the cart draws ${st(0)} balls a frame (model ${nb} = ${M.SNAKES} x 312, the 2005 record 312)`);
    ok(st(4) === M.TEXT.length * 3, `scroller: one lap = ${st(4)} frames (${M.TEXT.length} letters x 6 px / 2)`);
}

// ---------------- 2. every frame ---------------------------------------------
const MERGED = M.mergedPalette();
if (brk === "palette") [MERGED[4], MERGED[5]] = [MERGED[5], MERGED[4]];
const FRAMES = Math.max(M.CRUISE + 720, st(4) + 400);
const want = new Uint8Array(M.WIN_W * M.WIN_H), fails = {};
const fail = (what, msg) => { fails[what] ??= { n: 0, first: msg }; fails[what].n++; };
let phase = 0, closedWord = null;
for (let t = 0; t < FRAMES; t++) {
    const f = st(1), tick = st(2), p = phase >> 16, pan = M.pan(p);
    if (st(5) !== Math.min(t, M.CRUISE) || st(6) !== phase) fail("show", `t ${t}: cart t ${st(5)} phase ${st(6)}, model ${phase}`);
    machine.hwClear();
    demo.frame(16.6);
    const mask = st(7);
    if (mask !== M.openMask(t)) fail("show", `t ${t}: borders open ${mask}, model ${M.openMask(t)}`);
    M.windowPixels(want, f, pan, tick, M.TEXT, brk === "count" ? 1 : 0);
    if (brk === "pixels" && t === 777) want[60000] ^= 1;
    const buf = new Uint8Array(memory.buffer, demo.lsPlane(), M.BUF_W * 448);
    pixels: for (let y = 0; y < M.WIN_H; y++) for (let x = 0; x < M.WIN_W; x++) {
        const v = buf[(pan[1] + y) * M.BUF_W + pan[0] + x];
        if (v !== want[y * M.WIN_W + x]) { fail("pixels", `t ${t} (ball frame ${f}, pan ${pan}): x ${x} y ${y} cart ${v} model ${want[y * M.WIN_W + x]}`); break pixels; }
    }
    closedWord = checkComposite(t, buf, pan, M.openMask(t), closedWord);
    if (ppm && t === M.CRUISE + 100) writePpm(ppm, buf, pan);
    if (t === 1) ok([0, 1, 2, 3].every((p) => !!demo.isPlaneEnabled(p) === (p === 0)), "planes: only plane 0 is enabled");
    phase += M.speed(t, brk === "scroll");
    if (phase >= 360 << 16) phase -= 360 << 16;
}
for (const w of ["show", "pixels", "borders"])
    ok(!fails[w], `${w}: ${FRAMES - (fails[w]?.n ?? 0)}/${FRAMES} frames${fails[w] ? `; first: ${fails[w].first}` : ""}`);
console.log(`  info show: sides ${M.stageStart(0)}, bottom ${M.stageStart(1)}, top ${M.stageStart(2)}, all open ${M.OPEN_END}, scroll from ${M.EASE_START}, cruise ${M.CRUISE}`);

// One frame as the machine composes it: per physical line, the borders of an
// open side show the plane, a closed side the closed border colour.
function checkComposite(t, buf, [sx, sy], open, closed) {
    machine.hwRenderPlane(0);
    const snap = new Uint32Array(memory.buffer, machine.hwPhysicalPtr(), 800 * 280);
    closed ??= open & 4 ? null : snap[0] >>> 0; // the first closed top border
    for (let y = 0; y < M.WIN_H; y++) {
        const band = y < 40 ? 4 : y >= 240 ? 2 : 1;
        for (let x = 0; x < M.WIN_W; x++) {
            const inPic = y >= 40 && y < 240 && x >= 40 && x < 360;
            const plane = MERGED[buf[(sy + y) * M.BUF_W + sx + x]];
            const exp = inPic || open & band ? plane : closed;
            const got = snap[y * 800 + 2 * x] >>> 0;
            if (exp !== null && got !== exp) { fail("borders", `t ${t}: line ${y} x ${x} shows ${got.toString(16)}, want ${exp.toString(16)} (open ${open})`); return closed; }
        }
    }
    return closed;
}

function writePpm(file, buf, [sx, sy]) {
    const body = Buffer.alloc(M.WIN_W * M.WIN_H * 3);
    for (let y = 0; y < M.WIN_H; y++) for (let x = 0; x < M.WIN_W; x++) {
        const c = MERGED[buf[(sy + y) * M.BUF_W + sx + x]], i = 3 * (y * M.WIN_W + x);
        body[i] = c & 255; body[i + 1] = (c >> 8) & 255; body[i + 2] = (c >> 16) & 255;
    }
    writeFileSync(file, Buffer.concat([Buffer.from(`P6\n${M.WIN_W} ${M.WIN_H}\n255\n`), body]));
}

if (brk) {
    console.log(errors.length ? `leonard_spirit: PASS (--break ${brk} caught: ${errors[0]})` : `leonard_spirit: FAILED -- --break ${brk} was not caught`);
    process.exit(errors.length ? 0 : 1);
}
console.log(errors.length ? `leonard_spirit: FAILED -- ${errors.join("; ")}` : `leonard_spirit: all pass, ${M.NB} balls, ${FRAMES} frames`);
process.exit(errors.length ? 1 : 0);
