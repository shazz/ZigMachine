// Refit the cost model (apps/perf/cost_model.mjs) to MEASURED board frame times.
//
//   PERF_NO_CART_ARGS=1 node apps/frame_cost.mjs --all --warmup 720 --frames 300 \
//       --machine <the board's docs> --out calib.json      (the board's window, unattended)
//   node apps/perf_fit.mjs calib.json board_fps.csv [--fixed | --bench] [--exclude a,b] [--table F.md]
//
// Each cart's dump (apps/perf/fit_dump.mjs) holds the raw per-frame quantities the
// parameters multiply, so the fit re-costs every cart for a parameter set in microseconds.
// Loss: squared log error (capped at a 2x miss per cart) of predicted against measured frame time; a 60 fps cart only
// says "under 16.6 ms", so it counts only when predicted over that. Coordinate descent in
// log space within physical bounds. --fixed prints the current model's errors, no fit;
// --bench fits only what the native bench cart cannot measure (BENCH_FREE), the per-op
// constants stay at their measured values. --exclude drops carts whose board build is not
// the one estimated; --table writes every cart's board ms, estimate and error.
import { readFileSync, writeFileSync } from "node:fs";
import * as CM from "./perf/cost_model.mjs";

const VBLANK_MS = 16.6;
const OUTLIER = Math.log(2) ** 2;
// physical bounds: a line refill from DDR is tens of cycles, not hundreds; a posted store ~2
const BOUNDS = { CPI: [0.6, 3], STORE_DRAIN: [1, 150], FILL_WORD_CYCLES: [1, 200], COPY_WORD_CYCLES: [1, 200],
    DMISS: [5, 80], FRESCO_PLANE: [0, 2e6], FRAME_BASE: [0, 1e6], SNOOP_OVERFLOW: [0, 3000], HBL_CALL: [0, 3000],
    DISK_BLOCK: [0, 1e5], TRAP_CYCLES: [50, 1500] };
// --bench, stage 1: what the CART costs, fitted to the board's measured cart cycles (cart_c,
// uncensored: a 60 fps cart says how long its cart ran too); stage 2: the compositor, fitted
// to frame time with the cart side held.
export const BENCH_CART = ["CPI", "SNOOP_OVERFLOW"];
export const BENCH_FRAME = ["FRESCO_PLANE", "FRAME_BASE"];

export function cycles(p, f) {
    let c = 0;
    for (const [i, s] of f.regions) c += Math.max(i * p.CPI, s * p.STORE_DRAIN);
    return c + (f.fill / 4) * p.FILL_WORD_CYCLES + (f.copy / 4) * p.COPY_WORD_CYCLES + f.misses * p.DMISS + f.blit
        + f.icache + f.hbls * p.HBL_CALL + f.overflow * p.SNOOP_OVERFLOW + p.FRAME_BASE + f.planes * p.FRESCO_PLANE
        + (f.disk ?? 0) * p.DISK_BLOCK + (f.misaligned ?? 0) * p.TRAP_CYCLES;
}
const cartCycles = (p, f) => cycles({ ...p, FRESCO_PLANE: 0, FRAME_BASE: 0 }, f);
export function cartLoss(p, rows) {
    let l = 0;
    for (const r of rows.filter((x) => x.cartMc > 0.1)) l += Math.min(Math.log(Math.max(1e4, cartCycles(p, r.fit)) / (r.cartMc * 1e6)) ** 2, OUTLIER);
    return l;
}
const predMs = (p, f) => Math.max(VBLANK_MS, cycles(p, f) / (CM.MHZ * 1000));

export function loss(p, rows) {
    let l = 0;
    for (const r of rows) {
        const e = Math.log(predMs(p, r.fit) / r.ms);
        const sq = r.ms <= 17 ? (e > 0 ? e * e : 0) : e * e;
        l += Math.min(sq, OUTLIER); // robust: a cart off by more than 2x (another phase, an unmodelled cost) cannot drag the fit
    }
    return l;
}

export function fit(p0, rows, fixed = [], lossFn = loss) {
    const p = { ...p0 };
    for (let round = 0; round < 40; round++) {
        let moved = false;
        for (const [k, [lo, hi]] of Object.entries(BOUNDS).filter(([k]) => !fixed.includes(k))) {
            let best = lossFn(p, rows);
            for (const step of [1.5, 1.1, 1.02]) for (const dir of [step, 1 / step]) {
                for (;;) {
                    const v = Math.min(hi, Math.max(lo, (p[k] || lo || 1) * dir)), old = p[k];
                    p[k] = v;
                    const l = lossFn(p, rows);
                    if (l < best - 1e-9) { best = l; moved = true; } else { p[k] = old; break; }
                }
            }
        }
        if (!moved) break;
    }
    return p;
}

export function load(calibPath, csvPath, exclude = []) {
    const lines = readFileSync(csvPath, "utf8").trim().split("\n"), cartCol = lines[0].split(",").indexOf("cart_c");
    const board = new Map(lines.slice(1).map((l) => l.split(","))
        .map((c) => [c[0].replace(/^demo-|\.zmd$/g, ""), { ms: Number(c[2]), cartMc: cartCol > 0 ? Number(c[cartCol]) / 1e6 || 0 : 0 }]));
    return JSON.parse(readFileSync(calibPath, "utf8")).rows.filter((r) => r.fit && board.has(r.tag) && !exclude.includes(r.tag))
        .map((r) => ({ tag: r.tag, fit: r.fit, ...board.get(r.tag) }));
}

export function report(p, rows) {
    const err = rows.map((r) => ({ tag: r.tag, ms: r.ms, pred: predMs(p, r.fit) }))
        .map((x) => ({ ...x, ratio: x.ms <= 17 ? Math.max(1, x.pred / VBLANK_MS) : x.pred / x.ms }));
    const abs = err.map((x) => Math.abs(Math.log(x.ratio))).sort((a, b) => a - b);
    const pct = (q) => Math.round(100 * (Math.exp(abs[Math.floor(q * (abs.length - 1))]) - 1));
    console.log(`params: ${Object.keys(BOUNDS).map((k) => `${k}=${+p[k].toPrecision(3)}`).join(" ")}`);
    console.log(`${rows.length} carts: median error ${pct(0.5)}%, p90 ${pct(0.9)}%, max ${pct(1)}%`);
    const ce = rows.filter((r) => r.cartMc > 0.1).map((r) => Math.abs(Math.log(Math.max(1e4, cartCycles(p, r.fit)) / (r.cartMc * 1e6)))).sort((x, y) => x - y);
    const cq = (q) => Math.round(100 * (Math.exp(ce[Math.floor(q * (ce.length - 1))]) - 1));
    if (ce.length) console.log(`cart side against the board's cart_c (${ce.length} carts > 0.1 Mc): median ${cq(0.5)}%, p90 ${cq(0.9)}%`);
    console.log("worst (cart, board ms, predicted ms):");
    for (const x of err.sort((a, b) => Math.abs(Math.log(b.ratio)) - Math.abs(Math.log(a.ratio))).slice(0, 15))
        console.log(`  ${x.tag.padEnd(22)} ${String(x.ms).padStart(7)} ${x.pred.toFixed(1).padStart(8)}  x${x.ratio.toFixed(2)}`);
    return err;
}

// Every cart: board ms, predicted ms (both floored at a VBLANK), and the error as a ratio.
export function table(p, rows) {
    const lines = ["| cart | board ms | predicted ms | error |", "|---|---|---|---|"];
    for (const r of [...rows].sort((a, b) => b.ms - a.ms)) {
        const pred = predMs(p, r.fit), ratio = r.ms <= 17 ? Math.max(1, pred / VBLANK_MS) : pred / r.ms;
        lines.push(`| ${r.tag} | ${r.ms} | ${pred.toFixed(1)} | x${ratio.toFixed(2)} |`);
    }
    return lines.join("\n") + "\n";
}

if (process.argv[1]?.endsWith("perf_fit.mjs")) {
    const argv = process.argv.slice(2), opt = (k) => { const i = argv.indexOf(k); return i >= 0 ? argv.splice(i, 2)[1] : null; };
    const exclude = (opt("--exclude") ?? "").split(",").filter(Boolean), tableOut = opt("--table");
    const [calib, csv] = argv.filter((a) => !a.startsWith("--"));
    const rows = load(calib, csv, exclude);
    const p0 = Object.fromEntries(Object.keys(BOUNDS).map((k) => [k, CM[k]]));
    console.log("== current model");
    let p = p0;
    report(p0, rows);
    if (!argv.includes("--fixed")) {
        const only = (keys) => Object.keys(BOUNDS).filter((k) => !keys.includes(k));
        if (argv.includes("--bench")) p = fit(fit(p0, rows, only(BENCH_CART), cartLoss), rows, only(BENCH_FRAME));
        else p = fit(p0, rows);
        console.log("== fitted"); report(p, rows);
    }
    if (tableOut) writeFileSync(tableOut, table(p, rows));
}
