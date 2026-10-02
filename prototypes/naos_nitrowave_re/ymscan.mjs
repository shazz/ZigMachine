// ymscan.mjs RIP.sndh SUB DIR... -- log the rip on the sealed YM, then every
// SNDH subtune under DIR (non-~a), and rank them by the tone-period histogram
// overlap (order-free, ymcmp.py's second number). Run from the repo root.
import { readFile, readdir, stat } from "node:fs/promises";
import { join } from "node:path";

const FRAMES = 600;
const [rip, ripSub, ...dirs] = process.argv.slice(2);
const machineBin = await readFile("docs/machine-audio.wasm");
const demoBin = await readFile("docs/demo-audio.wasm");

async function log(path, sub) {
    const memory = new WebAssembly.Memory({ initial: 48, maximum: 48 });
    const machine = (await WebAssembly.instantiate(machineBin, { env: { memory } })).instance.exports;
    const env = { memory };
    for (const name of Object.keys(machine)) if (name.startsWith("machine")) env[name] = machine[name];
    const demo = (await WebAssembly.instantiate(demoBin, { env })).instance.exports;
    demo.audioInit();
    const tune = new Uint8Array(await readFile(path));
    if (tune.length > 900000) return null;
    new Uint8Array(memory.buffer, demo.audioSongPtr(), tune.length).set(tune);
    if (!demo.audioLoadSndh(tune.length)) return null;
    demo.audioSndhPlay(sub);
    const regs = new Uint8Array(memory.buffer, machine.audioYmRegsPtr(), 16);
    const hist = new Map();
    for (let f = 0; f < FRAMES; f++) {
        demo.audioRender(882);
        for (let c = 0; c < 3; c++) {
            if (!(regs[8 + c] & 31)) continue;
            const p = regs[2 * c] | ((regs[2 * c + 1] & 15) << 8);
            if (p) hist.set(p, (hist.get(p) || 0) + 1);
        }
    }
    return hist;
}

function overlap(a, b) {
    let inter = 0, na = 0, nb = 0;
    for (const v of a.values()) na += v;
    for (const v of b.values()) nb += v;
    for (const [k, v] of a) inter += Math.min(v, b.get(k) || 0);
    return inter / Math.max(1, na, nb);
}

async function* walk(d) {
    for (const e of await readdir(d)) {
        const p = join(d, e);
        if ((await stat(p)).isDirectory()) yield* walk(p);
        else if (p.endsWith(".sndh")) yield p;
    }
}

function header(buf) {
    const s = Buffer.from(buf.subarray(0, 400)).toString("latin1");
    const n = /##(\d\d)/.exec(s);
    const flag = /FLAG([~a-z]*)/.exec(s);
    return { subs: n ? Number(n[1]) : 1, flag: flag ? flag[1] : "" };
}

const ref = await log(rip, Number(ripSub));
const out = [];
for (const d of dirs) {
    for await (const p of walk(d)) {
        const h = header(await readFile(p));
        if (h.flag.includes("a")) continue;
        for (let s = 1; s <= Math.min(h.subs, 20); s++) {
            const hist = await log(p, s).catch(() => null);
            if (hist) out.push([overlap(ref, hist), p, s]);
        }
    }
}
out.sort((x, y) => y[0] - x[0]);
for (const [o, p, s] of out.slice(0, 8)) console.log(o.toFixed(3), p, "#" + s);
