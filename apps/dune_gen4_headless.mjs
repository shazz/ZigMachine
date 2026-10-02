// Headless DUNE GEN4 DEMO driver -- boots the sealed machine as
// docs/sealed-loader.js does, runs the cart one VBL a frame (dt = 20 ms) and
// holds every frame that matters against the ORIGINAL: frames of DUNE.PRG
// running in Hatari (apps/dune_gen4_ref.bin.gz, made by
// prototypes/dune_gen4_re/mkref.py from an AVI recorded one frame a VBL),
// compared as ST colour words over the whole window Hatari captures -- borders,
// rasters and all (ST x -40..359, y -29..239).
//   pixels   every reference frame, pixel for pixel: the intro's bounce (the
//            flick at the turn), the fade-in step by step, the main
//            part's letters, bars, rainbow and the scroller in the lower border
//   music    Gen4.sndh when the main part starts, silence for the title
//            (its tune is a Quartet one), the menu's poked copy at the menu
//   keys     Space ends the main part, Space leaves the title, F1 opens the
//            BLACK letters, Space returns to the menu; Escape asks for the menu disk
//   cost     mean ms a frame
//   node apps/dune_gen4_headless.mjs [--break pixels|lag|music] [outdir]
//     --break pixels  compares one main-part frame against the NEXT one
//     --break lag     shows the intro's bounce one VBL late (the latch)
//     --break music   expects the main part's tune at the menu
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { gunzipSync } from "node:zlib";
import { cartRam, romRam } from "../docs/wasm_hiwater.js";

const PAGES = 112; // must match SHARED_PAGES in machine/sdk/memmap.zig
const BREAKS = ["pixels", "lag", "music"];
const bi = process.argv.indexOf("--break");
const broke = bi > 0 ? process.argv[bi + 1] : null;
if (bi > 0 && !BREAKS.includes(broke)) throw new Error(`--break ${BREAKS.join(" | ")}`);
const outdir = process.argv.slice(2).find((a, i, v) => !a.startsWith("--") && v[i - 1] !== "--break") || "/tmp/dune_gen4";
const K = { space: 32, esc: 0xe012, f1: 0xe001 };
const MAIN_FIRST_VBL = 437; // the main part's first VBL (intro.zig's timeline)
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
    const ram = ["Base", "Top", "Size", "Used", "Free", "Alloc", "Mark", "Release", "AllocFailures"];
    const env = { ...env0, ...rom, jsConsoleLogWrite: noop, jsConsoleLogFlush: noop, jsThrowError: noop,
        consoleLogJS: noop, audioPlay: noop, audioStop: noop, loadSample: noop, beep: noop, diskReadBlock: noop,
        hostAudioStreamStart: noop, hostAudioFeed: noop, hostAudioStreamStop: noop };
    for (const r of ram) env[`hwRam${r}`] = machine[`hwRam${r}`];
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
    run(n) {
        for (let i = 0; i < n; i++) {
            const t0 = performance.now();
            this.machine.hwClear();
            this.demo.frame(20); // one 50 Hz VBL
            this.machine.hwRenderPlane(0);
            this.cost.push(performance.now() - t0);
            this.vbls++;
            if (this.demo.pollSongRequest()) {
                const name = new TextDecoder().decode(new Uint8Array(this.memory.buffer, this.demo.songNamePtr(), this.demo.songNameLen()));
                this.songs.push([this.vbls, name]);
            }
        }
    }
    runTo(vbl) { this.run(vbl - this.vbls); }
    key(cp) { this.demo.key(cp); }
    // The ST colour word of ST pixel (x, y): plane pixel (x + 40, y + 40).
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
    const raw = gunzipSync(await readFile("apps/dune_gen4_ref.bin.gz"));
    const n = raw.readUInt32LE(0);
    const head = JSON.parse(raw.subarray(4, 4 + n).toString());
    const size = head.w * head.h * 2;
    head.frames.forEach((f, i) => {
        const at = 4 + n + i * size;
        f.words = new Uint16Array(raw.buffer.slice(raw.byteOffset + at, raw.byteOffset + at + size));
    });
    return head;
}

/// Hold the cart's frame against a Hatari frame; the first few differences.
// On the ST a Timer B colour write lands when the interrupt is taken, and an
// interrupt waits for the instruction in progress (a long movem in the VBL's
// music call): now and then a line's first pixels still show the register as
// the line above had it. Hatari reproduces that cycle by cycle; the cart
// changes registers between lines. Such a pixel -- in the first 48 of the line,
// showing what the line above shows -- is counted, not failed, up to 3 lines.
const LATE_X = 48, LATE_LINES = 3;
let lateTotal = 0;

/// Hold the cart's frame against a Hatari frame; the first difference.
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

async function pixels(ref) {
    const cart = await boot();
    for (const f of ref.frames) {
        const late = (broke === "lag" && f.label.startsWith("bounce")) || (broke === "pixels" && f.label === "main-44");
        const at = f.vbl + (late ? 1 : 0);
        cart.runTo(at);
        const diff = compare(cart, ref, f);
        if (diff) fail("pixels", `${f.label} (VBL ${f.vbl}, Hatari ${f.hatari_vbl}): ${diff}`);
        await cart.shot(`${outdir}/${f.label}.ppm`);
    }
    if (!errors.length) console.log(`  pixels: ${ref.frames.length} frames equal Hatari's, ${ref.w}x${ref.h} ST pixels each (${lateTotal} line starts late by Timer B latency)`);
    return cart;
}

const out = await mkdir(outdir, { recursive: true });
void out;
const ref = await reference();
const cart = await pixels(ref);
await import("./dune_gen4_keys.mjs").then((m) => m.keys(cart, { fail, broke, MAIN_FIRST_VBL, K, outdir }));
const mean = cart.cost.reduce((a, b) => a + b, 0) / cart.cost.length;
if (mean > COST_MS) fail("cost", `mean frame ${mean.toFixed(3)} ms > ${COST_MS} ms`);
console.log(`  cost: mean ${mean.toFixed(3)} ms a frame over ${cart.cost.length} (cart + plane render)`);

if (broke) {
    const check = { pixels: "pixels: main-44", lag: "pixels: bounce", music: "music:" }[broke];
    const hit = errors.find((e) => e.startsWith(check));
    console.log(hit ? `dune_gen4: PASS (--break ${broke} caught: ${hit})` : `dune_gen4: FAILED -- --break ${broke} was not caught`);
    process.exit(hit ? 0 : 1);
}
console.log(errors.length ? `dune_gen4: FAILED -- ${errors.join("; ")}` : "dune_gen4: all pass");
process.exit(errors.length ? 1 : 0);
