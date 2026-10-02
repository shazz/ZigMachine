// ymsearch.mjs TARGET.ym FRAMES [DIR] -- find a tune in the SNDH archive by its YM registers.
// TARGET is a 14-byte-a-frame log (the original's, e.g. from the Musashi oracle). Every
// subtune of every SNDH under DIR (default prototypes/sndh_lf) plays FRAMES frames on the
// sealed YM (docs/*-audio.wasm, as ymlog.mjs) and is scored by the overlap of its tone-period
// histogram with the target's (order-free, so lag and speed do not matter); the best 15 are
// printed. Confirm a candidate with ymlog.mjs + ymcmp.py. Run from the repo root.
import { readFile, readdir } from "node:fs/promises";
import { join } from "node:path";

const [target, nframes, dir = "/home/matt/projects/ZigMachine/prototypes/sndh_lf"] = process.argv.slice(2);
const N = Number(nframes);
const memory = new WebAssembly.Memory({ initial: 48, maximum: 48 });
const machine = (await WebAssembly.instantiate(await readFile("docs/machine-audio.wasm"), { env: { memory } })).instance.exports;
const env = { memory };
for (const name of Object.keys(machine)) if (name.startsWith("machine")) env[name] = machine[name];
const demo = (await WebAssembly.instantiate(await readFile("docs/demo-audio.wasm"), { env })).instance.exports;
demo.audioInit();
const regs = new Uint8Array(memory.buffer, machine.audioYmRegsPtr(), 16);

function hist(frames) {
    const h = new Map();
    for (const f of frames) for (let c = 0; c < 3; c++) {
        if (!(f[8 + c] & 31)) continue;
        const p = f[2 * c] | ((f[2 * c + 1] & 15) << 8);
        h.set(p, (h.get(p) || 0) + 1);
    }
    return h;
}
function overlap(a, b) {
    let s = 0, na = 0, nb = 0;
    for (const v of a.values()) na += v;
    for (const v of b.values()) nb += v;
    for (const [p, v] of a) s += Math.min(v / na, (b.get(p) || 0) / nb);
    return s;
}
const t = await readFile(target);
const want = [];
for (let i = 0; i + 14 <= Math.min(t.length, N * 14); i += 14) want.push(t.subarray(i, i + 14));
const wh = hist(want);

async function* files(d) {
    for (const e of await readdir(d, { withFileTypes: true })) {
        const p = join(d, e.name);
        if (e.isDirectory()) yield* files(p);
        else if (e.name.toLowerCase().endsWith(".sndh")) yield p;
    }
}
const best = [];
for await (const path of files(dir)) {
    const tune = new Uint8Array(await readFile(path));
    if (tune.length > 900000 || tune[0] === 0x49) continue; // ICE-packed: the loader unpacks? skip
    const subs = Number((new TextDecoder("latin1").decode(tune.subarray(0, 512)).match(/##(\d\d)/) || [0, 1])[1]) || 1;
    for (let s = 1; s <= Math.min(subs, 40); s++) {
        new Uint8Array(memory.buffer, demo.audioSongPtr(), tune.length).set(tune);
        if (!demo.audioLoadSndh(tune.length)) break;
        demo.audioSndhPlay(s);
        const got = [];
        for (let f = 0; f < N; f++) { demo.audioRender(882); got.push(regs.slice(0, 14)); }
        const sc = overlap(wh, hist(got));
        best.push([sc, path.slice(dir.length + 1), s]);
        best.sort((a, b) => b[0] - a[0]);
        best.length = Math.min(best.length, 15);
    }
}
for (const [sc, p, s] of best) console.log(sc.toFixed(3), p, `#${s}`);
