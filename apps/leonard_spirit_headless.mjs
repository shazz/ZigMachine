// Headless LEONARD'S SPIRIT check (cart 108, apps/zig/scenes/leonard_spirit.zig):
// Leonard/Oxygene's 312-sprite record redone for many more balls, ONE plane.
// The harness holds the cart to its OWN model, written from the scene's
// documented maths (not from the Zig):
//
//   count   the cart draws NB = 8 x 312 balls a frame (lsState(0)): eight
//           snakes, each the 2005 record's 312-ball snake on its own curve of
//           the family; the model's frame 0 has over 2,000 distinct ball
//           positions (one longer chain at 1 degree would only redraw itself
//           past 360); how many balls show at least one pixel is printed
//   pixels  every frame for a whole scrolltext lap and its wrap (> 2 path
//           periods of 360), plane 0 is byte for byte: back.raw, then the NB
//           balls in order, snake k with a2 += k 2^27, b2 += k 2^26 (x = 152 + ((76 cos a1 + 76 sin a2) >> 15),
//           y = 92 + ((44 cos b1 + 44 sin b2) >> 15), Q15 sine of 1,024 steps,
//           u32 turns), then the 6x6 scroller's ink at y 194, 2 pixels a frame
//   planes  only plane 0 is enabled; every 500 frames the plane as the machine
//           composes it shows the merged palette of the plane's indices: 0-3
//           back_pal, 4-6 ball_pal 1-3, 7 font_pal 1 (the RGBA words)
//   music   sos.sndh requested at start
//
//   node apps/leonard_spirit_headless.mjs [--break pixels|count|music|palette] [--ppm F]
//     each --break must be caught (the model is wrong on purpose)
import { readFileSync, writeFileSync } from "node:fs";
import { cartRam } from "../docs/wasm_hiwater.js";

const PAGES = 112; // SHARED_PAGES in machine/sdk/memmap.zig
const SNAKES = 8, SNAKE_LEN = 312, NB = SNAKES * SNAKE_LEN; // the record (leonard_spirit.zig NB)
const W = 320, H = 200, SCROLL_Y = 194;
const A = "apps/zig/assets/screens/leonard/";
const argv = process.argv.slice(2);
const opt = (n) => { const i = argv.indexOf(n); return i < 0 ? null : argv[i + 1]; };
const brk = opt("--break");
if (brk && !["pixels", "count", "music", "palette"].includes(brk)) throw new Error("--break pixels|count|music|palette");
const ppm = opt("--ppm");

// ---------------- boot -------------------------------------------------------
const memory = new WebAssembly.Memory({ initial: PAGES, maximum: PAGES });
let demo;
const machine = (await WebAssembly.instantiate(readFileSync("docs/machine-video.wasm"), {
    env: { memory, hblDispatch: (id, p, l, x) => demo.hblDispatch(id, p, l, x) },
})).instance.exports;
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

// ---------------- the model --------------------------------------------------
const back = readFileSync(A + "back.raw"), ball = readFileSync(A + "ball.raw"), font = readFileSync(A + "font.raw");
const SIN = Int16Array.from({ length: 1024 }, (_, i) => Math.round(32767 * Math.sin((i * 2 * Math.PI) / 1024)));
const DEG = Uint32Array.from({ length: 360 }, (_, d) => Number((BigInt(d) << 32n) / 360n));
const sin = (a) => SIN[a >>> 22], cos = (a) => SIN[((a >>> 22) + 256) & 1023];
const nModel = brk === "count" ? NB + 1 : NB;
const MERGED = mergedPalette();
const STEP = DEG[1]; // t = 1 degree, as in 2005

// --break count: the last snake is one ball longer
function positions(f) {
    const out = new Int32Array(2 * nModel);
    let n = 0;
    for (let k = 0; k < SNAKES; k++) {
        let a1 = DEG[(3 * f) % 360], a2 = (DEG[(2 * f) % 360] + k * 2 ** 27) >>> 0;
        let b1 = DEG[(360 - f) % 360], b2 = (DEG[(2 * f) % 360] + k * 2 ** 26) >>> 0;
        const len = SNAKE_LEN + (k === SNAKES - 1 ? nModel - NB : 0);
        for (let i = 0; i < len; i++, n++) {
            out[2 * n] = 152 + ((76 * (cos(a1) + sin(a2))) >> 15);
            out[2 * n + 1] = 92 + ((44 * (cos(b1) + sin(b2))) >> 15);
            a1 = (a1 + 7 * STEP) >>> 0; a2 = (a2 - 4 * STEP) >>> 0;
            b1 = (b1 + 6 * STEP) >>> 0; b2 = (b2 - 3 * STEP) >>> 0;
        }
    }
    return out;
}

const TEXT_2005 = "HI EVERYBODY ! ULTRA OPTIMISATION RULES, EVEN FOR STUPID RECORD ! I NEVER THOUGH I COULD DISPLAY 312 SPRITES ONE YEAR AGO !  I TOTALLY REWRITE MY PC DATABUILDER TO IMPLEMENT NEW STUFF. THEN, I CHANGE THE CLEARING DATA FORMAT TO GET SOME MEMORY LEFT AND THAT IS !THAT DISK SHOULD (I HOPE) RUN ON 520-STF,MEGASTE,TT,FALCON AND EVEN CT60. GREETINGS ARE SENT TO PHANTOM, GUNSTICK AND SOTE. YOU ALL ARE COOL OPTIMIZERS !  LEONARD/OXYGENE, 17.03.2005";
const TEXT = " ".repeat(92) + TEXT_2005;
const LAP = () => demo.lsState(4); // the cart's lap in frames, checked against the model's text below

// the 6x6 ink of letter c at strip pixel column sx (0..5) and row r
const ink = (c, sx, r) => font[(c.charCodeAt(0) - 32) * 36 + r * 6 + sx] !== 0;

function model(f, t, text, plane) {
    plane.set(back);
    const pos = positions(f);
    for (let i = 0; i < nModel; i++) {
        const x = pos[2 * i], y = pos[2 * i + 1];
        for (let r = 0; r < 16; r++) for (let c = 0; c < 16; c++) {
            const v = ball[r * 16 + c];
            if (v) plane[(y + r) * W + x + c] = v + 3;
        }
    }
    if (brk === "pixels" && f === 77) plane[pos[1] * W + pos[0] + 8] ^= 1;
    const s = t * 2;
    for (let x = 0; x < W; x++) {
        const p = (s + x) % (text.length * 6), ch = text[Math.floor(p / 6)];
        for (let r = 0; r < 6; r++) if (ink(ch, p % 6, r)) plane[(SCROLL_Y + r) * W + x] = 7;
    }
    return pos;
}

// the 2005 words, then the line announcing the new count (NB inside)
const TEXT_NOW = `      ...AND THE STUPID RECORD STRIKES BACK ! ${NB} SPRITES = 8 TIMES 312, ALL OF THEM DRAWN EVERY FRAME, 60 FPS ON ZIGGY. SAME SPIRIT AS 2005 : THE DATABUILDER DOES THE THINKING, THE PLAYER JUST RUNS. EACH BALL IS GENERATED CODE, 72 MOVES AND NOT ONE MASK, ONE BLITTER COPY FOR THE CLEAR, ONE PLANE, NOTHING COMPUTED TWICE. WHO WANTS TO BEAT IT ?  ULTRA OPTIMISATION STILL RULES !`;
const FULL = TEXT + TEXT_NOW;

// ---------------- 1. music, count, planes, palette ---------------------------
{
    const pending = demo.pollSongRequest();
    const name = new TextDecoder().decode(new Uint8Array(memory.buffer, demo.songNamePtr(), demo.songNameLen()));
    const want = brk === "music" ? "mad_max_sos.sndh" : "sos.sndh";
    ok(pending === 1 && name === want, `music: asked for ${name} (want ${want})`);
    ok(demo.lsState(0) === nModel && nModel > 312, `count: the cart draws ${demo.lsState(0)} balls a frame (model ${nModel}, the 2005 record 312)`);
    ok(LAP() === FULL.length * 3, `scroller: one lap = ${LAP()} frames (${FULL.length} letters x 6 px / 2)`);
}

// ---------------- 2. every frame ---------------------------------------------
const FRAMES = LAP() + 400; // a whole lap of the text, its wrap, and > 2 path periods
const want = new Uint8Array(W * H);
let bad = 0, palBad = 0, first = null, minVis = Infinity, maxVis = 0, distinct0 = 0;
for (let n = 0; n < FRAMES; n++) {
    const f = demo.lsState(1), t = demo.lsState(2);
    demo.frame(16.6);
    const pos = model(f, t, FULL, want);
    const got = new Uint8Array(memory.buffer, demo.lsPlane(), W * H);
    if (n === 0) distinct0 = new Set(Array.from({ length: nModel }, (_, i) => pos[2 * i] * 1000 + pos[2 * i + 1])).size;
    if (n % 97 === 0) {
        const seen = new Set([-1]);
        const owner = new Int32Array(W * H).fill(-1);
        for (let i = 0; i < nModel; i++) for (let r = 0; r < 16; r++) for (let c = 0; c < 16; c++)
            if (ball[r * 16 + c]) owner[(pos[2 * i + 1] + r) * W + pos[2 * i] + c] = i;
        for (let y = 0; y < SCROLL_Y; y++) for (let x = 0; x < W; x++) seen.add(owner[y * W + x]);
        minVis = Math.min(minVis, seen.size - 1); maxVis = Math.max(maxVis, seen.size - 1);
    }
    let diff = -1;
    for (let i = 0; i < W * H; i++) if (got[i] !== want[i]) { diff = i; break; }
    if (diff >= 0) { bad++; first ??= `frame ${n} (path ${f}, tick ${t}): x ${diff % W} y ${Math.floor(diff / W)} cart ${got[diff]} model ${want[diff]}`; }
    if (ppm && n === 100) writePpm(ppm, got);
    if (n % 500 === 0) palBad += paletteErrors(got);
    if (n === 1) {
        let planes = 0;
        for (let p = 0; p < 4; p++) planes += demo.isPlaneEnabled(p) ? 1 << p : 0;
        ok(planes === 1, `planes: only plane 0 enabled (mask ${planes})`);
    }
}
ok(palBad === 0, `palette: the composed plane shows the merged palette (${palBad} wrong pixels on ${Math.ceil(FRAMES / 500)} frames)`);
ok(bad === 0, `pixels: plane 0 = model on ${FRAMES - bad}/${FRAMES} frames${first ? `; first: ${first}` : ""}`);
ok(distinct0 > 2000, `count: ${distinct0} distinct ball positions in frame 0 of ${nModel} (not one chain redrawn over itself)`);
console.log(`  info balls with a visible pixel (rows above the scroller), sampled: ${minVis}..${maxVis} of ${nModel}`);

// the merged palette as the machine stores it (a<<24 | b<<16 | g<<8 | r);
// --break palette swaps two ball shades
function mergedPalette() {
    const word = (f, i) => readFileSync(A + f).readUInt32LE(i * 4);
    const e = [0, 1, 2, 3].map((i) => word("back_pal.dat", i))
        .concat([1, 2, 3].map((i) => word("ball_pal.dat", i)), [word("font_pal.dat", 1)]);
    if (brk === "palette") [e[4], e[5]] = [e[5], e[4]];
    return e;
}

// plane pixel (x, y) is physical (80 + 2x, 40 + y) of the 800x280 raster
function paletteErrors(plane) {
    machine.hwRenderPlane(0);
    const snap = new Uint32Array(memory.buffer, machine.hwPhysicalPtr(), 800 * 280);
    let n = 0;
    for (let y = 0; y < H; y++) for (let x = 0; x < W; x++)
        if (snap[(40 + y) * 800 + 80 + 2 * x] >>> 0 !== MERGED[plane[y * W + x]]) n++;
    return n;
}

function writePpm(file, plane) {
    const pal = readFileSync(A + "back_pal.dat"), bp = readFileSync(A + "ball_pal.dat"), fp = readFileSync(A + "font_pal.dat");
    const rgb = (i) => (i < 4 ? pal.subarray(i * 4) : i < 7 ? bp.subarray((i - 3) * 4) : fp.subarray(4));
    const body = Buffer.alloc(W * H * 3);
    for (let i = 0; i < W * H; i++) { const c = rgb(plane[i]); body[3 * i] = c[0]; body[3 * i + 1] = c[1]; body[3 * i + 2] = c[2]; }
    writeFileSync(file, Buffer.concat([Buffer.from(`P6\n${W} ${H}\n255\n`), body]));
}

if (brk) {
    console.log(errors.length ? `leonard_spirit: PASS (--break ${brk} caught: ${errors[0]})` : `leonard_spirit: FAILED -- --break ${brk} was not caught`);
    process.exit(errors.length ? 0 : 1);
}
console.log(errors.length ? `leonard_spirit: FAILED -- ${errors.join("; ")}` : `leonard_spirit: all pass, ${NB} balls, ${FRAMES} frames`);
process.exit(errors.length ? 1 : 0);
