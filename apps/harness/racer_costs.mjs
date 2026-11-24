// RACER's cost table without the board (R82 M1): apps/harness/frame_cost.mjs (wasm op counts x the
// fitted cost model, ESTIMATES) over the cart's own knobs, driven by its keys:
//   node apps/harness/racer_costs.mjs [--frames 20] [--warmup 30]
// For each track: the heaviest of the eight fixed poses at R = 5, then R = 3..8 on that pose with
// each fill path (total Mc, the cart's share, est. fps) with the plain multiply twin (frame_cost bills
// the ZM-X import as a ROM call, so the plain twin is the fairer upper bound), the multiply A/B (import /
// plain / f32) and, when the names twin is built (tools/perf_names.sh, under the build lock), the cart's
// Mc by stage.
// 1.67 Mc is a 60 Hz frame at 100 MHz; the board drops below 60 fps between ~1.75 and 2.1 Mc.
import { costOf, parseArgs } from "./frame_cost.mjs";

const CART = "site/carts/demo-racer.wasm";
const argv = process.argv.slice(2);
const opt = (n, d) => (argv.includes(n) ? Number(argv[argv.indexOf(n) + 1]) : d);
const FRAMES = opt("--frames", 20), WARMUP = opt("--warmup", 30);
const code = (c) => c.charCodeAt(0);
const STAGES = [
    ["visibility", /visibility|pvs/i], ["collect (cull, transform, clip, project)", /collect|\.build|clipped|\.push|rcp|xform|clip/i],
    ["sort", /\.sort/i], ["fill (edge setup, spans)", /emit|poly|span|flush/i], ["sky + backdrop", /sky|backdrop|Painter/i], ["hud + report", /hud|report|bench|Hud/i],
];

async function cost(track, pose, r, { affine = false, mul = "plain" } = {}) {
    const keys = [];
    if (track === "city") keys.push(code("t"));
    keys.push(code("A") + pose, code("0") + r);
    if (affine) keys.push(code("f"));
    if (mul === "plain") keys.push(code("m")); // the plain twin: what a cart without ZM_ZMX=1 runs, an upper bound for the ZM-X op
    if (mul === "f32") keys.push(code("g"));
    const o = parseArgs([CART, "--frames", String(FRAMES), "--warmup", String(WARMUP), "--no-disk", "--top", "400", ...keys.flatMap((k) => ["--call", `1:key:${k}`])]);
    return costOf(CART, o);
}

function stageSplit(r) {
    const out = Object.fromEntries(STAGES.map(([n]) => [n, 0]));
    let named = false, mulsh = 0, other = 0;
    for (const h of r.hot) {
        if (/zmMulsh16/.test(h.func)) { mulsh += h.mc; continue; }
        if (h.mod !== "cart" || /^f\d+$/.test(h.func)) continue;
        named = true;
        const s = STAGES.find(([, re]) => re.test(h.func));
        if (s) out[s[0]] += h.mc; else other += h.mc;
    }
    return named ? { ...out, "other cart regions": other, "mulsh bodies (ROM import; one ZM-X op on the board)": mulsh } : null;
}

const row = (r) => `${r.mc.avg.toFixed(2)} Mc (cart ${r.split.cart.toFixed(2)}), ~${r.fps} fps`;
for (const track of ["oval", "city"]) {
    let worst = { pose: 0, mc: 0 };
    for (let k = 0; k < 8; k++) {
        const r = await cost(track, k, 5);
        if (r.mc.avg > worst.mc) worst = { pose: k, mc: r.mc.avg };
    }
    console.log(`\n## ${track}: heaviest pose ${"ABCDEFGH"[worst.pose]} (R = 5, CPU fill: ${worst.mc.toFixed(2)} Mc)\n`);
    console.log("| R | CPU fill | AFFINE fill |\n|---|---|---|");
    const stages = [];
    for (const r of [3, 4, 5, 6, 7, 8]) {
        const a = await cost(track, worst.pose, r), b = await cost(track, worst.pose, r, { affine: true });
        console.log(`| ${r} | ${row(a)} | ${row(b)} |`);
        stages.push([r, "cpu", stageSplit(a)], [r, "affine", stageSplit(b)]);
    }
    if (stages[0][2]) {
        const cols = Object.keys(stages[0][2]).map((k) => k.replace(/ \(.*/, "").replace("mulsh bodies", "mulsh bodies*"));
        console.log(`\nCart Mc by stage (regions >= 0.01 Mc; * the ROM import's bodies, one ZM-X op on the board):\n\n| R | fill | ${cols.join(" | ")} |\n|---|---|${cols.map(() => "---").join("|")}|`);
        for (const [r, f, sp] of stages) console.log(`| ${r} | ${f} | ${Object.values(sp).map((v) => v.toFixed(2)).join(" | ")} |`);
    } else console.log("\n(no names twin: run tools/perf_names.sh under the build lock for the per-stage split)");
    console.log("\nMultiply A/B at R = 5 (CPU fill):");
    for (const mul of ["", "plain", "f32"]) {
        const r = await cost(track, worst.pose, 5, { mul });
        console.log(`- ${mul || "mulsh import (billed as a ROM call here: pessimistic, the board runs one instruction)"}: ${row(r)}`);
    }
}
