// ASTRO BENCH (site/carts/demo-c-astro_bench.wasm, SPIKE: docs/hardware/studies/ARM_FPU_COPROC.md): ASTROLABE through the
// machine's hwAstro, as site/js/sealed-loader.js binds it, checked against the cart's own maths and JS's.
//
//   1. the real clock: every job runs once and logs once, no "ZM ASTRO FAIL", every ulp = 0 (the
//      machine's kernels and the cart's f64 are both IEEE + compiler_rt), LINPACK's two solutions are
//      the same bits, served = 0 (no ARM here), the timings are printed (a browser's, NOT the board's);
//   2. the reference bits against JavaScript: IEEE ops (1/3, sqrt 2, fma) exact, libm within 1 ulp;
//   3. no clock (hostMicros = 0): "-" for every time, the checks still pass;
//   4. key 1 reruns, the screen shows text.
//
//   5. the zoom's third side (SPACE twice): ZIGGY's f32 on the FPU. Its pictures at the shallow steps 0 and 8
//      are the f64 pictures (<= 1 % of the cells differ), at a deep step they are NOT (>= 50 % differ: f32's
//      7 digits run out past the step the cart logs as "f32 break="), which documents why f64 / ASTROLABE exist.
//
//   node apps/harness/astro_bench_headless.mjs [--break result|batch|clock|f32|f32match]
// --break proves the checks bite: hwAstro's first result off by one ulp; array descriptors answered OK
// with nothing computed; a no-clock run the harness is told to expect numbers from; f32: the "deep" step
// is a shallow one (f32 looks fine there, so the degradation check must fail); f32match: the "shallow"
// step is the deep one (the f32 picture is garbage there, so the match check must fail).
import { readFile, writeFile } from "node:fs/promises";
import { cartRam, romRam } from "../../site/js/wasm_hiwater.js";

const PAGES = 128, OFF_VRAM = 0x1100, W = 320, H = 200, PAPER = 1, KEY_1 = 0x31;
const brk = process.argv.includes("--break") ? process.argv[process.argv.indexOf("--break") + 1] : null;
const errors = [];
const check = (ok, m) => { if (!ok) { errors.push(m); console.log(`  FAIL ${m}`); } };
const JOBS = ["roundtrip", "add", "mul", "div", "sqrt", "sin", "linpack", "sin4096", "ref"];

// hwAstro as the machine serves it, or broken for --break
function astro(machine, memory) {
    return (desc, count) => {
        const dv = new DataView(memory.buffer);
        if (brk === "batch" && dv.getUint32(desc, true) >= 0x20) return 0; // "OK", nothing computed
        const st = machine.hwAstro(desc, count);
        if (brk === "result") dv.setUint32(desc + 64, dv.getUint32(desc + 64, true) ^ 1, true);
        return st;
    };
}

async function boot(clock, bytes) {
    const memory = new WebAssembly.Memory({ initial: PAGES, maximum: PAGES });
    let demo;
    const machine = (await WebAssembly.instantiate(await readFile("site/machine-video.wasm"), {
        env: { memory, hblDispatch: (id, p, l, x) => demo.hblDispatch(id, p, l, x) },
    })).instance.exports;
    const romBytes = await readFile("site/rom.wasm");
    const rom = (await WebAssembly.instantiate(romBytes, { env: { memory, hwVideoBase: machine.hwVideoBase, hwBlit: machine.hwBlit } })).instance.exports;
    machine.hwSetRomHigh(romRam(romBytes).high ?? 0);
    const log = [];
    const env = { memory, ...rom, hostMicros: clock, consoleLogJS: (p, n) => log.push(Buffer.from(memory.buffer, p, n).toString("latin1")) };
    for (const k of Object.keys(machine)) if (k.startsWith("hw")) env[k] = machine[k];
    env.hwAstro = astro(machine, memory);
    for (const imp of WebAssembly.Module.imports(new WebAssembly.Module(bytes)))
        if (imp.module === "env" && !(imp.name in env)) env[imp.name] = () => {};
    demo = (await WebAssembly.instantiate(bytes, { env })).instance.exports;
    machine.hwSetCartHigh(cartRam(bytes).high ?? 0);
    machine.hwInit(); demo.boot(); demo.skipBoot();
    return { memory, machine, demo, log };
}

function runToDone(m, nth = 1) {
    for (let f = 0; f < 200; f++) {
        m.machine.hwClear(); m.demo.frame(16.6);
        if (m.log.filter((l) => l.startsWith("ZM ASTRO done")).length >= nth) return f + 1;
    }
    return 0;
}

const lines = (log, job) => log.filter((l) => l.startsWith(`ZM ASTRO ${job}`) && (job !== "sin" || !l.startsWith("ZM ASTRO sin4096")));
const field = (l, k) => new RegExp(`\\b${k}=(\\S+)`).exec(l ?? "")?.[1];

function common(m, what) {
    for (const j of JOBS) check(lines(m.log, j).length === 1, `${what}: ${j} logged ${lines(m.log, j).length} times, want once`);
    for (const l of m.log.filter((x) => x.startsWith("ZM ASTRO FAIL"))) check(false, `${what}: ${l}`);
    for (const j of ["add", "mul", "div", "sqrt", "sin", "sin4096"]) check(field(lines(m.log, j)[0], "ulp") === "0", `${what}: ${j} ulp = ${field(lines(m.log, j)[0], "ulp")}`);
    check(/ same$/.test(lines(m.log, "linpack")[0] ?? ""), `${what}: LINPACK's two solutions differ`);
    const done = m.log.find((l) => l.startsWith("ZM ASTRO done")) ?? "";
    check(field(done, "failures") === "0", `${what}: ${done}`);
    check(/served=0\//.test(done), `${what}: an ARM served a call in the browser: ${done}`);
}

// the reference bits: sin(0.5), 1/3, sqrt(2), exp(1), pow(2, 0.5), atan2(1, -1), fma((1+2^-30)^2 - 1 - 2^-29)
function reference(m) {
    const bits = (lines(m.log, "ref")[0] ?? "").split(" ").slice(3).map((h) => BigInt(`0x${h}`));
    const f64 = (x) => new BigInt64Array(new Float64Array([x]).buffer)[0];
    const want = [Math.sin(0.5), 1 / 3, Math.SQRT2, Math.exp(1), Math.pow(2, 0.5), Math.atan2(1, -1), 2 ** -60];
    const exact = [false, true, true, false, false, false, true];
    want.forEach((w, i) => {
        const d = bits[i] === undefined ? 99n : bits[i] - f64(w);
        const ulp = d < 0n ? -d : d;
        check(exact[i] ? ulp === 0n : ulp <= 1n, `reference ${i}: ${ulp} ulp from JavaScript's ${w}`);
    });
}

async function realClockRun(bytes) {
    const m = await boot(() => Math.floor(performance.now() * 1000) >>> 0, bytes);
    const frames = runToDone(m);
    check(frames === JOBS.length, `real clock: done after ${frames} frames, want ${JOBS.length} (a job a frame)`);
    common(m, "real clock");
    reference(m);
    console.log("  results (a browser's timings, ns per op, NOT the board's):");
    for (const l of m.log) console.log(`    ${l}`);
    check(Number(field(lines(m.log, "add")[0], "soft64")) >= 0, "real clock: no soft64 time");
    return m;
}

async function rerunAndScreen(m) {
    m.demo.key(KEY_1);
    check(runToDone(m, 2) > 0, "key 1: the rerun never finished");
    check(lines(m.log, "linpack").length === 2, "key 1: LINPACK not logged once more");
    m.machine.hwRenderPlane(0);
    const fb = new Uint8Array(m.memory.buffer, m.machine.hwVideoBase() + OFF_VRAM, W * H);
    let ink = 0; for (const p of fb) if (p !== PAPER) ink++;
    check(ink > 400, `the screen shows results: only ${ink} non-paper pixels`);
}

async function noClockRun(bytes) {
    const m = await boot(() => 0, bytes);
    check(runToDone(m) > 0, "no clock: never finished");
    common(m, "no clock");
    const add = lines(m.log, "add")[0];
    if (brk === "clock") check(/^\d+$/.test(field(add, "soft64") ?? ""), `no clock: expected numbers, got ${add}`);
    else check(field(add, "soft64") === "-" && field(lines(m.log, "linpack")[0], "soft") === "-", `no clock: a time was logged: ${add}`);
}

// page 2: the Julia zoom. The same pixels from ASTROLABE and from ZIGGY's soft f64 (the hash of every 8th
// step's escape events), a picture of many colours, and a readout; --shots DIR writes RGBA dumps of both pages.
const SHOTS = process.argv.includes("--shots") ? process.argv[process.argv.indexOf("--shots") + 1] : null;
async function shot(m, name) {
    m.machine.hwRenderPlane(0);
    const base = m.machine.hwVideoBase(), mem = new Uint8Array(m.memory.buffer);
    const out = Buffer.alloc(W * H * 4);
    for (let i = 0; i < W * H; i++) out.set(mem.subarray(base + 0x100 + mem[base + OFF_VRAM + i] * 4, base + 0x100 + mem[base + OFF_VRAM + i] * 4 + 4), i * 4);
    await writeFile(`${SHOTS}/${name}.rgba`, out);
}
const ZCELLS = 80 * 40, ZROWS = W * 160, F32_DEEP = brk === "f32" ? 8 : 296;
const pic = (m) => Buffer.from(new Uint8Array(m.memory.buffer, m.machine.hwVideoBase() + OFF_VRAM, ZROWS));
// the share of the 80 x 40 cells (4 x 4 px) whose colour differs: the top-left pixel of each stands for it
const differ = (a, b) => { let d = 0; for (let y = 0; y < 160; y += 4) for (let x = 0; x < W; x += 4) if (a[y * W + x] !== b[y * W + x]) d++; return d / ZCELLS; };
const hashes = (m, side) => Object.fromEntries(m.log.filter((l) => l.startsWith("ZM ASTRO zoom") && l.includes(`side=${side}`)).map((l) => [field(l, "step"), field(l, "hash")]));
function frames(m, until, max) { for (let f = 0; f < max && !until(); f++) { m.machine.hwClear(); m.demo.frame(16.6); } return until(); }

// run frames; keep a copy of the picture on the frame a side logs each wanted step (the log comes at the end of a picture)
function capture(m, side, steps, max) {
    const got = {}, from = m.log.length; // only this run's log lines: an earlier run left the same steps in it
    for (let f = 0; f < max && Object.keys(got).length < steps.length; f++) {
        m.machine.hwClear(); m.demo.frame(16.6);
        const h = hashes({ log: m.log.slice(from) }, side);
        for (const k of steps) if (got[k] === undefined && h[k] !== undefined) got[k] = pic(m);
    }
    return got;
}

// SPACE twice from ASTROLABE: f32 on the FPU against ASTROLABE's f64 at steps 0, 8 and a deep one
async function f32Run(m, steps) {
    const f64 = capture(m, "astro", steps, 400);
    m.demo.key(0x32), m.demo.key(0x20), m.demo.key(0x20);
    const brkLine = m.log.filter((l) => l.startsWith("ZM ASTRO f32 break=")).pop();
    const N = Number(field(brkLine, "break"));
    check(N > 8 && N < F32_DEEP + 100, `f32: the cart's break step ${N} is not between the shallow steps and the deep one`);
    const f32 = capture(m, "f32", steps, 12 * (F32_DEEP + 8));
    for (const k of steps) check(f32[k] !== undefined && f64[k] !== undefined, `f32: no picture at step ${k}`);
    const sh = brk === "f32match" ? F32_DEEP : 8;
    const d0 = differ(f32[0], f64[0]), d8 = differ(f32[8], f64[8]), dd = differ(f32[F32_DEEP], f64[F32_DEEP]);
    check(d0 <= 0.01 && differ(f32[sh], f64[sh]) <= 0.01, `f32: shallow pictures differ from f64's (step 0: ${d0}, step ${sh}: ${differ(f32[sh], f64[sh])})`);
    check(dd >= 0.5, `f32: deep step ${F32_DEEP} differs in only ${(dd * 100).toFixed(1)} % of the cells: f32 should have broken down`);
    check(new Set(f32[F32_DEEP]).size < new Set(f64[F32_DEEP]).size, "f32: the deep picture has no fewer colours than f64's: it should have collapsed to blocks");
    console.log(`  f32 FPU: cart says precision runs out past step ${N}; vs f64 ${(d0 * 100).toFixed(1)} % of cells differ at step 0, ${(d8 * 100).toFixed(1)} % at 8, ${(dd * 100).toFixed(1)} % at ${F32_DEEP}`);
    if (SHOTS) {
        const dump = async (name, p) => { const out = Buffer.alloc(W * H * 4), mem = new Uint8Array(m.memory.buffer), b = m.machine.hwVideoBase();
            for (let i = 0; i < ZROWS; i++) out.set(mem.subarray(b + 0x100 + p[i] * 4, b + 0x100 + p[i] * 4 + 4), i * 4); await writeFile(`${SHOTS}/${name}.rgba`, out); };
        m.demo.key(0x32), m.demo.key(0x20); // restart, soft f64 from step 0
        const soft = capture(m, "ziggy", steps, 12 * (F32_DEEP + 8));
        for (const k of steps.slice(2)) await dump(`step${k}_astro`, f64[k]), await dump(`step${k}_f32`, f32[k]), await dump(`step${k}_ziggy`, soft[k]);
    }
}

async function zoomRun(bytes) {
    const m = await boot(() => Math.floor(performance.now() * 1000) >>> 0, bytes);
    if (SHOTS) { runToDone(m); await shot(m, "bench"); }
    m.demo.key(0x32); // 2
    check(frames(m, () => hashes(m, "astro")[16], 60), "zoom: ASTROLABE never reached step 16");
    if (SHOTS) await shot(m, "zoom_astro");
    const a = hashes(m, "astro");
    m.machine.hwRenderPlane(0);
    const fb = new Uint8Array(m.memory.buffer, m.machine.hwVideoBase() + OFF_VRAM, W * 160);
    check(new Set(fb).size >= 8, `zoom: only ${new Set(fb).size} colours in the picture`);
    if (SHOTS) { frames(m, () => hashes(m, "astro")[200], 400); m.demo.frame(16.6); await shot(m, "zoom_deep"); }
    m.demo.key(0x32), m.demo.key(0x20); // restart at step 0, then SPACE: ZIGGY's soft f64
    check(frames(m, () => hashes(m, "ziggy")[16], 600), "zoom: ZIGGY's side never reached step 16");
    if (SHOTS) await shot(m, "zoom_ziggy");
    const z = hashes(m, "ziggy");
    for (const k of ["0", "8", "16"]) check(a[k] !== undefined && a[k] === z[k], `zoom step ${k}: ASTROLABE ${a[k]} != ZIGGY ${z[k]}`);
    console.log(`  zoom: steps 0/8/16 the same pixels both ways (hash ${a[0]} ${a[8]} ${a[16]})`);
    m.demo.key(0x32); // from step 0 again
    await f32Run(m, [0, 8, ...(SHOTS ? [232] : []), F32_DEEP]);
}

const bytes = new Uint8Array(await readFile("site/carts/demo-c-astro_bench.wasm"));
console.log("astro_bench_headless:");
if (brk !== "clock") await rerunAndScreen(await realClockRun(bytes));
await noClockRun(bytes);
await zoomRun(bytes);
if (brk) {
    const ok = errors.length > 0;
    console.log(ok ? `\nastro_bench_headless: PASS (--break ${brk} was caught: ${errors.length} failures)` : `\nastro_bench_headless: FAILED — --break ${brk} was not caught`);
    process.exit(ok ? 0 : 1);
}
console.log(errors.length ? `\nastro_bench_headless: ${errors.length} FAILED` : "\nastro_bench_headless: PASS");
process.exit(errors.length ? 1 : 0);
