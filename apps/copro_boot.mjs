// COPRO's harness boot (apps/copro_check.mjs, apps/copro_astro_check.mjs): the cart over the real machine +
// ROM, the loader's OWN hostBardJob / bardJobFrame lifted from docs/sealed-loader.js, hwAstro counted.
//   brk "stale": the page says done without serving; "answer": a served job's output spoiled.
import { readFile } from "node:fs/promises";
import { cartRam, romRam } from "../docs/wasm_hiwater.js";

const PAGES = 128, W = 320, REG_FB_BASE = 0x44;

/** The loader's BARD jobs functions, over the cart `box.demo`; `log` records every call and serve. */
async function loaderJobs(box, log, brk) {
    const src = await readFile("docs/sealed-loader.js", "utf8");
    const fn = (name) => {
        const m = src.match(new RegExp(`^function ${name}\\([^)]*\\) \\{[\\s\\S]*?^\\}\\n`, "m"));
        if (!m) throw new Error(`docs/sealed-loader.js has no function ${name}`);
        return m[0];
    };
    let body = fn("hostBardJob") + fn("bardJobFrame");
    if (brk === "stale") body = body.replace("if (op === 3) { demo.bardJobServe(); return 1; }", "if (op === 3) return 1;")
        .replace("if (jobCart) demo.bardJobServe();", "");
    const demo = { bardJobServe: () => serve(box, log, brk) };
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
function serve(box, log, brk) {
    const u = new Uint32Array(box.memory.buffer), b = log.block >>> 2;
    const slot = (t) => b + 8 + 16 * (t & 7);
    const before = [...Array(8).keys()].map((i) => u[b + 8 + 16 * i + 2]);
    box.demo.bardJobServe();
    for (let i = 0; i < 8; i++) {
        const s = b + 8 + 16 * i;
        if (u[s + 2] === before[i] || u[s + 2] !== u[s + 1]) continue;
        log.served++;
        if (brk === "answer") spoil(u, u.subarray(slot(u[s + 1]), slot(u[s + 1]) + 16));
    }
}

// One word of the job's output: zx0 a shown pixel (row 12), xform/particles point 0, crc32 chunk 0.
function spoil(u, j) {
    const a = j.subarray(6);
    const at = { 1: a[2] + 12 * W + 100, 2: a[5], 3: a[4], 4: a[3] }[j[0]];
    if (at !== undefined) u[at >>> 2] = j[0] === 1 ? u[at >>> 2] ^ 0x01010101 : j[0] === 4 ? u[at >>> 2] ^ 1 : 5 * W + 5;
}

export async function boot(switches, brk = null, astro = null) {
    const memory = new WebAssembly.Memory({ initial: PAGES, maximum: PAGES });
    const box = { memory, demo: null }, log = { calls: [], served: 0, block: 0 };
    const machine = (await WebAssembly.instantiate(await readFile("docs/machine-video.wasm"), {
        env: { memory, hblDispatch: (id, p, l, x) => box.demo.hblDispatch(id, p, l, x) },
    })).instance.exports;
    const romBytes = await readFile("docs/rom.wasm");
    const rom = (await WebAssembly.instantiate(romBytes, { env: { memory, hwVideoBase: machine.hwVideoBase, hwBlit: machine.hwBlit } })).instance.exports;
    machine.hwSetRomHigh(romRam(romBytes).high ?? 0);
    const cartBytes = await readFile("docs/demo-copro.wasm");
    const jobs = await loaderJobs(box, log, brk);
    const env = { memory, ...rom, hostBardJob: jobs.hostBardJob };
    for (const k of Object.keys(machine)) if (k.startsWith("hw")) env[k] = machine[k];
    log.astro = 0; // hwAstro calls; `astro(desc, count, memory, machine)` stands in for the machine's when given
    env.hwAstro = (desc, n) => { log.astro++; return astro ? astro(desc, n, memory, machine) : machine.hwAstro(desc, n); };
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

