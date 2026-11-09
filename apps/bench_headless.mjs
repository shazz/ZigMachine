// BENCH (docs/demo-c-bench.wasm): the Hatari benchmark suite as a cart. Runs it to completion in the wasm host,
// the way docs/sealed-loader.js loads a cart, and checks what the cart claims:
//
//   1. a deterministic clock (every hostMicros call advances 100 ms): the slice arithmetic gives exact rates, and
//      CoreMark's CRCs, Dhrystone's final values, Whetstone's checksum and LINPACK's residual all pass;
//   2. the host's real clock: same checks, and the timings are printed (a browser's, NOT the board's);
//   3. no clock (hostMicros answers 0): every rate reads "no clock", no number, the checks still pass;
//   4. key 1 reruns and every result is logged once per run, the screen shows text.
//
//   node apps/bench_headless.mjs [--break crc|dhry|resid|clock]
// --break proves the checks bite: a corrupted CoreMark CRC table, a corrupted Dhrystone value, a corrupted
// LINPACK solution, and a run with no clock that the harness is told to expect numbers from.
import { readFile } from "node:fs/promises";
import { cartRam, romRam } from "../docs/wasm_hiwater.js";

const PAGES = 128, OFF_VRAM = 0x1100, W = 320, H = 200, PAPER = 1, KEY_1 = 0x31;
const brk = process.argv.includes("--break") ? process.argv[process.argv.indexOf("--break") + 1] : null;
const errors = [];
const fail = (m) => { errors.push(m); console.log(`  FAIL ${m}`); };
const check = (ok, m) => { if (!ok) fail(m); };
const JOBS = ["coremark", "dhrystone", "whetstone_double", "whetstone_single", "linpack_double", "linpack_single", "mem"];

// A cart with CoreMark's known-CRC table corrupted (core_main.c list_known_crc[3] = 0xe714, the value the
// "2K performance run" is compared against).
function corruptCrc(bytes) {
    const pat = [0xb0, 0xd4, 0x40, 0x33, 0x79, 0x6a, 0x14, 0xe7, 0xc1, 0xe3];
    const at = [];
    for (let i = 0; i + pat.length <= bytes.length; i++) if (pat.every((b, j) => bytes[i + j] === b)) at.push(i);
    if (at.length !== 1) throw new Error(`CoreMark's CRC table found ${at.length} times, want 1`);
    const out = new Uint8Array(bytes); out[at[0] + 6] ^= 0x01; // list_known_crc[3], the 2K performance run's
    return out;
}

async function boot(clock, cartBytes) {
    const memory = new WebAssembly.Memory({ initial: PAGES, maximum: PAGES });
    let demo;
    const machine = (await WebAssembly.instantiate(await readFile("docs/machine-video.wasm"), {
        env: { memory, hblDispatch: (id, p, l, x) => demo.hblDispatch(id, p, l, x) },
    })).instance.exports;
    const romBytes = await readFile("docs/rom.wasm");
    const rom = (await WebAssembly.instantiate(romBytes, { env: { memory, hwVideoBase: machine.hwVideoBase, hwBlit: machine.hwBlit } })).instance.exports;
    machine.hwSetRomHigh(romRam(romBytes).high ?? 0);
    const log = [];
    const env = { memory, ...rom, hostMicros: clock,
        consoleLogJS: (p, n) => log.push(Buffer.from(memory.buffer, p, n).toString("latin1")) };
    for (const k of Object.keys(machine)) if (k.startsWith("hw")) env[k] = machine[k];
    for (const imp of WebAssembly.Module.imports(new WebAssembly.Module(cartBytes)))
        if (imp.module === "env" && !(imp.name in env)) env[imp.name] = () => {};
    demo = (await WebAssembly.instantiate(cartBytes, { env })).instance.exports;
    machine.hwSetCartHigh(cartRam(cartBytes).high ?? 0);
    machine.hwInit(); demo.boot(); demo.skipBoot();
    return { memory, machine, demo, log };
}

// Frames until the cart logs "ZM BENCH done" (the nth time), or give up.
function runToDone(m, nth = 1) {
    let frames = 0, seen = 0, t0 = performance.now();
    for (; frames < 400000; frames++) {
        m.machine.hwClear(); m.demo.frame(16.6);
        if (m.log.filter((l) => l === "ZM BENCH done").length >= nth) return { frames, ms: performance.now() - t0 };
        if (performance.now() - t0 > 120000) break;
    }
    return { frames, ms: performance.now() - t0, timeout: true };
}

const parse = (log) => {
    const out = {};
    for (const l of log) { const m = /^ZM BENCH ([\w]+)=(.*)$/.exec(l); if (m) (out[m[1]] ??= []).push(m[2]); }
    return out;
};
const num = (s) => Number(/^[\d.]+/.exec(s)?.[0] ?? NaN);

function checks(r, what) {
    for (const j of JOBS) {
        const c = r[`${j}_check`];
        check(c?.length === 1, `${what}: ${j}_check logged ${c?.length ?? 0} times, want once`);
        check(c?.[0]?.startsWith("ok"), `${what}: ${j}_check = ${c?.[0]}`);
    }
}

async function fakeClockRun(bytes) {
    let t = 1000;
    const m = await boot(() => (t = (t + 100000) >>> 0), bytes);
    m.demo.benchSetTargetUs(50000);
    if (brk === "dhry") m.demo.benchBreak(1);
    if (brk === "resid") m.demo.benchBreak(2);
    const { frames, timeout } = runToDone(m);
    check(!timeout, "fake clock: never finished");
    const r = parse(m.log);
    console.log(`  fake clock: done in ${frames} frames`);
    checks(r, "fake clock");
    // one slice a job, 100 ms a timed pair: the arithmetic is exact
    const exact = { coremark: "10.00", dhrystone: "1.13", whetstone_double: "1.00", whetstone_single: "1.00", linpack_double: "3433.33", linpack_single: "3433.33" };
    for (const [k, v] of Object.entries(exact)) check(r[k]?.[0]?.startsWith(v + " "), `fake clock: ${k} = ${r[k]?.[0]}, want ${v}`);
    check(r.mem_write_4k?.[0]?.startsWith("0.31 "), `fake clock: mem_write_4k = ${r.mem_write_4k?.[0]}, want 0.31`);
    return m;
}

async function realClockRun(bytes) {
    const m = await boot(() => Math.floor(performance.now() * 1000) >>> 0, bytes);
    m.demo.benchSetTargetUs(150000);
    const { frames, ms, timeout } = runToDone(m);
    check(!timeout, "real clock: never finished");
    const r = parse(m.log);
    console.log(`  real clock: done in ${frames} frames, ${(ms / 1000).toFixed(1)} s`);
    checks(r, "real clock");
    console.log("  results (a browser's timings, NOT the board's):");
    for (const l of m.log.filter((x) => x.startsWith("ZM BENCH") && !x.includes("_check") && !x.includes("_chk"))) console.log(`    ${l}`);
    for (const k of ["coremark", "dhrystone", "whetstone_double", "whetstone_single", "linpack_double", "linpack_single", "mem_write_4k", "mem_memcpy_256k"])
        check(num(r[k]?.[0]) > 0, `real clock: ${k} = ${r[k]?.[0]}`);
    // the LOOP=1 checksums are fixed by the source and the libm: pinned (x1000)
    check(Math.abs(num(r.whetstone_double_chk?.[0]) - PIN.whet_d) < 0.001, `whetstone_double_chk ${r.whetstone_double_chk?.[0]}, pinned ${PIN.whet_d}`);
    check(Math.abs(num(r.whetstone_single_chk?.[0]) - PIN.whet_f) < 0.001, `whetstone_single_chk ${r.whetstone_single_chk?.[0]}, pinned ${PIN.whet_f}`);
    return m;
}

async function rerunAndScreen(m) {
    const before = m.log.filter((l) => l.startsWith("ZM BENCH coremark=")).length;
    m.demo.benchSetTargetUs(20000);
    m.demo.key(KEY_1);
    const { timeout } = runToDone(m, 2);
    check(!timeout, "key 1: the rerun never finished");
    const after = m.log.filter((l) => l.startsWith("ZM BENCH coremark=")).length;
    check(after === before + 1, `key 1: coremark logged ${after - before} times by the rerun, want once`);
    m.machine.hwRenderPlane(0);
    const fb = new Uint8Array(m.memory.buffer, m.machine.hwVideoBase() + OFF_VRAM, W * H);
    let ink = 0; for (const p of fb) if (p !== PAPER) ink++;
    check(ink > 400, `the screen shows results: only ${ink} non-paper pixels`);
}

async function noClockRun(bytes) {
    const m = await boot(() => 0, bytes);
    m.demo.benchSetTargetUs(50000);
    const { timeout } = runToDone(m);
    check(!timeout, "no clock: never finished");
    const r = parse(m.log);
    checks(r, "no clock");
    for (const j of JOBS) {
        if (brk === "clock") check(num(r[j]?.[0]) > 0, `no clock: ${j} should have printed a number, printed ${r[j]?.[0]}`);
        else check(r[j]?.[0] === "no clock", `no clock: ${j} = ${r[j]?.[0]}, want "no clock"`);
    }
    check(!m.log.some((l) => / (MWIPS|KFLOPS|DMIPS|CoreMark|MB\/s)$/.test(l)), "no clock: a rate was logged");
    console.log("  no clock: every rate reads \"no clock\"");
}

const PIN = { whet_d: 7.62, whet_f: 7.62 };
let bytes = new Uint8Array(await readFile("docs/demo-c-bench.wasm"));
if (brk === "crc") bytes = corruptCrc(bytes);
console.log("bench_headless:");
await fakeClockRun(bytes);
if (!brk || brk === "none") { const m = await realClockRun(bytes); await rerunAndScreen(m); }
await noClockRun(bytes);
if (brk) {
    const ok = errors.length > 0;
    console.log(ok ? `\nbench_headless: PASS (--break ${brk} was caught: ${errors.length} failures)` : `\nbench_headless: FAILED — --break ${brk} was not caught`);
    process.exit(ok ? 0 : 1);
}
console.log(errors.length ? `\nbench_headless: ${errors.length} FAILED` : "\nbench_headless: PASS");
process.exit(errors.length ? 1 : 0);
