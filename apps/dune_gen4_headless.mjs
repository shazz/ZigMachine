// Headless DUNE GEN4 DEMO driver -- boots the sealed machine as
// docs/sealed-loader.js does, runs the cart one VBL a frame (dt = 20 ms) and
// holds every frame that matters against the ORIGINAL: DUNE.PRG running in
// Hatari (apps/dune_gen4_ref.bin.br, made by prototypes/dune_gen4_re/mkref.py
// from AVIs recorded one frame a VBL), compared as ST colour words over the
// whole window Hatari captures -- borders, rasters and all (x -40..359,
// y -29..239). The walk through the parts and the music: dune_gen4_keys.mjs.
//   pixels   49 frames: the intro's bounce (the flick at the turn), the fade-in
//            step by step, the main part (letters, colour-0 bars, rainbow, the
//            scroller in the lower border), the title, three visits to the menu
//            (rasters, its scroller carrying on through F1) and two to F1 (the
//            BLACK letters carrying on round their path), two to F2 (HADES)
//   music    Gen4.sndh from the main part, silence for the title (a Quartet
//            tune), the poked copy for the menu, nothing after; Escape -> menu disk
//   cost     mean ms a frame
//   node apps/dune_gen4_headless.mjs [--break pixels|lag|music] [outdir]
//     --break pixels  shows one main-part frame a VBL late
//     --break lag     shows the intro's bounce a VBL late (the screen latch)
//     --break music   expects the main part's tune at the menu
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { brotliDecompressSync } from "node:zlib";
import { cartRam, romRam } from "../docs/wasm_hiwater.js";
import { WALKS, music, walk } from "./dune_gen4_keys.mjs";

const PAGES = 112; // must match SHARED_PAGES in machine/sdk/memmap.zig
const BREAKS = { pixels: "pixels: main-44", lag: "pixels: bounce", music: "music:" };
const bi = process.argv.indexOf("--break");
const broke = bi > 0 ? process.argv[bi + 1] : null;
if (bi > 0 && !(broke in BREAKS)) throw new Error(`--break ${Object.keys(BREAKS).join(" | ")}`);
const outdir = process.argv.slice(2).find((a, i, v) => !a.startsWith("--") && v[i - 1] !== "--break") || "/tmp/dune_gen4";
const COST_MS = 4;
const errors = [];
const fail = (what, msg) => { errors.push(`${what}: ${msg}`); console.log(`  FAIL ${what}: ${msg}`); };

async function boot(cart = "docs/demo-dune_gen4.wasm") {
    const memory = new WebAssembly.Memory({ initial: PAGES, maximum: PAGES });
    let demo;
    const machine = (await WebAssembly.instantiate(await readFile("docs/machine-video.wasm"), {
        env: { memory, hblDispatch: (id, p, l, x) => demo.hblDispatch(id, p, l, x) },
    })).instance.exports;
    const romBytes = await readFile("docs/rom.wasm");
    const env0 = { memory, hwVideoBase: machine.hwVideoBase, hwBlit: machine.hwBlit };
    const rom = (await WebAssembly.instantiate(romBytes, { env: env0 })).instance.exports;
    machine.hwSetRomHigh(romRam(romBytes).high ?? 0);
    const noop = () => {};
    const cartBytes = await readFile(cart);
    const env = { ...env0, ...rom, jsConsoleLogWrite: noop, jsConsoleLogFlush: noop, jsThrowError: noop,
        consoleLogJS: noop, audioPlay: noop, audioStop: noop, loadSample: noop, beep: noop, diskReadBlock: noop,
        hostAudioStreamStart: noop, hostAudioFeed: noop, hostAudioStreamStop: noop };
    for (const r of ["Base", "Top", "Size", "Used", "Free", "Alloc", "Mark", "Release", "AllocFailures"]) env[`hwRam${r}`] = machine[`hwRam${r}`];
    for (const r of ["Base", "Top", "Size", "Used", "Free"]) env[`hwRomRam${r}`] = machine[`hwRomRam${r}`];
    demo = (await WebAssembly.instantiate(cartBytes, { env })).instance.exports;
    machine.hwSetCartHigh(cartRam(cartBytes).high ?? 0);
    machine.hwInit();
    demo.boot();
    demo.skipBoot();
    return new Cart(memory, machine, demo);
}

class Cart {
    constructor(memory, machine, demo) {
        Object.assign(this, { memory, machine, demo, vbls: 0, songs: [], cost: [] });
        this.w = machine.hwPhysWidth(); // 800: x doubled
        this.h = machine.hwPhysHeight(); // 280
        this.pfb = new Uint8Array(memory.buffer, machine.hwPhysicalPtr(), this.w * this.h * 4);
    }
    runTo(vbl) {
        while (this.vbls < vbl) {
            const t0 = performance.now();
            this.machine.hwClear();
            this.demo.frame(20); // one 50 Hz VBL
            this.machine.hwRenderPlane(0);
            this.cost.push(performance.now() - t0);
            this.vbls++;
            if (!this.demo.pollSongRequest()) continue;
            const name = new TextDecoder().decode(new Uint8Array(this.memory.buffer, this.demo.songNamePtr(), this.demo.songNameLen()));
            this.songs.push([this.vbls, name]);
        }
    }
    key(cp) { this.demo.key(cp); }
    /// The ST colour word of ST pixel (x, y): plane pixel (x + 40, y + 40).
    word(x, y) {
        const i = ((y + 40) * this.w + (x + 40) * 2) * 4;
        const g = (c) => Math.round((this.pfb[i + c] * 7) / 255);
        return (g(0) << 8) | (g(1) << 4) | g(2);
    }
    async shot(path) {
        const half = this.w / 2, rgb = new Uint8Array(half * this.h * 3);
        for (let y = 0; y < this.h; y++) for (let x = 0; x < half; x++)
            for (let c = 0; c < 3; c++) rgb[(y * half + x) * 3 + c] = this.pfb[(y * this.w + 2 * x) * 4 + c];
        await writeFile(path, Buffer.concat([Buffer.from(`P6\n${half} ${this.h}\n255\n`), rgb]));
    }
}

async function reference() {
    const raw = brotliDecompressSync(await readFile("apps/dune_gen4_ref.bin.br"));
    const n = raw.readUInt32LE(0);
    const head = JSON.parse(raw.subarray(4, 4 + n).toString());
    const size = head.w * head.h;
    let prev = new Uint16Array(size);
    head.frames.forEach((f, i) => {
        const at = raw.byteOffset + 4 + n + i * size * 2;
        const delta = new Uint16Array(raw.buffer.slice(at, at + size * 2));
        f.words = delta.map((d, k) => d ^ prev[k]); // stored XORed with the frame before
        prev = f.words;
    });
    return head;
}

// On the ST a Timer B colour write lands when the interrupt is taken, and an
// interrupt waits for the instruction in progress (a long movem in the VBL's
// music call): now and then a line's first pixels still show the register as
// the line above had it. Hatari reproduces that cycle by cycle; the cart
// changes registers between lines. Such a pixel -- in the first 48 of the line,
// showing what the line above shows -- is counted, not failed, up to 3 lines.
const LATE_X = 48, LATE_LINES = 3;
let lateTotal = 0;

/// Hold the cart's frame against a Hatari frame.
function compare(cart, ref, f) {
    let bad = 0, first = null;
    const late = new Set();
    for (let y = 0; y < ref.h; y++) for (let x = 0; x < ref.w; x++) {
        const X = ref.x0 + x, Y = ref.y0 + y;
        const want = f.words[y * ref.w + x], got = cart.word(X, Y);
        if (want === got) continue;
        if (X < LATE_X && want === cart.word(X, Y - 1)) { late.add(Y); continue; }
        bad++;
        first ??= `(${X},${Y}) ${got.toString(16)} want ${want.toString(16)}`;
    }
    lateTotal += late.size;
    if (late.size > LATE_LINES) return `${late.size} lines start late (Timer B), more than ${LATE_LINES}`;
    return bad ? `${bad} pixels differ, first ${first}` : null;
}

await mkdir(outdir, { recursive: true });
const ref = await reference();
const shots = [];
const check = (c, f) => {
    const diff = compare(c, ref, f);
    if (diff) fail("pixels", `${f.label} (VBL ${f.vbl}, Hatari ${f.hatari_vbl}): ${diff}`);
    shots.push(c.shot(`${outdir}/${f.label}.ppm`));
};
const costs = [];
for (const name of ["ref4", "ref5"]) {
    const cart = await boot();
    const songs = walk(cart, ref, WALKS[name], check, { fail, broke });
    if (name === "ref4") music(songs, cart, { fail, broke });
    costs.push(...cart.cost);
}
await Promise.all(shots);
if (!errors.some((e) => e.startsWith("pixels")))
    console.log(`  pixels: ${shots.length} frames equal Hatari's, ${ref.w}x${ref.h} ST pixels each (${lateTotal} line starts late by Timer B latency)`);
const mean = costs.reduce((a, b) => a + b, 0) / costs.length;
if (mean > COST_MS) fail("cost", `mean frame ${mean.toFixed(3)} ms > ${COST_MS} ms`);
console.log(`  cost: mean ${mean.toFixed(3)} ms a frame over ${costs.length} (cart + plane render)`);

if (broke) {
    const hit = errors.find((e) => e.startsWith(BREAKS[broke]));
    console.log(hit ? `dune_gen4: PASS (--break ${broke} caught: ${hit})` : `dune_gen4: FAILED -- --break ${broke} was not caught`);
    process.exit(hit ? 0 : 1);
}
console.log(errors.length ? `dune_gen4: FAILED -- ${errors.join("; ")}` : "dune_gen4: all pass");
process.exit(errors.length ? 1 : 0);
