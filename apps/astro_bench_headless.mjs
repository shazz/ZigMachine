// ASTRO BENCH (docs/demo-c-astro_bench.wasm, SPIKE: docs/ARM_FPU_COPROC.md): ASTROLABE through the
// machine's hwAstro, as docs/sealed-loader.js binds it, checked against the cart's own maths and JS's.
//
//   1. the real clock: every job runs once and logs once, no "ZM ASTRO FAIL", every ulp = 0 (the
//      machine's kernels and the cart's f64 are both IEEE + compiler_rt), LINPACK's two solutions are
//      the same bits, served = 0 (no ARM here), the timings are printed (a browser's, NOT the board's);
//   2. the reference bits against JavaScript: IEEE ops (1/3, sqrt 2, fma) exact, libm within 1 ulp;
//   3. no clock (hostMicros = 0): "-" for every time, the checks still pass;
//   4. key 1 reruns, the screen shows text.
//
//   node apps/astro_bench_headless.mjs [--break result|batch|clock]
// --break proves the checks bite: hwAstro's first result off by one ulp; array descriptors answered OK
// with nothing computed; a no-clock run the harness is told to expect numbers from.
import { readFile } from "node:fs/promises";
import { cartRam, romRam } from "../docs/wasm_hiwater.js";

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
    const machine = (await WebAssembly.instantiate(await readFile("docs/machine-video.wasm"), {
        env: { memory, hblDispatch: (id, p, l, x) => demo.hblDispatch(id, p, l, x) },
    })).instance.exports;
    const romBytes = await readFile("docs/rom.wasm");
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

const bytes = new Uint8Array(await readFile("docs/demo-c-astro_bench.wasm"));
console.log("astro_bench_headless:");
if (brk !== "clock") await rerunAndScreen(await realClockRun(bytes));
await noClockRun(bytes);
if (brk) {
    const ok = errors.length > 0;
    console.log(ok ? `\nastro_bench_headless: PASS (--break ${brk} was caught: ${errors.length} failures)` : `\nastro_bench_headless: FAILED — --break ${brk} was not caught`);
    process.exit(ok ? 0 : 1);
}
console.log(errors.length ? `\nastro_bench_headless: ${errors.length} FAILED` : "\nastro_bench_headless: PASS");
process.exit(errors.length ? 1 : 0);
