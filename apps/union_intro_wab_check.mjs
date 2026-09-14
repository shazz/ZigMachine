// Checks the Union cracktro's WAB logo part against the ORIGINAL remake replayed
// frame by frame (union_intro_wab_ref.mjs): START, MID and FINAL of the fly-in,
// every one of its 350 frames, and that FINAL is exactly the full logo.
//
//   node apps/union_intro_wab_check.mjs <cart.wasm> [--baseline <cart.wasm>]
//   node apps/union_intro_wab_check.mjs --frames <file>   (raw 400x280 RGB part frames)
//
// Cart mode finds the part by the MID frame, then with --baseline proves the parts
// around it did not change: every frame before the WAB part is byte-identical, and
// the placement part runs identically, starting exactly 350 frames after it began.
// UNION_INTRO_SRC points at the remake (default prototypes/oldies/UnionDemoCracktro/intro).
// Exits 1 on any failure.
import { readFile } from "node:fs/promises";
import { createHash } from "node:crypto";
import { cartRam, romRam } from "../docs/wasm_hiwater.js";
import { replayWab, PLANE_W, PLANE_H, ENTRY_FRAMES, PART_FRAMES } from "./union_intro_wab_ref.mjs";

const SIZE = PLANE_W * PLANE_H * 3;
const CHECKS = { START: 20, MID: 60, FINAL: ENTRY_FRAMES - 2, "FINAL hold": ENTRY_FRAMES - 1, "fade mid": 250, "fade end": PART_FRAMES - 1 };
// Nearest sampling, 32 alpha levels, replace-not-blend on overlaps and a 255-colour
// palette keep a faithful port off the canvas on the turning tiles' edges: at worst
// mean 1.43 and 14.3% of lit pixels (frame 83). Measured controls, the same port
// one frame early or late: mean >= 2.16, >= 22.4% off; one pixel aside: >= 13.2%
// at frame 60 but >= 24.1% at 83 and 100. origin/main's port: 57-96% off.
const MAX_MEAN = 2, MAX_BAD = 0.18, BAD_DIFF = 64, LIT = 32;
const LOGO = 132, LOGO_X = 134, LOGO_Y = 74;
const TICKS = 2600, PLACEMENT_RUN = 400;
const PAGES = 112; // SHARED_PAGES in machine/sdk/memmap.zig
let failed = false;
const verdict = (ok, msg) => { console.log(`  ${ok ? "ok  " : "FAIL"} ${msg}`); if (!ok) failed = true; };

// mean |RGB diff| (0..255) and the share of lit pixels off by more than BAD_DIFF.
function diff(a, ao, b, bo) {
    let sum = 0, lit = 0, bad = 0;
    for (let i = 0; i < SIZE; i += 3) {
        let m = 0, on = false;
        for (let c = 0; c < 3; c++) {
            const x = a[ao + i + c], y = b[bo + i + c];
            sum += Math.abs(x - y); m = Math.max(m, Math.abs(x - y));
            on ||= x > LIT || y > LIT;
        }
        if (on) { lit++; if (m > BAD_DIFF) bad++; }
    }
    return { mean: sum / SIZE, bad: lit ? bad / lit : 0, lit };
}

function checkPart(ref, got, at) {
    for (const [name, n] of Object.entries(CHECKS)) {
        const d = diff(ref, n * SIZE, got, at(n));
        verdict(d.mean <= MAX_MEAN && d.bad <= MAX_BAD, `${name} (part frame ${n}): mean ${d.mean.toFixed(2)}, off ${(100 * d.bad).toFixed(1)}% of lit pixels`);
    }
    const worst = { mean: 0, meanAt: -1, bad: 0, badAt: -1 };
    for (let n = 0; n < PART_FRAMES; n++) {
        const d = diff(ref, n * SIZE, got, at(n));
        if (process.env.WAB_VERBOSE) console.log(`    frame ${n}: mean ${d.mean.toFixed(2)}, off ${(100 * d.bad).toFixed(1)}% of ${d.lit}`);
        if (d.mean > worst.mean) Object.assign(worst, { mean: d.mean, meanAt: n });
        if (d.bad > worst.bad) Object.assign(worst, { bad: d.bad, badAt: n });
    }
    verdict(worst.mean <= MAX_MEAN && worst.bad <= MAX_BAD,
        `all ${PART_FRAMES} frames: worst mean ${worst.mean.toFixed(2)} (frame ${worst.meanAt}), worst off ${(100 * worst.bad).toFixed(1)}% (frame ${worst.badAt})`);
}

// FINAL must be the assembled logo and nothing else: wab.raw through wab_pal at its place.
async function checkFullLogo(got, at) {
    const raw = await readFile(new URL("zig/assets/screens/union_intro/wab.raw", import.meta.url));
    const pal = await readFile(new URL("zig/assets/screens/union_intro/wab_pal.dat", import.meta.url));
    const want = new Uint8Array(SIZE);
    for (let y = 0; y < LOGO; y++) for (let x = 0; x < LOGO; x++) {
        const idx = raw[y * LOGO + x], d = ((LOGO_Y + y) * PLANE_W + LOGO_X + x) * 3;
        if (idx) want.set(pal.subarray(idx * 4, idx * 4 + 3), d);
    }
    for (const n of [ENTRY_FRAMES - 2, ENTRY_FRAMES - 1, ENTRY_FRAMES]) {
        let off = 0;
        for (let i = 0; i < SIZE; i++) if (want[i] !== got[at(n) + i]) off++;
        verdict(off === 0, `part frame ${n} is exactly the full logo (${off} bytes differ)`);
    }
}

async function boot(cartPath) {
    const memory = new WebAssembly.Memory({ initial: PAGES, maximum: PAGES });
    let demo;
    const machine = (await WebAssembly.instantiate(await readFile("docs/machine-video.wasm"), {
        env: { memory, hblDispatch: (id, p, l, x) => demo.hblDispatch(id, p, l, x) },
    })).instance.exports;
    const romBytes = await readFile("docs/rom.wasm");
    const rom = (await WebAssembly.instantiate(romBytes, { env: { memory, hwVideoBase: machine.hwVideoBase, hwBlit: machine.hwBlit } })).instance.exports;
    machine.hwSetRomHigh(romRam(romBytes).high ?? 0);
    const cartBytes = await readFile(cartPath);
    const env = { memory, ...rom };
    for (const k of Object.keys(machine)) if (k.startsWith("hw")) env[k] = machine[k];
    for (const imp of WebAssembly.Module.imports(new WebAssembly.Module(cartBytes)))
        if (imp.module === "env" && !(imp.name in env)) env[imp.name] = () => {};
    demo = (await WebAssembly.instantiate(cartBytes, { env })).instance.exports;
    machine.hwSetCartHigh(cartRam(cartBytes).high ?? 0);
    machine.hwInit();
    demo.boot();
    demo.skipBoot();
    return { memory, machine, demo };
}

// Runs the host loop; returns per tick a hash of every enabled plane's output, and
// hands `onRgb(t, rgb)` the 400x280 RGB composite (planes alpha-blended bottom
// first) of each tick `want(t)` asks for. The buffer is reused: copy to keep it.
async function runCart(cartPath, want, onRgb) {
    const { memory, machine, demo } = await boot(cartPath);
    const w = machine.hwPhysWidth(), h = machine.hwPhysHeight(), hashes = [], buf = new Uint8Array(SIZE);
    hashes.cost = 0; // worst demo.frame() of the ticks asked for, in ms
    for (let t = 0; t < TICKS; t++) {
        machine.hwClear();
        const t0 = performance.now();
        demo.frame(16.6);
        if (want(t)) hashes.cost = Math.max(hashes.cost, performance.now() - t0);
        const hash = createHash("sha256"), rgb = want(t) ? buf.fill(0) : null;
        for (let p = 0; p < machine.hwPlanesNumber(); p++) {
            if (!demo.isPlaneEnabled(p)) { hash.update(`off${p}`); continue; }
            machine.hwRenderPlane(p);
            const pfb = new Uint8Array(memory.buffer, machine.hwPhysicalPtr(), w * h * 4);
            hash.update(pfb);
            if (!rgb) continue;
            for (let i = 0; i < PLANE_W * PLANE_H; i++) {
                const s = (((i / PLANE_W) | 0) * w + 2 * (i % PLANE_W)) * 4, a = pfb[s + 3] / 255;
                for (let c = 0; c < 3; c++) rgb[i * 3 + c] = Math.round(pfb[s + c] * a + rgb[i * 3 + c] * (1 - a));
            }
        }
        hashes.push(hash.digest("hex"));
        if (rgb) onRgb(t, rgb);
    }
    return hashes;
}

async function checkCart(ref, cart, baseline, at) {
    // Pass 1 finds the tick closest to the MID frame (unless --at names the part's
    // first tick); pass 2 keeps the whole part.
    let best = { mean: Infinity, t: -1 };
    const hashes = await runCart(cart, (t) => at === null, (t, rgb) => {
        const d = diff(ref, CHECKS.MID * SIZE, rgb, 0);
        if (d.mean < best.mean) best = { mean: d.mean, t };
    });
    if (at === null) verdict(best.mean <= MAX_MEAN, `the original's MID frame is shown: closest at tick ${best.t}, mean ${best.mean.toFixed(2)}`);
    const start = at ?? Math.max(0, best.t - CHECKS.MID);
    console.log(`${cart}: WAB part checked from tick ${start}`);
    const frames = new Uint8Array(PART_FRAMES * SIZE);
    const part = await runCart(cart, (t) => t >= start && t < start + PART_FRAMES, (t, rgb) => frames.set(rgb, (t - start) * SIZE));
    console.log(`  worst cart update+render during the part: ${part.cost.toFixed(3)} ms`);
    checkPart(ref, frames, (n) => n * SIZE);
    await checkFullLogo(frames, (n) => n * SIZE);
    if (!baseline) return;
    const scan = { hashes }, base = { hashes: await runCart(baseline, () => false) };
    const pre = scan.hashes.slice(0, start).findIndex((hsh, t) => hsh !== base.hashes[t]);
    verdict(pre === -1, `frames 0..${start - 1} (depack + TRSI) identical to the baseline${pre === -1 ? "" : `: first differs at ${pre}`}`);
    const placement = start + PART_FRAMES, from = base.hashes.indexOf(scan.hashes[placement], start);
    let run = 0;
    while (from >= 0 && run < PLACEMENT_RUN && scan.hashes[placement + run] === base.hashes[from + run]) run++;
    verdict(run === PLACEMENT_RUN && scan.hashes[placement - 1] !== base.hashes[from - 1],
        `placement starts at tick ${placement} = WAB start + ${PART_FRAMES}; it ran from ${from} in the baseline (shift ${from - placement}); ${run}/${PLACEMENT_RUN} frames identical`);
}

const args = process.argv.slice(2);
const introDir = process.env.UNION_INTRO_SRC ?? "prototypes/oldies/UnionDemoCracktro/intro";
const { frames: ref } = await replayWab(introDir);
if (args[0] === "--frames") {
    const got = await readFile(args[1]);
    verdict(got.length === PART_FRAMES * SIZE, `${args[1]}: ${got.length / SIZE} frames, the original shows ${PART_FRAMES}`);
    checkPart(ref, got, (n) => n * SIZE);
    await checkFullLogo(got, (n) => n * SIZE);
} else {
    const b = args.indexOf("--baseline"), a = args.indexOf("--at");
    await checkCart(ref, args[0], b >= 0 ? args[b + 1] : null, a >= 0 ? Number(args[a + 1]) : null);
}
console.log(failed ? "=> FAIL" : "=> PASS");
process.exit(failed ? 1 : 0);
