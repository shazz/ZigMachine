// The blitter's QUEUE (HW 1.8.0, memmap BLIT_CMD_QUEUE), driven straight through the sealed
// machine: a descriptor list must draw exactly what its ops draw one by one, leave the
// register block as it was, and sum their CYCLES. Two machines side by side: one runs the
// list (COMMAND 5), the other replays it as a cart would without the queue (each descriptor's
// words stored into the block, hwBlit, the block put back at the end). Then the edges: an
// empty list or one past the ring's end is refused, a list cut short ends before the cut
// descriptor, COMMAND 0 only sets words, and a QUEUE inside a list is an unknown op.
//
// Usage: node apps/blitter_queue_check.mjs        (exit 1 on any failure)
import { readFile } from "node:fs/promises";

const PAGES = 128, VIDEO = 0x400000, OFF_BLIT = 0x80, P0 = 0x1100, STRIDE = 320;
const RING = VIDEO + 0x1dc000, RING_WORDS = 512, Q = VIDEO + OFF_BLIT + 0x68, CYCLES = VIDEO + OFF_BLIT + 0x60;
const FILL = 2, BLIT = 1, LINE = 3, TRI = 4, QUEUE = 5;
const wasm = await readFile(process.env.MACHINE || "docs/machine-video.wasm");

async function machine() {
    const memory = new WebAssembly.Memory({ initial: PAGES, maximum: PAGES });
    const hw = (await WebAssembly.instantiate(wasm, { env: { memory, hblDispatch: () => {} } })).instance.exports;
    hw.hwInit();
    const dv = () => new DataView(memory.buffer), u8 = () => new Uint8Array(memory.buffer);
    let s = 7;
    for (let i = 0; i < 3 * 64000; i++) u8()[VIDEO + P0 + i] = (s = (s * 1103515245 + 12345) >>> 0) >>> 24;
    const word = (k) => dv().getUint32(VIDEO + OFF_BLIT + 4 * k, true);
    const setWord = (k, v) => k === 0 ? (u8()[VIDEO + OFF_BLIT + 1] = v >>> 8, u8()[VIDEO + OFF_BLIT + 2] = v >>> 16)
        : dv().setUint32(VIDEO + OFF_BLIT + 4 * k, v, true);
    const run = (cmd) => { u8()[VIDEO + OFF_BLIT] = cmd; hw.hwBlit(); return dv().getUint32(CYCLES, true); };
    const block = () => u8().slice(VIDEO + OFF_BLIT, VIDEO + OFF_BLIT + 0x60);
    const planes = () => u8().slice(VIDEO + P0, VIDEO + P0 + 3 * 64000);
    return { dv, u8, word, setWord, run, block, planes };
}

// Descriptors as [cmd, {k: value}]: register words by index (0: MINTERM << 8 | CON << 16).
const xy = (x, y) => ((x & 0xffff) | (y & 0xffff) << 16) >>> 0;
function ops(seed) {
    let s = seed;
    const r = (n) => (s = (s * 1103515245 + 12345) >>> 0) % n;
    const list = [[0, { 0: 0xcc00, 8: P0, 9: STRIDE }]];
    for (let i = 0; i < 60; i++) {
        const c = [FILL, BLIT, LINE, TRI][r(4)], w = {};
        if (r(3) === 0) w[1] = r(256) | r(2) << 25;              // COLOR (+ CON2.FILL_MT now and then)
        if (r(4) === 0) w[0] = [0xcc00, 0x6600, 0xee00, 0xcc00 | 0x80 << 16][r(4)]; // MINTERM, CON.CLIP_EN
        if (r(5) === 0) w[8] = P0 + 64000 * r(3);
        if (c === BLIT) w[2] = P0 + 64000 * r(3) + r(5000), w[3] = STRIDE; // A_BASE: set, unused by D = B
        if (c === BLIT) w[4] = P0 + r(60000), w[5] = STRIDE, w[0] = 0xcc00 | 0x02 << 16;
        if (c === FILL || c === BLIT) w[10] = xy(1 + r(40), 1 + r(30));
        w[11] = xy(r(340) - 10, r(220) - 10);
        if (c === LINE || c === TRI) w[12] = xy(r(340) - 10, r(220) - 10);
        if (c === TRI) w[13] = xy(r(340) - 10, r(220) - 10);
        if (r(9) === 0) w[14] = xy(r(100), r(80)), w[15] = xy(40 + r(200), 30 + r(120));
        list.push([r(15) === 0 ? 0 : c, w]);
    }
    return list;
}

function encode(list) {
    const out = [];
    for (const [cmd, w] of list) {
        const ks = Object.keys(w).map(Number).sort((a, b) => a - b);
        out.push((ks.reduce((m, k) => m | 1 << k, 0) | cmd << 24) >>> 0, ...ks.map((k) => w[k] >>> 0));
    }
    return out;
}

function kick(m, words, start, count = words.length) {
    words.forEach((v, i) => m.dv().setUint32(RING + 4 * (start + i), v, true));
    m.dv().setUint16(Q, start, true);
    m.dv().setUint16(Q + 2, count, true);
    return m.run(QUEUE);
}

// The list one op at a time, as the cart would store it; the block put back at the end.
function replay(m, list) {
    const saved = m.block();
    let sum = 0;
    for (const [cmd, w] of list) {
        for (const k of Object.keys(w)) m.setWord(Number(k), w[k] >>> 0);
        if (cmd) sum = (sum + m.run(cmd)) >>> 0;
    }
    m.u8().set(saved, VIDEO + OFF_BLIT);
    return sum;
}

let failed = 0;
const same = (a, b) => a.length === b.length && a.every((v, i) => v === b[i]);
async function check(name, fn) {
    let why;
    try { why = await fn(); } catch (e) { why = `threw ${e}`; }
    console.log(`${why ? "FAIL" : "ok  "}  ${name}${why ? ": " + why : ""}`);
    if (why) failed++;
}

for (const seed of [1, 2, 3]) {
    await check(`a list of 60 ops draws what they draw one by one (seed ${seed})`, async () => {
        const a = await machine(), b = await machine(), list = ops(seed), before = a.block();
        a.u8()[VIDEO + OFF_BLIT] = QUEUE;
        const got = kick(a, encode(list), seed * 7);
        const want = replay(b, list);
        if (!same(a.planes(), b.planes())) return "the planes differ";
        before[0] = QUEUE;
        if (!same(a.block(), before)) return "the register block was changed";
        return got === want && got > 0 ? null : `CYCLES ${got}, the ops' sum is ${want}`;
    });
}

const fill = (x, y, w, h, color) => [FILL, { 1: color, 10: xy(w, h), 11: xy(x, y) }];
const prelude = [0, { 0: 0xcc00, 8: P0, 9: STRIDE }];
async function edge(list, start, count) {
    const m = await machine(), before = m.planes();
    m.dv().setUint32(CYCLES, 77, true);
    const cyc = kick(m, encode(list), start, count);
    return { m, cyc, drew: !same(m.planes(), before) };
}
await check("an empty list is refused: CYCLES 0", async () => {
    const { cyc, drew } = await edge([prelude, fill(0, 0, 8, 8, 1)], 0, 0);
    return cyc === 0 && !drew ? null : `CYCLES ${cyc}, drew ${drew}`;
});
await check("a list past the ring's end is refused", async () => {
    const { cyc, drew } = await edge([prelude, fill(0, 0, 8, 8, 1)], RING_WORDS - 3, 7);
    return cyc === 0 && !drew ? null : `CYCLES ${cyc}, drew ${drew}`;
});
await check("a list ending on the ring's last word runs", async () => {
    const words = encode([prelude, fill(0, 0, 8, 8, 1)]);
    const { cyc } = await edge([prelude, fill(0, 0, 8, 8, 1)], RING_WORDS - words.length, words.length);
    return cyc === 64 ? null : `CYCLES ${cyc}`;
});
await check("a list cut short ends before the cut descriptor", async () => {
    const list = [prelude, fill(0, 0, 8, 8, 1), fill(20, 0, 4, 4, 2)];
    const { cyc } = await edge(list, 0, encode(list).length - 1);
    return cyc === 64 ? null : `CYCLES ${cyc} (the first fill alone is 64)`;
});
await check("COMMAND 0 only sets words, and they stay for the next op", async () => {
    const { m, cyc } = await edge([prelude, [0, { 1: 9, 10: xy(3, 2) }], [FILL, { 11: xy(5, 5) }]], 0, undefined);
    const px = m.u8()[VIDEO + P0 + 5 * STRIDE + 5];
    return cyc === 6 && px === 9 ? null : `CYCLES ${cyc}, pixel ${px}`;
});
await check("a queued op below OFF_VRAM (the palettes) is refused: no draw, no cost", async () => {
    const m = await machine(), pal = m.u8().slice(VIDEO + 0x100, VIDEO + 0x1100);
    const cyc = kick(m, encode([[0, { 0: 0xcc00, 8: 0x100, 9: STRIDE }], fill(0, 0, 8, 8, 3)]), 0);
    return cyc === 0 && same(m.u8().slice(VIDEO + 0x100, VIDEO + 0x1100), pal) ? null : `CYCLES ${cyc}`;
});
await check("a QUEUE inside a list is an unknown op: no draw, no cost", async () => {
    const { cyc, drew } = await edge([prelude, [QUEUE, { 1: 3, 10: xy(8, 8), 11: xy(0, 0) }]], 0, undefined);
    return cyc === 0 && !drew ? null : `CYCLES ${cyc}, drew ${drew}`;
});

if (failed) {
    console.log(`blitter QUEUE: ${failed} check(s) failed`);
    process.exit(1);
}
console.log("blitter QUEUE: a list draws what its ops draw, and the edges hold ✅");
