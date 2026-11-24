// RACER's cost table without the board (R82 M1): apps/harness/frame_cost.mjs (wasm op counts x the
// fitted cost model, ESTIMATES) over the cart's own knobs, driven by its keys:
//   node apps/harness/racer_costs.mjs [--frames 20] [--warmup 30] [--md]
// For each track: the heaviest of the eight fixed poses at R = 5, then R = 3..8 on that pose with
// each fill path (total Mc, the cart's share, est. fps), the multiply A/B (mulsh / plain / f32) and,
// when the names twin is built (tools/perf_names.sh, under the build lock), the cart's Mc by stage.
// 1.67 Mc is a 60 Hz frame at 100 MHz; the board drops below 60 fps between ~1.75 and 2.1 Mc.
import { costOf, parseArgs } from "./frame_cost.mjs";

const CART = "site/carts/demo-racer.wasm";
const argv = process.argv.slice(2);
const opt = (n, d) => (argv.includes(n) ? Number(argv[argv.indexOf(n) + 1]) : d);
const FRAMES = opt("--frames", 20), WARMUP = opt("--warmup", 30);
const code = (c) => c.charCodeAt(0);
const STAGES = [
    ["visibility", /visibility|pvs/i], ["collect", /collect|build|face|clipped|push|xform|get/i],
    ["sort", /sort/i], ["fill", /emit|poly|span|flush|fill|affine|row/i], ["sky+backdrop", /sky|backdrop/i], ["hud", /hud|draw|print|report|bench/i],
];

async function cost(track, pose, r, { affine = false, mul = "" } = {}) {
    const keys = [];
    if (track === "city") keys.push(code("t"));
    keys.push(code("A") + pose, code("0") + r);
    if (affine) keys.push(code("f"));
    if (mul === "plain") keys.push(code("m"));
    if (mul === "f32") keys.push(code("g"));
    const o = parseArgs([CART, "--frames", String(FRAMES), "--warmup", String(WARMUP), "--no-disk", "--top", "400", ...keys.flatMap((k) => ["--call", `1:key:${k}`])]);
    return costOf(CART, o);
}

function stageSplit(r) {
    const out = Object.fromEntries(STAGES.map(([n]) => [n, 0]));
    let named = false;
    for (const h of r.hot) {
        if (h.mod !== "cart" || /^f\d+$/.test(h.func)) continue;
        named = true;
        const s = STAGES.find(([, re]) => re.test(h.func));
        if (s) out[s[0]] += h.mc;
    }
    return named ? out : null;
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
    for (const r of [3, 4, 5, 6, 7, 8]) {
        const a = await cost(track, worst.pose, r), b = await cost(track, worst.pose, r, { affine: true });
        console.log(`| ${r} | ${row(a)} | ${row(b)} |`);
    }
    console.log("\nMultiply A/B at R = 5 (CPU fill):");
    for (const mul of ["", "plain", "f32"]) {
        const r = await cost(track, worst.pose, 5, { mul });
        console.log(`- ${mul || "mulsh (the ZM-X import, billed as a call here)"}: ${row(r)}`);
    }
    const split = stageSplit(await cost(track, worst.pose, 5));
    if (split) console.log("\nCart Mc by stage at R = 5:", Object.entries(split).map(([k, v]) => `${k} ${v.toFixed(3)}`).join(", "));
    else console.log("\n(no names twin: run tools/perf_names.sh under the build lock for the per-stage split)");
}
