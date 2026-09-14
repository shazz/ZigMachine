// Checks the Union cracktro's WAB logo part. Cart-only, always: the assembled logo
// is EXACTLY wab.raw at its place on part frames 110..151 and on no other frame,
// which also locates the part. Against the ORIGINAL remake replayed frame by frame
// (union_intro_wab_ref.mjs), when it is present: START, MID, FINAL, all 350 frames.
//
//   node apps/union_intro_wab_check.mjs <cart.wasm> [--baseline <cart.wasm>] [--at <tick>]
//   node apps/union_intro_wab_check.mjs --frames <file>   (raw 400x280 RGB part frames)
//
// --baseline proves the parts around it did not change: every frame before the WAB
// part is byte-identical, and placement runs identically, starting exactly 350
// frames after the part began. --at names the part's first tick (for a cart that
// never shows the logo). prototypes/ is not in git: the remake is UNION_INTRO_SRC,
// or REMAKE under this checkout or the main one; without it the comparison is
// SKIPPED, said so, and the cart-only checks still run. Exits 1 on any failure.
import { readFile } from "node:fs/promises";
import { existsSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { dirname, join } from "node:path";
import { createHash } from "node:crypto";
import { cartRam, romRam } from "../docs/wasm_hiwater.js";
import { replayWab, PLANE_W, PLANE_H, ENTRY_FRAMES, PART_FRAMES } from "./union_intro_wab_ref.mjs";

const REMAKE = "prototypes/oldies/UnionDemoCracktro/intro";
const SIZE = PLANE_W * PLANE_H * 3;
const CHECKS = { START: 20, MID: 60, FINAL: ENTRY_FRAMES - 2, "FINAL hold": ENTRY_FRAMES - 1, "fade mid": 250, "fade end": PART_FRAMES - 1 };
// Nearest sampling, 32 alpha levels, replace-not-blend on overlaps and a 255-colour
// palette keep a faithful port off the canvas on the turning tiles' edges: at worst
// mean 1.43 and 14.3% of lit pixels (frame 83). Measured controls, the same port
// one frame early or late: mean >= 2.16, >= 22.4% off; one pixel aside: >= 13.2%
// at frame 60 but >= 24.1% at 83 and 100. The old (pre-fix) port: 57-96% off.
const MAX_MEAN = 2, MAX_BAD = 0.18, BAD_DIFF = 64, LIT = 32;
// Every tile is at rest from vbl 110 (ENDVBL); the fade's first two frames are at
// alpha 1 (the second's 1.005 is ignored); its third, 1.005 - 0.005, truncates below.
const LOGO_FROM = 110, LOGO_TO = ENTRY_FRAMES + 1;
const LOGO = 132, LOGO_X = 134, LOGO_Y = 74;
const PAGES = 112; // SHARED_PAGES in machine/sdk/memmap.zig
let failed = false;
const verdict = (ok, msg) => { console.log(`  ${ok ? "ok  " : "FAIL"} ${msg}`); if (!ok) failed = true; };

function findRemake() {
    const has = (d) => existsSync(`${d}/eflogowabentry.js`);
    if (process.env.UNION_INTRO_SRC) return has(process.env.UNION_INTRO_SRC) ? process.env.UNION_INTRO_SRC : null;
    const roots = [process.cwd()];
    try {
        const common = execFileSync("git", ["rev-parse", "--path-format=absolute", "--git-common-dir"], { stdio: ["ignore", "pipe", "ignore"] });
        roots.push(dirname(common.toString().trim()));
    } catch { /* not a git checkout: cwd only */ }
    return roots.map((r) => join(r, REMAKE)).find(has) ?? null;
}

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

function checkPart(ref, got) {
    for (const [name, n] of Object.entries(CHECKS)) {
        const d = diff(ref, n * SIZE, got, n * SIZE);
        verdict(d.mean <= MAX_MEAN && d.bad <= MAX_BAD, `${name} (part frame ${n}): mean ${d.mean.toFixed(2)}, off ${(100 * d.bad).toFixed(1)}% of lit pixels`);
    }
    const worst = { mean: 0, meanAt: -1, bad: 0, badAt: -1 };
    for (let n = 0; n < PART_FRAMES; n++) {
        const d = diff(ref, n * SIZE, got, n * SIZE);
        if (d.mean > worst.mean) Object.assign(worst, { mean: d.mean, meanAt: n });
        if (d.bad > worst.bad) Object.assign(worst, { bad: d.bad, badAt: n });
    }
    verdict(worst.mean <= MAX_MEAN && worst.bad <= MAX_BAD,
        `all ${PART_FRAMES} frames: worst mean ${worst.mean.toFixed(2)} (frame ${worst.meanAt}), worst off ${(100 * worst.bad).toFixed(1)}% (frame ${worst.badAt})`);
}

// The assembled logo and nothing else: wab.raw through wab_pal at its place, on black.
async function logoFrame() {
    const raw = await readFile(new URL("zig/assets/screens/union_intro/wab.raw", import.meta.url));
    const pal = await readFile(new URL("zig/assets/screens/union_intro/wab_pal.dat", import.meta.url));
    const want = Buffer.alloc(SIZE);
    for (let y = 0; y < LOGO; y++) for (let x = 0; x < LOGO; x++) {
        const idx = raw[y * LOGO + x];
        if (idx) want.set(pal.subarray(idx * 4, idx * 4 + 3), ((LOGO_Y + y) * PLANE_W + LOGO_X + x) * 3);
    }
    return want;
}

// `exact` (ascending ticks or part frames showing the logo) must be first..first+42.
function checkLogoRun(exact, first) {
    const n = LOGO_TO - LOGO_FROM + 1;
    const ok = exact.length === n && exact[0] === first + LOGO_FROM && exact[n - 1] === first + LOGO_TO;
    verdict(ok, `exactly the full logo on part frames ${LOGO_FROM}..${LOGO_TO} only: ${exact.length} frames, ${exact.length ? `${exact[0] - first}..${exact[exact.length - 1] - first}` : "none"}`);
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

// The host loop for `ticks`; returns per tick a hash of every enabled plane's output
// (with .cost, the worst demo.frame() in ms of the ticks `want` names), and hands
// `onRgb(t, rgb)` the 400x280 composite of those ticks, in a reused buffer.
async function runCart(cartPath, ticks, want, onRgb) {
    const { memory, machine, demo } = await boot(cartPath);
    const w = machine.hwPhysWidth(), h = machine.hwPhysHeight(), hashes = [], buf = Buffer.alloc(SIZE);
    hashes.cost = 0;
    for (let t = 0; t < ticks; t++) {
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
    const want = await logoFrame(), exact = [], ticks = baseline ? 2600 : 1400;
    const hashes = await runCart(cart, ticks, () => true, (t, rgb) => { if (rgb.equals(want)) exact.push(t); });
    const start = at ?? (exact.length ? exact[0] - LOGO_FROM : null);
    if (start === null) return verdict(false, `${cart}: the full logo is never shown exactly, so the WAB part cannot be located (try --at)`);
    console.log(`${cart}: WAB part from tick ${start}`);
    checkLogoRun(exact, start);
    const frames = Buffer.alloc(PART_FRAMES * SIZE);
    const part = await runCart(cart, start + PART_FRAMES, (t) => t >= start, (t, rgb) => frames.set(rgb, (t - start) * SIZE));
    console.log(`  worst cart update+render during the part: ${part.cost.toFixed(3)} ms`);
    if (ref) checkPart(ref, frames);
    if (!baseline) return;
    const base = await runCart(baseline, ticks, () => false);
    const pre = hashes.slice(0, start).findIndex((hsh, t) => hsh !== base[t]);
    verdict(pre === -1, `frames 0..${start - 1} (depack + TRSI) identical to the baseline${pre === -1 ? "" : `: first differs at ${pre}`}`);
    const placement = start + PART_FRAMES, from = base.indexOf(hashes[placement], start);
    let run = 0;
    while (from >= 0 && run < 400 && hashes[placement + run] === base[from + run]) run++;
    verdict(run === 400 && hashes[placement - 1] !== base[from - 1],
        `placement starts at tick ${placement} = WAB start + ${PART_FRAMES}; it ran from ${from} in the baseline (shift ${from - placement}); ${run}/400 frames identical`);
}

const args = process.argv.slice(2);
const remake = findRemake();
const ref = remake ? (await replayWab(remake)).frames : null;
if (!remake) console.log(`  SKIPPED the comparison with the original: no remake at ${REMAKE} (set UNION_INTRO_SRC); cart-only checks follow`);
if (args[0] === "--frames") {
    const got = await readFile(args[1]), exact = [], want = await logoFrame();
    verdict(got.length === PART_FRAMES * SIZE, `${args[1]}: ${got.length / SIZE} frames, the original shows ${PART_FRAMES}`);
    for (let n = 0; n * SIZE < got.length; n++) if (want.equals(got.subarray(n * SIZE, (n + 1) * SIZE))) exact.push(n);
    checkLogoRun(exact, 0);
    if (ref) checkPart(ref, got);
} else {
    const b = args.indexOf("--baseline"), a = args.indexOf("--at");
    await checkCart(ref, args[0] ?? "docs/demo-union_intro.wasm", b >= 0 ? args[b + 1] : null, a >= 0 ? Number(args[a + 1]) : null);
}
console.log(failed ? "=> FAIL" : "=> PASS");
process.exit(failed ? 1 : 0);
