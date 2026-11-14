// COPRO's ASTROLABE pages (cart 130, apps/zig/scenes/copro/deepzoom.zig, cloth.zig): f64 batches on env.hwAstro,
// or the cart's own soft f64 (copro/soft64.zig) for the A/B. The cart boots as apps/copro_check.mjs boots it
// (apps/copro_boot.mjs: the real machine, whose hwAstro is the page's ASTROLABE), and:
//   same      page 5 (zoom) and 6 (cloth) draw the same pixels, frame for frame, on ZIGGY's soft f64 (switch 6)
//             and on hwAstro: the cart's kernels are the machine's, op for op, bit for bit
//   calls     on the coprocessor every frame is one hwAstro call; on ZIGGY none
//   fallback  a board without the ARM (hwAstro answers from ZIGGY's soft f64, W_CYCLES set, SERVED_ARM clear):
//             the same pixels, and the HUD names it (SOFT), unlike the page (HOST) and the ARM (ARM)
//   zoom      level 0's escaped cells (after 30 iterations) are those JavaScript's own doubles give, colour for
//             colour: the same seven ops, the same integer escape test on the bits
//   moves     the cloth's picture changes from frame to frame
//   node apps/copro_astro_check.mjs [--break astro]
//     astro: hwAstro answers, then one element of the batch's last output is doubled (an ASTROLABE whose answer
//            is not the soft f64's): both "same" checks must fail (then exit 0)
import { boot } from "./copro_boot.mjs";

const W = 320, ROWS = 176, SHADE = 16, DESC = 80;
const BRK = process.argv.includes("--break") ? process.argv[process.argv.indexOf("--break") + 1] : null;
if (BRK !== null && BRK !== "astro") throw new Error(`--break astro, not ${BRK}`);
const fails = { same: 0, other: 0 };
const ok = (kind, c, m) => { console.log(`  ${c ? "ok  " : "FAIL"} ${m}`); if (!c) fails[kind]++; };
const eq = (a, b, from = 0, to = ROWS) => { for (let i = from * W; i < to * W; i++) if (a[i] !== b[i]) return false; return true; };

/** hwAstro as a board would answer: the machine's code, then `post` over each descriptor's words. */
const answering = (post) => (desc, n, memory, machine) => {
    const st = machine.hwAstro(desc, n);
    for (let i = 0; i < n; i++) post(new Uint32Array(memory.buffer, desc + DESC * i, 20), memory);
    return st;
};
const SOFT = answering((d) => { d[9] = 777; }); // W_CYCLES: the board's fallback counted ZIGGY's cycles
const ARM = answering((d) => { d[8] |= 1 << 8; d[9] = 99; }); // SERVED_ARM
const SPOIL = (desc, n, memory, machine) => { // --break astro: the last output's middle element doubled
    const st = machine.hwAstro(desc, n);
    const d = new Uint32Array(memory.buffer, desc + DESC * (n - 1), 20);
    const out = new Float64Array(memory.buffer, d[6], d[1]);
    out[d[1] >> 1] *= 2;
    return st;
};

console.log("copro astro");
for (const [p, name, frames] of [[4, "F64 ZOOM", 120], [5, "F64 CLOTH", 90]]) {
    const z = await boot([6, p]), c = await boot([p], null, BRK === "astro" ? SPOIL : null);
    const soft = await boot([p], null, SOFT), arm = await boot([p], null, ARM);
    let same = true, fell = true, at = -1, moves = 0, prev = null;
    for (let f = 0; f < frames; f++) {
        for (const r of [z, c, soft, arm]) r.frame();
        const pz = z.plane(), pc = c.plane();
        if (same && !eq(pz, pc)) { same = false; at = f; }
        if (!eq(pc, soft.plane()) || !eq(pc, arm.plane())) fell = false;
        if (prev && !eq(prev, pc)) moves++;
        prev = pc;
    }
    ok("same", same, `${name}: ZIGGY's soft f64 and ASTROLABE draw the same picture for ${frames} frames${same ? "" : ` (differ at frame ${at})`}`);
    ok("other", c.log.astro >= frames && z.log.astro === 0, `${name}: ${c.log.astro} hwAstro calls on the coprocessor, ${z.log.astro} on ZIGGY`);
    const hud = (r) => r.plane().subarray(184 * W, 192 * W);
    ok("other", fell && !eq(hud(c), hud(soft), 0, 8) && !eq(hud(soft), hud(arm), 0, 8) && !eq(hud(c), hud(arm), 0, 8),
        `${name}: a board without the ARM (SOFT) and with it (ARM) draw the page's pixels; the HUD names each side`);
    ok("other", moves >= frames / 2, `${name}: the picture moves (${moves} of ${frames} frames changed)`);
}

{   // level 0 of the zoom against JavaScript's doubles: 15 frames = 30 iterations
    const c = await boot([4]);
    for (let f = 0; f < 15; f++) c.frame();
    const px = c.plane(), want = zoomOracle(30);
    let bad = 0;
    for (let i = 0; i < 64 * 35; i++) if (px[Math.floor(i / 64) * 5 * W + (i % 64) * 5] !== want[i]) bad++;
    ok("other", bad === 0, `F64 ZOOM: level 0's 2240 cells after 30 iterations are JavaScript's (${bad} differ)`);
}

/** deepzoom.zig level 0 in JavaScript doubles: the colour index each cell holds after `iters` iterations. */
function zoomOracle(iters) {
    const P = 64 * 35, dx = 3.0 / 64.0, x0 = -0.743643887037151 - dx * 32.0, y0 = 0.131825904205330 - dx * 17.0;
    const zr = new Float64Array(P), zi = new Float64Array(P), cr = new Float64Array(P), ci = new Float64Array(P);
    const bits = (a, i) => new Uint32Array(a.buffer, 8 * i + 4, 1)[0];
    const out = new Uint8Array(P);
    for (let i = 0; i < P; i++) { cr[i] = x0 + dx * (i % 64); ci[i] = y0 + dx * Math.floor(i / 64); }
    for (let it = 2; it <= iters; it += 2) {
        for (let k = 0; k < 2; k++) for (let i = 0; i < P; i++) {
            const t0 = zr[i] * zr[i], t1 = zi[i] * zi[i], t2 = zr[i] * zi[i];
            zr[i] = (t0 + -1.0 * t1) + cr[i];
            zi[i] = (t2 + t2) + ci[i];
        }
        for (let i = 0; i < P; i++) {
            if (out[i]) continue;
            const e = Math.max((bits(zr, i) >>> 20) & 0x7ff, (bits(zi, i) >>> 20) & 0x7ff);
            if (e < 1024) continue;
            out[i] = SHADE + ((it * 2 - (31 - Math.clz32(e - 1022))) & 15);
            zr[i] = zi[i] = cr[i] = ci[i] = 0;
        }
    }
    return out;
}

if (BRK === "astro") {
    console.log(fails.same === 2 ? "copro astro: --break astro caught (both pages' A/B differ)" : `copro astro: --break astro NOT caught (${fails.same} of 2)`);
    process.exit(fails.same === 2 ? 0 : 1);
}
const n = fails.same + fails.other;
console.log(n ? `copro astro: ${n} FAILED` : "copro astro: all ok");
process.exit(n ? 1 : 0);
