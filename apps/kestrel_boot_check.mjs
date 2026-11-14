// KESTREL BOOT (cart "kestrel_boot", apps/zig/scenes/kestrel_boot.zig): the WINDHOVER boot
// screen (prototypes/boot_screen/STUDY.md). Boots the cart over the real machine + ROM, runs
// 420 host frames as the page does (hwClear, frame, every enabled plane rendered, the effects
// queue drained after the frame) and checks the storyboard:
//   black     frames 1..19 are black, the whole composed raster
//   sky       the sky is up by frame 80 (a bright, many-coloured picture), on the true-colour plane
//   stoop     frames 50..95 all differ (the bird moves), then 170..249 are one still picture
//   raster    while the highlight runs (frame 100) plane 1's copper list changes colours on
//             many lines; once it is over (frame 200) only its first line has a record
//   black end the picture is black from frame 290 and stays black to the end (no loop)
//   length    first light to black between 3 and 6 s
//   jingle    the YM stream (zg.ymWrite entries): the call on C at 20 / 28 / 36, R13 written
//             exactly once (frame 95, 0x0E, with R8 = 0x10: the buzzer), the last write by
//             frame 260 leaving the mixer off and every volume 0; never more than the queue holds
//   node apps/kestrel_boot_check.mjs [cart.wasm]
//   node apps/kestrel_boot_check.mjs --break   each mutant (nofade, silent, slow, nocopper,
//                                              retrigger, frozen) must be caught by the checks
import { readFile } from "node:fs/promises";
import { createHash } from "node:crypto";
import { cartRam, romRam } from "../docs/wasm_hiwater.js";
import { OFF_VRAM, REG_FB_COPPER } from "./linebase_model.mjs";

const PAGES = 128, FRAMES = 420, REG_TC_FADE = 0x0C, FX_YM = 3, FX_CAP = 32;
const BROKE = process.argv.includes("--break");
const [cart = "docs/demo-kestrel_boot.wasm"] = process.argv.slice(2).filter((a) => !a.startsWith("--"));

async function boot() {
    const memory = new WebAssembly.Memory({ initial: PAGES, maximum: PAGES });
    let demo;
    const machine = (await WebAssembly.instantiate(await readFile("docs/machine-video.wasm"), {
        env: { memory, hblDispatch: (id, p, l, x) => demo.hblDispatch(id, p, l, x) },
    })).instance.exports;
    const romBytes = await readFile("docs/rom.wasm");
    const rom = (await WebAssembly.instantiate(romBytes, {
        env: { memory, hwVideoBase: machine.hwVideoBase, hwBlit: machine.hwBlit },
    })).instance.exports;
    machine.hwSetRomHigh(romRam(romBytes).high ?? 0);
    const cartBytes = await readFile(cart);
    const env = { memory, ...rom };
    for (const k of Object.keys(machine)) if (k.startsWith("hw")) env[k] = machine[k];
    for (const imp of WebAssembly.Module.imports(new WebAssembly.Module(cartBytes)))
        if (imp.module === "env" && !(imp.name in env)) env[imp.name] = () => {};
    demo = (await WebAssembly.instantiate(cartBytes, { env })).instance.exports;
    machine.hwSetCartHigh(cartRam(cartBytes).high ?? 0);
    machine.hwInit();
    demo.boot();
    demo.skipBoot();
    return { memory, machine, demo, video: machine.hwVideoBase() };
}

// The page's frame: the composed raster (planes stacked, alpha 0 shows what is under) and the
// frame's YM writes [reg, value]. `brk` mutates the run the way a broken cart would.
function frame(m, f, brk) {
    const { machine, demo, memory } = m;
    machine.hwClear();
    const skip = (brk === "slow" && f % 2 === 1) || (brk === "frozen" && f >= 150);
    if (!skip) demo.frame(1000 / 60);
    const dv = new DataView(memory.buffer);
    if (brk === "nofade") dv.setUint8(m.video + REG_TC_FADE, 0);
    if (brk === "nocopper") dv.setUint16(m.video + REG_FB_COPPER + 2, 0, true);
    const n = demo.pollSfx(), at = demo.sfxEntriesPtr(), ym = [];
    for (let i = 0; i < n; i++) if (dv.getUint8(at + i * 16) === FX_YM) ym.push([dv.getUint8(at + i * 16 + 1), dv.getUint8(at + i * 16 + 2)]);
    const size = machine.hwPhysWidth() * machine.hwPhysHeight();
    const comp = new Uint32Array(size);
    for (let p = 0; p < machine.hwPlanesNumber(); p++) {
        if (!demo.isPlaneEnabled(p)) continue;
        machine.hwRenderPlane(p);
        const snap = new Uint32Array(memory.buffer, machine.hwPhysicalPtr(), size);
        for (let i = 0; i < size; i++) if (snap[i] >>> 24) comp[i] = snap[i];
    }
    return { comp, ym: brk === "silent" ? [] : ym, fx: n, copper: copperHeads(m) };
}

// Plane 1's copper list: how many line records (HEAD words) it holds this frame.
function copperHeads(m) {
    const dv = new DataView(m.memory.buffer);
    const v = dv.getUint16(m.video + REG_FB_COPPER + 2, true);
    if (!v) return 0;
    let heads = 0;
    // HEAD = 0xF << 28 | row << 19 | the count of words after it (libs/zig/effects/copper.zig build)
    for (let a = m.video + OFF_VRAM + v * 16; heads <= 400; heads++) {
        const w = dv.getUint32(a, true);
        if (w >>> 28 !== 0xF || ((w >>> 19) & 511) === 511) return heads;
        a += 4 * (1 + (w & 0x7FFFF));
    }
    return heads;
}

const rgbSum = (c) => (c & 255) + ((c >>> 8) & 255) + ((c >>> 16) & 255);
function stats(comp) {
    let lit = 0, sum = 0;
    const colours = new Set();
    for (const c of comp) {
        const s = rgbSum(c);
        if (s) lit++;
        sum += s;
        colours.add(c & 0xFFFFFF);
    }
    return { lit, mean: sum / comp.length / 3, colours: colours.size, hash: createHash("md5").update(comp).digest("hex") };
}

async function run(brk) {
    const m = await boot();
    const shots = [], ym = [];
    let fxMax = 0;
    for (let f = 1; f <= FRAMES; f++) {
        const r = frame(m, f, brk);
        const st = stats(r.comp);
        shots[f] = { ...st, copper: r.copper };
        fxMax = Math.max(fxMax, r.fx);
        for (const [reg, v] of r.ym) ym.push({ f, reg, v });
    }
    if (brk === "retrigger") ym.push({ f: 150, reg: 13, v: 0x0E });
    return { shots, ym, fxMax };
}

// cart frame k (0-based) is host frame k + 1
const at = (shots, k) => shots[k + 1];

function checks({ shots, ym, fxMax }) {
    const bad = [];
    const need = (ok, what) => { if (!ok) bad.push(what); };
    for (let k = 0; k < 19; k++) need(at(shots, k).lit === 0, `black: frame ${k} is not black`);
    const up = at(shots, 80);
    need(up.mean > 30 && up.colours > 300, `sky: frame 80 mean ${up.mean.toFixed(1)}, ${up.colours} colours`);
    let moved = 0; // the ease settles: its last steps can round to the same pose
    for (let k = 51; k <= 95; k++) moved += at(shots, k).hash !== at(shots, k - 1).hash;
    need(moved >= 40, `stoop: the bird moved on ${moved} of 45 frames`);
    need(at(shots, 50).hash !== at(shots, 49).hash, "stoop: the bird did not enter at frame 50");
    for (let k = 171; k <= 249; k++) need(at(shots, k).hash === at(shots, 170).hash, `hold: frame ${k} differs from 170`);
    need(at(shots, 100).copper > 20, `raster: ${at(shots, 100).copper} copper lines at frame 100`);
    need(at(shots, 200).copper === 1, `raster: ${at(shots, 200).copper} copper lines at frame 200 (1 expected)`);
    for (let k = 290; k < FRAMES; k++) need(at(shots, k).lit === 0, `black end: frame ${k} is not black`);
    let first = -1, last = -1;
    for (let k = 0; k < FRAMES; k++) if (at(shots, k).lit) { if (first < 0) first = k; last = k; }
    const secs = (last - first + 1) / 60;
    need(first >= 0 && secs >= 3 && secs <= 6, `length: lit ${secs.toFixed(2)} s (frames ${first}..${last})`);
    jingle(ym, need);
    need(fxMax <= FX_CAP, `jingle: ${fxMax} effects in one frame (queue holds ${FX_CAP})`);
    return bad;
}

function jingle(ym, need) {
    const k = (e) => e.f - 1; // cart frame
    for (const c of [20, 28, 36]) need(ym.some((e) => k(e) === c && e.reg === 10 && e.v > 0), `jingle: no call note on C at frame ${c}`);
    const r13 = ym.filter((e) => e.reg === 13);
    need(r13.length === 1 && k(r13[0]) === 95 && r13[0].v === 0x0E, `jingle: R13 written ${r13.length} times (once at 95 expected)`);
    need(ym.some((e) => k(e) === 95 && e.reg === 8 && e.v === 0x10), "jingle: no buzzer (R8 = 0x10) at the chord");
    const regs = new Array(14).fill(0);
    for (const e of ym) regs[e.reg] = e.v;
    const lastF = ym.length ? k(ym[ym.length - 1]) : -1;
    need(ym.length > 0 && lastF <= 260, `jingle: last write at frame ${lastF}`);
    need(regs[7] === 0x3F && regs[8] + regs[9] + regs[10] === 0, `jingle: ends with mixer ${regs[7]}, volumes ${regs.slice(8, 11)}`);
}

const MUTANTS = ["nofade", "silent", "slow", "nocopper", "retrigger", "frozen"];
if (BROKE) {
    let missed = 0;
    for (const b of MUTANTS) {
        const bad = checks(await run(b));
        console.log(`kestrel_boot --break ${b}: ${bad.length ? `caught (${bad[0]})` : "NOT CAUGHT"}`);
        if (!bad.length) missed++;
    }
    process.exit(missed ? 1 : 0);
}
const bad = checks(await run(null));
for (const b of bad.slice(0, 20)) console.log(`kestrel_boot: ${b}`);
console.log(`kestrel_boot: ${bad.length ? `FAIL (${bad.length})` : "OK"}: black 0-19, sky by 80, stoop 50-95, still 170-249, copper highlight, black from 290, YM call + chord`);
process.exit(bad.length ? 1 : 0);
