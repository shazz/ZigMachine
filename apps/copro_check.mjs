// COPRO (cart 130, apps/zig/scenes/copro.zig): BARD as a coprocessor (zg.bard.job, system table 1.24),
// on the page. The cart boots over the real machine + ROM with the loader's OWN hostBardJob / bardJobFrame
// (docs/sealed-loader.js, lifted from its source as apps/bard_queue_lib.mjs lifts bardDrain), and:
//   same      each page draws the same pixels (rows 0..175, the effect), frame for frame, with its jobs on
//             ZIGGY (switch 4: the cart serves them inside its frame) and on the coprocessor (the page
//             serves them after the cart's frame, or when the cart waits)
//   served    on the coprocessor every job the cart posted was answered by the page's server, and the cart
//             never gave up on it (no hostBardJob(OPEN, 0), the fallback to ZIGGY); on ZIGGY none was kicked
//   picture   page 1's first slide is the TEX NEO SHOW's dragon, rows 12..187, index for index (the ZX0 job)
//   crc       page 4's first frame: cell k is colour 16 + (zlib's crc32 of chunk k) & 15, for the 64 KB buffer the
//             cart fills with hash(i, 0xC2C) words (the crc32 job against Node's zlib)
//   node apps/copro_check.mjs [--break answer | --break stale]
//     answer: the page's server answers, then a word of each job's output is changed (a coprocessor whose
//             kernel differs from ZIGGY's): every "same" check must fail (then exit 0)
//     stale:  the page says a job is done without serving it: the cart falls back to ZIGGY, so its pixels
//             still agree, and every "served" check must fail (then exit 0)
import { readFile } from "node:fs/promises";
import { crc32 } from "node:zlib";
import { cartRam, romRam } from "../docs/wasm_hiwater.js";

const PAGES = 128, W = 320, ROWS = 176, REG_FB_BASE = 0x44, SHADE = 16;
const BRK = process.argv.includes("--break") ? process.argv[process.argv.indexOf("--break") + 1] : null;
if (BRK !== null && BRK !== "answer" && BRK !== "stale") throw new Error(`--break answer | stale, not ${BRK}`);
const fails = { same: 0, served: 0, other: 0 };
const ok = (kind, c, m) => {
    console.log(`  ${c ? "ok  " : "FAIL"} ${m}`);
    if (!c) fails[kind]++;
};

/** The loader's BARD jobs functions, over the cart `box.demo`; `log` records every call and serve. */
async function loaderJobs(box, log) {
    const src = await readFile("docs/sealed-loader.js", "utf8");
    const fn = (name) => {
        const m = src.match(new RegExp(`^function ${name}\\([^)]*\\) \\{[\\s\\S]*?^\\}\\n`, "m"));
        if (!m) throw new Error(`docs/sealed-loader.js has no function ${name}`);
        return m[0];
    };
    let body = fn("hostBardJob") + fn("bardJobFrame");
    if (BRK === "stale") body = body.replace("if (op === 3) { demo.bardJobServe(); return 1; }", "if (op === 3) return 1;")
        .replace("if (jobCart) demo.bardJobServe();", "");
    const demo = { bardJobServe: () => serve(box, log) };
    const f = new Function("demo", `let jobCart = false; ${body}; return { hostBardJob, bardJobFrame };`)(demo);
    return {
        hostBardJob: (op, arg) => {
            log.calls.push([op, arg >>> 0]);
            if (op === 0 && arg) log.block = arg >>> 0;
            return f.hostBardJob(op, arg);
        },
        bardJobFrame: f.bardJobFrame,
    };
}

/** The cart's server, counting the jobs it answers (--break answer: then spoils one word of each). */
function serve(box, log) {
    const u = new Uint32Array(box.memory.buffer), b = log.block >>> 2;
    const slot = (t) => b + 8 + 16 * (t & 7);
    const before = [...Array(8).keys()].map((i) => u[b + 8 + 16 * i + 2]);
    box.demo.bardJobServe();
    for (let i = 0; i < 8; i++) {
        const s = b + 8 + 16 * i;
        if (u[s + 2] === before[i] || u[s + 2] !== u[s + 1]) continue;
        log.served++;
        if (BRK === "answer") spoil(u, u.subarray(slot(u[s + 1]), slot(u[s + 1]) + 16));
    }
}

// One word of the job's output: zx0 a shown pixel (row 12), xform/particles point 0, crc32 chunk 0.
function spoil(u, j) {
    const a = j.subarray(6);
    const at = { 1: a[2] + 12 * W + 100, 2: a[5], 3: a[4], 4: a[3] }[j[0]];
    if (at !== undefined) u[at >>> 2] = j[0] === 1 ? u[at >>> 2] ^ 0x01010101 : j[0] === 4 ? u[at >>> 2] ^ 1 : 5 * W + 5;
}

async function boot(switches) {
    const memory = new WebAssembly.Memory({ initial: PAGES, maximum: PAGES });
    const box = { memory, demo: null }, log = { calls: [], served: 0, block: 0 };
    const machine = (await WebAssembly.instantiate(await readFile("docs/machine-video.wasm"), {
        env: { memory, hblDispatch: (id, p, l, x) => box.demo.hblDispatch(id, p, l, x) },
    })).instance.exports;
    const romBytes = await readFile("docs/rom.wasm");
    const rom = (await WebAssembly.instantiate(romBytes, { env: { memory, hwVideoBase: machine.hwVideoBase, hwBlit: machine.hwBlit } })).instance.exports;
    machine.hwSetRomHigh(romRam(romBytes).high ?? 0);
    const cartBytes = await readFile("docs/demo-copro.wasm");
    const jobs = await loaderJobs(box, log);
    const env = { memory, ...rom, hostBardJob: jobs.hostBardJob };
    for (const k of Object.keys(machine)) if (k.startsWith("hw")) env[k] = machine[k];
    for (const imp of WebAssembly.Module.imports(new WebAssembly.Module(cartBytes)))
        if (imp.module === "env" && !(imp.name in env)) env[imp.name] = () => 0; // hostMicros: no clock
    box.demo = (await WebAssembly.instantiate(cartBytes, { env })).instance.exports;
    machine.hwSetCartHigh(cartRam(cartBytes).high ?? 0);
    machine.hwInit();
    box.demo.boot();
    box.demo.skipBoot();
    for (const s of switches) box.demo.setShadeMode(s);
    const frame = () => { box.demo.frame(16.6); jobs.bardJobFrame(); };
    const plane = () => {
        const base = machine.hwVideoBase();
        const off = new DataView(memory.buffer).getUint32(base + REG_FB_BASE, true);
        return new Uint8Array(memory.buffer, base + off, W * 200).slice();
    };
    return { box, log, frame, plane };
}

const eq = (a, b) => { for (let i = 0; i < W * ROWS; i++) if (a[i] !== b[i]) return false; return true; };
const NAMES = ["ZX0 DEPACK", "3D MORPH", "PARTICLES", "CRC-32"];
const FRAMES = [320, 120, 120, 90]; // page 1: two swaps (150 frames a picture)

console.log("copro");
for (let p = 0; p < 4; p++) {
    const z = await boot([4, p]), c = await boot([p]);
    let same = true, at = -1;
    for (let f = 0; f < FRAMES[p] && same; f++) {
        z.frame();
        c.frame();
        if (!eq(z.plane(), c.plane())) { same = false; at = f; }
    }
    ok("same", same, `${NAMES[p]}: ZIGGY alone and the coprocessor draw the same picture for ${FRAMES[p]} frames${same ? "" : ` (differ at frame ${at})`}`);
    const posted = new Uint32Array(c.box.memory.buffer)[(c.log.block >>> 2) + 2];
    const gaveUp = c.log.calls.some(([op, arg]) => op === 0 && arg === 0);
    ok("served", posted > 0 && c.log.served === posted && !gaveUp,
        `${NAMES[p]}: the page served all ${posted} jobs the cart posted (${c.log.served}), the cart kept the coprocessor (${gaveUp ? "fell back to ZIGGY" : "no fallback"})`);
    const toZiggy = z.log.calls.findLastIndex(([op, arg]) => op === 0 && arg === 0); // the switch (init opened the coprocessor)
    ok("other", toZiggy >= 0 && z.log.calls.length === toZiggy + 1,
        `${NAMES[p]}: on ZIGGY no job was kicked to the page after the switch`);
}

{   // page 1's first picture, after one frame
    const c = await boot([0]);
    c.frame();
    const want = (await readFile("apps/zig/assets/screens/tex_neoshow/dragon.raw")).subarray(12 * W, (12 + ROWS) * W);
    ok("other", eq(c.plane(), want), "ZX0 DEPACK: the first slide is dragon.raw rows 12..187, index for index");
}
{   // page 4's cells on its first frame, against zlib
    const c = await boot([3]);
    c.frame();
    const buf = Buffer.alloc(64 * 1024);
    for (let i = 0; i < buf.length / 4; i++) buf.writeUInt32LE(hash(i, 0xC2C), 4 * i);
    const px = c.plane();
    let bad = 0;
    for (let k = 0; k < 256; k++) {
        const want = SHADE + (crc32(buf.subarray(256 * k, 256 * (k + 1))) & 15);
        if (px[Math.floor(k / 32) * 22 * W + (k % 32) * 10] !== want) bad++;
    }
    ok("other", bad === 0, `CRC-32: all 256 cells are zlib's crc32 of their chunk (${bad} differ)`);
}

/** libs/zig/bard_jobs/kernels.zig hash. */
function hash(i, frame) {
    let h = (Math.imul(i, 0x9E3779B1) ^ Math.imul(frame, 0x85EBCA77)) >>> 0;
    h = (h ^ (h >>> 15)) >>> 0;
    h = Math.imul(h, 0x2C1B3C6D) >>> 0;
    h = (h ^ (h >>> 12)) >>> 0;
    h = Math.imul(h, 0x297A2D39) >>> 0;
    return (h ^ (h >>> 15)) >>> 0;
}

if (BRK === "answer") {
    console.log(fails.same === 4 ? "copro: --break answer caught (every page's A/B differs)" : `copro: --break answer NOT caught (${fails.same} of 4)`);
    process.exit(fails.same === 4 ? 0 : 1);
}
if (BRK === "stale") {
    console.log(fails.served === 4 ? "copro: --break stale caught (every page fell back)" : `copro: --break stale NOT caught (${fails.served} of 4)`);
    process.exit(fails.served === 4 ? 0 : 1);
}
const n = fails.same + fails.served + fails.other;
console.log(n ? `copro: ${n} FAILED` : "copro: all ok");
process.exit(n ? 1 : 0);
