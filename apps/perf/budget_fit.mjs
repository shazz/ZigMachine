// Fit frame_cost --budget's FRESCO side (cost_model.mjs COMP_*) to the board probe, and score the
// budget's frame (cart + FRESCO, serial) against board frame time next to frame_cost's own total.
//
//   PERF_NO_CART_ARGS=1 node apps/frame_cost.mjs --all --warmup 720 --frames 300 \
//       --machine <the board's docs/> --out calib.json
//   node apps/perf/budget_fit.mjs calib.json fps.csv [--exclude a,b] [--table F.md]
//
// The board's columns (fpga/tools/board_fps_probe.py): comp_busy (compositor clocks, 125 MHz:
// x0.8 for sys cycles), passes, cart_c, frame_ms. A 60 fps cart only bounds its frame (<= 16.6
// ms), so its frame error counts only when predicted slower; comp_busy is measured either way.
import { readFileSync, writeFileSync } from "node:fs";
import { FRAME_MC } from "./cost_model.mjs";

const SYS_PER_COMP = 100 / 125;

function load(calibPath, csvPath, exclude) {
    const lines = readFileSync(csvPath, "utf8").trim().split("\n"), head = lines[0].split(",");
    const board = new Map(lines.slice(1).map((l) => Object.fromEntries(l.split(",").map((v, i) => [head[i], v])))
        .map((r) => [r.cart.replace(/^demo-|\.zmd$/g, ""), r]));
    return JSON.parse(readFileSync(calibPath, "utf8")).rows
        .filter((r) => r.frameBudget && board.has(r.tag) && !exclude.includes(r.tag) && board.get(r.tag).comp_busy !== "-")
        .map((r) => {
            const b = board.get(r.tag), fb = r.frameBudget;
            const f = fb.features;
            return { tag: r.tag, ms: Number(b.frame_ms), comp: (Number(b.comp_busy) * SYS_PER_COMP) / 1e6, passesBoard: Number(b.passes),
                x: [f.narrowFirst, f.narrowLater, f.wideFirst, f.wideLater, f.bg], passes: fb.planes.reduce((a, p) => a + p.passes, 0) + fb.bg.passes,
                cart: fb.cartMc, old: r.mc.avg,
                measured: (Number(b.cart_c) + Number(b.comp_busy) * SYS_PER_COMP + Number(b.hbl)) / 1e6 };
        });
}

// least squares, normal equations
function lsq(X, y) {
    const n = X[0].length, A = Array.from({ length: n }, () => Array(n).fill(0)), b = Array(n).fill(0);
    X.forEach((x, i) => x.forEach((v, j) => { b[j] += v * y[i]; x.forEach((u, k) => { A[j][k] += v * u; }); }));
    for (let i = 0; i < n; i++) for (let r = 0; r < n; r++) if (r !== i) {
        const f = A[r][i] / A[i][i];
        for (let k = 0; k < n; k++) A[r][k] -= f * A[i][k];
        b[r] -= f * b[i];
    }
    return b.map((v, i) => v / A[i][i]);
}

const ms = (mc) => Math.max(1000 / 60, (mc / FRAME_MC) * (1000 / 60));
const err = (pred, board) => (board <= 17 ? Math.max(1, pred / (1000 / 60)) : pred / board);
function stats(xs) {
    const a = xs.map((x) => Math.abs(Math.log(x))).sort((p, q) => p - q), q = (f) => Math.round(100 * (Math.exp(a[Math.floor(f * (a.length - 1))]) - 1));
    return `median ${q(0.5)}%, p90 ${q(0.9)}%, max ${q(1)}% (${a.length} carts)`;
}

const argv = process.argv.slice(2), opt = (k) => { const i = argv.indexOf(k); return i >= 0 ? argv.splice(i, 2)[1] : null; };
const exclude = (opt("--exclude") ?? "").split(",").filter(Boolean), tableOut = opt("--table");
const rows = load(...argv.filter((a) => !a.startsWith("--")), exclude);
// No intercept: a frame with no layer and no BG pass is one CLEAR (fitted, it came out below zero).
const k = lsq(rows.map((r) => r.x.map((v) => v / 1e6)), rows.map((r) => r.comp));
const comp = (r) => r.x.reduce((a, v, i) => a + (v * k[i]) / 1e6, 0);
const names = ["narrow first", "narrow later", "wide first", "wide later", "BG"];
console.log(`cycles a pass: ${names.map((n, i) => `${n} ${k[i].toFixed(0)}`).join(", ")}`);
console.log(`passes: the model's equal the board's on ${rows.filter((r) => r.passes === r.passesBoard).length} of ${rows.length} carts (the rest: the dirty-line planner skipped lines)`);
console.log(`FRESCO against comp_busy: ${stats(rows.map((r) => comp(r) / r.comp))}`);
const slow = rows.filter((r) => r.ms > 17);
for (const [name, f] of [["frame_cost total", (r) => r.old], ["budget, cart + FRESCO", (r) => r.cart + comp(r)]]) {
    const side = rows.filter((r) => (f(r) <= FRAME_MC) === (r.ms <= 17)).length;
    console.log(`${name.padEnd(22)}: all ${stats(rows.map((r) => err(ms(f(r)), r.ms)))}; under 60 fps ${stats(slow.map((r) => err(ms(f(r)), r.ms)))}; right side of 60 fps ${side}/${rows.length}`);
}
// The board's own sum, cart_c + comp_busy + its HBL handlers: the serial model with MEASURED parts
// (what the budget models), and the honest yardstick for a total (uncensored, every cart).
const right = rows.filter((r) => (r.measured <= FRAME_MC) === (r.ms <= 17)).length;
console.log(`board's measured sum (cart_c + comp + hbl): right side of 60 fps ${right}/${rows.length}`);
const real = rows.filter((r) => r.measured > 0.3);
for (const [name, f] of [["frame_cost total", (r) => r.old], ["budget, cart + FRESCO", (r) => r.cart + comp(r)]])
    console.log(`${name.padEnd(22)} vs that sum: ${stats(real.map((r) => f(r) / r.measured))}`);
if (tableOut) {
    const t = ["| cart | board ms | board FRESCO Mc | budget FRESCO Mc | passes board / model | budget Mc (cart + FRESCO) | frame_cost Mc |", "|---|---|---|---|---|---|---|"];
    for (const r of [...rows].sort((a, b) => b.ms - a.ms))
        t.push(`| ${r.tag} | ${r.ms} | ${r.comp.toFixed(2)} | ${comp(r).toFixed(2)} | ${r.passesBoard} / ${r.passes} | ${(r.cart + comp(r)).toFixed(2)} (${r.cart} + ${comp(r).toFixed(2)}) | ${r.old} |`);
    writeFileSync(tableOut, t.join("\n") + "\n");
}
