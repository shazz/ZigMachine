// Headless GNOMES driver (cart 104): The Gnomes Group's "BB25" cracktro (Buxton Bytes 2025), ported
// from the original ST binary. Two pins:
//
//   model     every frame to 1200, then checkpoints, the composited 800x280 raster equals a model of
//             the ORIGINAL's code (apps/gnomes_model.mjs: colour 0/1 per line, the swaying logo, the
//             VU meters on the pushed YM registers, the 13 TTY pages, the 8 px/frame scroller)
//   original  at 8 frames captured from the real intro in Hatari (refs in assets/screens/gnomes/ref,
//             tools/private_tools/gnomes_refs.py; frame = the intro's own loop counter, YM registers
//             read at the same instant), the cart's picture equals the capture in ST colour words over
//             the 400x276 the two share. Tolerances, each counted: in the left border the colour may
//             still be the line above's (Timer-B latency, the change lands 0..45 px into the line); the
//             cells of glyphs not yet in the shown buffer before the frame's own loop are skipped (the
//             original types into the screen being displayed, so a fresh glyph above the beam shows late).
//   plus      music, keys, text lengths, border rasters, no allocation refused.
//
//   node apps/gnomes_headless.mjs [outdir]
//   node apps/gnomes_headless.mjs --break raster|sweep|scroll|page|vu|music|pixels   (each must FAIL)
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { inflateSync } from "node:zlib";
import { cartRam } from "../docs/wasm_hiwater.js";
import { loadAssets, Original, PW, PH } from "./gnomes_model.mjs";

const PAGES = 112; // must match SHARED_PAGES in machine/sdk/memmap.zig
const OUT = process.argv[2] && !process.argv[2].startsWith("--") ? process.argv[2] : "/tmp/gnomes";
const BREAKS = ["raster", "sweep", "scroll", "page", "vu", "music", "pixels"];
const bi = process.argv.indexOf("--break");
const broke = bi > 0 ? process.argv[bi + 1] : null;
if (bi > 0 && !BREAKS.includes(broke)) throw new Error(`--break ${BREAKS.join(" | ")}`);

// ---------------- boot (the ikplus shape) -----------------------------------
const memory = new WebAssembly.Memory({ initial: PAGES, maximum: PAGES });
let demo;
const machine = (await WebAssembly.instantiate(await readFile("docs/machine-video.wasm"), {
    env: { memory, hblDispatch: (id, p, l, x) => demo.hblDispatch(id, p, l, x) },
})).instance.exports;
const romEnv = { memory, hwVideoBase: machine.hwVideoBase, hwBlit: machine.hwBlit };
const rom = (await WebAssembly.instantiate(await readFile("docs/rom.wasm"), { env: romEnv })).instance.exports;
const cartBytes = await readFile("docs/demo-gnomes.wasm");
const env = { ...romEnv, ...rom };
for (const k of Object.keys(machine)) if (k.startsWith("hwRam") || k.startsWith("hwRomRam")) env[k] = machine[k];
for (const imp of WebAssembly.Module.imports(new WebAssembly.Module(cartBytes)))
    if (imp.module === "env" && !(imp.name in env)) env[imp.name] = () => {};
async function startCart() {
    demo = (await WebAssembly.instantiate(cartBytes, { env })).instance.exports;
    machine.hwSetCartHigh(cartRam(cartBytes).high ?? 0);
    machine.hwInit();
    demo.boot();
    demo.skipBoot();
}
await startCart();
await mkdir(OUT, { recursive: true });

const errors = [];
const ok = (cond, msg) => {
    console.log(`  ${cond ? "ok  " : "FAIL"} ${msg}`);
    if (!cond) errors.push(msg);
};
const a = await loadAssets();
const songName = () => new TextDecoder().decode(new Uint8Array(memory.buffer, demo.songNamePtr(), demo.songNameLen()));

// ---------------- 1. music, text --------------------------------------------
{
    const pending = demo.pollSongRequest();
    const want = broke === "music" ? "tgg_custodian.sndh" : "custodian.sndh";
    ok(pending === 1 && songName() === want && demo.songTune() === 1, `music: asked for ${songName()} #${demo.songTune()} at start (want ${want} #1)`);
    const pages = [...a.tty].filter((b) => b === 0).length - 1;
    ok(demo.gnBigTextLen() === 2885 && demo.gnTtyLen() === a.tty.length && pages === 13,
        `text: the scroller is ${demo.gnBigTextLen()} chars (2885), the TTY ${demo.gnTtyLen()} bytes in ${pages} pages (13)`);
}

// ---------------- 2. the original's captures --------------------------------
const CAPS = new Map(); // frame -> YM registers 0..13 at that instant
for (const line of (await readFile("apps/zig/assets/screens/gnomes/ref/caps.txt", "utf8")).trim().split("\n")) {
    const [n, ...regs] = line.trim().split(/\s+/);
    CAPS.set(+n, regs.map((h) => parseInt(h, 16)));
}
async function ref(n) {
    const z = await readFile(`apps/zig/assets/screens/gnomes/ref/n${String(n).padStart(4, "0")}.bin.z`);
    const b = inflateSync(z);
    return Uint16Array.from({ length: b.length / 2 }, (_, i) => b.readUInt16LE(2 * i));
}
// A synthetic YM for the other frames, so the meters move (an envelope byte >= 16 lights all 16).
const synth = (n) => { const r = new Array(14).fill(0); r[8] = (n * 7) % 17; r[9] = (n * 5) % 18; r[10] = (n * 3) % 16; return r; };

// ---------------- 3. run --------------------------------------------------------
const PFB_W = 800;
const pfb = new Uint32Array(memory.buffer, machine.hwPhysicalPtr(), PFB_W * PH);
const ymMirror = new Uint8Array(memory.buffer, demo.getYmRegsPointer(), 14);
// The composite back to ST words: gun = ((n & 7) << 1 | n >> 3) * 16, so an ST word's gun is 32 n.
const stOf = (px) => (((px & 255) >> 5) << 8) | ((((px >> 8) & 255) >> 5) << 4) | (((px >> 16) & 255) >> 5);
const cartImage = () => { const o = new Uint16Array(PW * PH); for (let i = 0; i < o.length; i++) o[i] = stOf(pfb[i * 2]); return o; };
const hex = (w) => "$" + w.toString(16).padStart(3, "0");

const model = new Original(a, broke);
const EVERY = 1200, LAST = 3400;
const CHECK = new Set([1500, 2000, 2500, 3000, LAST, ...CAPS.keys()]);
let compared = 0, failure = null, borderColours = 0;
const capReport = [];
for (let n = 1; n <= LAST && !failure; n++) {
    const ym = CAPS.get(n) ?? synth(n);
    ymMirror.set(ym);
    machine.hwClear();
    demo.frame(20.0);
    model.step(n, ym);
    if (demo.gnState(0) !== n) { failure = `frame ${n}: the cart is on frame ${demo.gnState(0)}`; break; }
    if (n > EVERY && !CHECK.has(n)) continue;
    machine.hwRenderPlane(0);
    const got = cartImage(), want = model.image(n);
    if (broke === "pixels" && n === 50) want[140 * PW + 200] ^= 0x111;
    for (let i = 0; i < want.length && !failure; i++)
        if (got[i] !== want[i]) failure = `model: frame ${n} plane (${i % PW},${(i / PW) | 0}) is ${hex(got[i])}, the original's code gives ${hex(want[i])}`;
    compared++;
    if (n === 300) for (const x of [0, PW - 1]) borderColours = Math.max(borderColours, new Set(Array.from({ length: PH }, (_, y) => got[y * PW + x])).size);
    if (CAPS.has(n)) capReport.push(await vsOriginal(n, got));
    if ([1, 300, 1000, 2000].includes(n)) await writeFile(`${OUT}/frame_${String(n).padStart(6, "0")}.ppm`, ppm());
}
if (failure) errors.push(failure);
ok(!failure && compared === EVERY + [...CHECK].filter((n) => n > EVERY).length, `model: ${compared} frames equal the original's code pixel for pixel (every frame to ${EVERY}, then ${[...CHECK].filter((n) => n > EVERY).sort((x, y) => x - y).join("/")})`);
for (const r of capReport) ok(r.bad === 0, r.msg);
ok(borderColours >= 40, `raster: a border column carries ${borderColours} colours down 280 lines (real per-line writes, borders open)`);
ok(machine.hwRamAllocFailures() === 0, "no zg.mem allocation refused");

// The cart's frame n against the Hatari capture of the original's frame n.
async function vsOriginal(n, got) {
    const r = await ref(n);
    const masked = new Set();
    // A glyph is surely on screen above the beam only once the buffer shown in frame n got it
    // in an EARLIER loop: in loop t if t has n's parity, else at its catch-up redraw.
    for (const [t, col, row, c] of model.typed) if (t <= n && !((t - n) % 2 === 0 ? t < n : c < n)) masked.add(`${col},${row}`);
    let same = 0, bad = 0, jitter = 0, race = 0, first = "";
    for (let l = 0; l < 276; l++) for (let cx = 8; cx < 408; cx++) {
        const want = r[l * 416 + cx], px = got[(l + 2) * PW + cx - 8];
        if (px === want) { same++; continue; }
        if (cx < 48 && l > 0 && got[(l + 1) * PW + cx - 8] === want) { jitter++; continue; }
        const sx = cx - 48;
        if (l >= 80 && l < 200 && sx >= 0 && sx < 176 && masked.has(`${sx >> 3},${l >> 3}`)) { race++; continue; }
        if (!bad++) first = ` first at ST (${sx},${l}): cart ${hex(px)}, Hatari ${hex(want)}`;
    }
    return { bad, msg: `original: frame ${n} equals Hatari's capture on ${same} of 110400 pixels; ${jitter} left-border latency, ${race} fresh-glyph race, ${bad} wrong${first}` };
}
function ppm() {
    const body = Buffer.alloc(PFB_W * PH * 3);
    for (let i = 0; i < pfb.length; i++) { body[3 * i] = pfb[i] & 255; body[3 * i + 1] = (pfb[i] >> 8) & 255; body[3 * i + 2] = (pfb[i] >> 16) & 255; }
    return Buffer.concat([Buffer.from(`P6\n${PFB_W} ${PH}\n255\n`), body]);
}

// ---------------- 4. keys ------------------------------------------------------
if (!failure) {
    const tunes = [];
    for (let k = 0; k < 6; k++) {
        demo.key(0xE001 + k);
        demo.frame(20.0);
        tunes.push(demo.pollSongRequest() === 1 && songName() === "custodian.sndh" ? demo.songTune() : -1);
    }
    ok(tunes.join() === "1,2,3,4,5,6" && demo.pollCartRequest() === 0, `keys: F1-F6 request custodian.sndh #${tunes.join(", #")} and stay`);
    for (const [name, act] of [["SPACE", () => demo.key(32)], ["Escape", () => demo.key(0xE012)], ["Back", () => demo.input(6)]]) {
        await startCart();
        act();
        demo.frame(20.0);
        ok(demo.pollCartRequest() === -1, `keys: ${name} hands the screen back`);
    }
}

if (broke) {
    console.log(errors.length ? `gnomes: PASS (--break ${broke} caught: ${errors[0]})` : `gnomes: FAILED -- --break ${broke} was not caught`);
    process.exit(errors.length ? 0 : 1);
}
console.log(errors.length ? `gnomes: FAILED -- ${errors.join("; ")}` : "gnomes: all pass");
process.exit(errors.length ? 1 : 0);
