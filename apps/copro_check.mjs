// COPRO (cart 130, apps/zig/scenes/copro.zig): BARD as a coprocessor (zg.bard.job, system table 1.24),
// on the page. The cart boots over the real machine + ROM with the loader's OWN hostBardJob / bardJobFrame
// (docs/sealed-loader.js, lifted from its source as apps/bard_queue_lib.mjs lifts bardDrain), and:
//   same      each page draws the same pixels (rows 0..175, the effect), frame for frame, with its jobs on
//             ZIGGY (switch 6: the cart serves them inside its frame) and on the coprocessor (the page
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
import { boot as bootWith } from "./copro_boot.mjs";

const W = 320, ROWS = 176, SHADE = 16;
const boot = (switches) => bootWith(switches, BRK);
const BRK = process.argv.includes("--break") ? process.argv[process.argv.indexOf("--break") + 1] : null;
if (BRK !== null && BRK !== "answer" && BRK !== "stale") throw new Error(`--break answer | stale, not ${BRK}`);
const fails = { same: 0, served: 0, other: 0 };
const ok = (kind, c, m) => {
    console.log(`  ${c ? "ok  " : "FAIL"} ${m}`);
    if (!c) fails[kind]++;
};

const eq = (a, b) => { for (let i = 0; i < W * ROWS; i++) if (a[i] !== b[i]) return false; return true; };
const NAMES = ["ZX0 DEPACK", "3D MORPH", "PARTICLES", "CRC-32"];
const FRAMES = [320, 120, 120, 90]; // page 1: two swaps (150 frames a picture)

console.log("copro");
for (let p = 0; p < 4; p++) {
    const z = await boot([6, p]), c = await boot([p]);
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
