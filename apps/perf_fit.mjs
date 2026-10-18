// Refit the cost model (apps/perf/cost_model.mjs) to MEASURED board frame times.
//
//   PERF_NO_CART_ARGS=1 node apps/frame_cost.mjs --all --warmup 720 --frames 300 \
//       --machine <the board's docs> --out calib.json      (the board's window, unattended)
//   node apps/perf_fit.mjs calib.json board_fps.csv [--fixed]
//
// Each cart's dump (apps/perf/fit_dump.mjs) holds the raw per-frame quantities the
// parameters multiply, so the fit re-costs every cart for a parameter set in microseconds.
// Loss: squared log error (capped at a 2x miss per cart) of predicted against measured frame time; a 60 fps cart only
// says "under 16.6 ms", so it counts only when predicted over that. Coordinate descent in
// log space within physical bounds. --fixed prints the current model's errors, no fit.
import { readFileSync } from "node:fs";
import * as CM from "./perf/cost_model.mjs";

const VBLANK_MS = 16.6;
const OUTLIER = Math.log(2) ** 2;
// physical bounds: a line refill from DDR is tens of cycles, not hundreds; CPI a modelled op >= ~1
const BOUNDS = { CPI: [0.6, 3], STORE_DRAIN: [5, 150], FILL_WORD_CYCLES: [8, 200], DMISS: [10, 80],
    FRESCO_PLANE: [0, 2e6], SNOOP_OVERFLOW: [0, 3000], HBL_CALL: [0, 3000], DISK_BLOCK: [0, 1e5] };

export function cycles(p, f) {
    let c = 0;
    for (const [i, s] of f.regions) c += Math.max(i * p.CPI, s * p.STORE_DRAIN);
    return c + ((f.fill + f.copy) / 4) * p.FILL_WORD_CYCLES + f.misses * p.DMISS + f.blit + f.icache
        + f.hbls * p.HBL_CALL + f.overflow * p.SNOOP_OVERFLOW + f.planes * p.FRESCO_PLANE + (f.disk ?? 0) * p.DISK_BLOCK;
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

export function fit(p0, rows, fixed = []) {
    const p = { ...p0 };
    for (let round = 0; round < 40; round++) {
        let moved = false;
        for (const [k, [lo, hi]] of Object.entries(BOUNDS).filter(([k]) => !fixed.includes(k))) {
            let best = loss(p, rows);
            for (const step of [1.5, 1.1, 1.02]) for (const dir of [step, 1 / step]) {
                for (;;) {
                    const v = Math.min(hi, Math.max(lo, (p[k] || lo || 1) * dir)), old = p[k];
                    p[k] = v;
                    const l = loss(p, rows);
                    if (l < best - 1e-9) { best = l; moved = true; } else { p[k] = old; break; }
                }
            }
        }
        if (!moved) break;
    }
    return p;
}

export function load(calibPath, csvPath) {
    const board = new Map(readFileSync(csvPath, "utf8").trim().split("\n").slice(1).map((l) => l.split(","))
        .map((c) => [c[0].replace(/^demo-|\.zmd$/g, ""), Number(c[2])]));
    return JSON.parse(readFileSync(calibPath, "utf8")).rows.filter((r) => r.fit && board.has(r.tag))
        .map((r) => ({ tag: r.tag, fit: r.fit, ms: board.get(r.tag) }));
}

export function report(p, rows) {
    const err = rows.map((r) => ({ tag: r.tag, ms: r.ms, pred: predMs(p, r.fit) }))
        .map((x) => ({ ...x, ratio: x.ms <= 17 ? Math.max(1, x.pred / VBLANK_MS) : x.pred / x.ms }));
    const abs = err.map((x) => Math.abs(Math.log(x.ratio))).sort((a, b) => a - b);
    const pct = (q) => Math.round(100 * (Math.exp(abs[Math.floor(q * (abs.length - 1))]) - 1));
    console.log(`params: ${Object.keys(BOUNDS).map((k) => `${k}=${+p[k].toPrecision(3)}`).join(" ")}`);
    console.log(`${rows.length} carts: median error ${pct(0.5)}%, p90 ${pct(0.9)}%, max ${pct(1)}%`);
    console.log("worst (cart, board ms, predicted ms):");
    for (const x of err.sort((a, b) => Math.abs(Math.log(b.ratio)) - Math.abs(Math.log(a.ratio))).slice(0, 15))
        console.log(`  ${x.tag.padEnd(22)} ${String(x.ms).padStart(7)} ${x.pred.toFixed(1).padStart(8)}  x${x.ratio.toFixed(2)}`);
    return err;
}

if (process.argv[1]?.endsWith("perf_fit.mjs")) {
    const [calib, csv] = process.argv.slice(2).filter((a) => !a.startsWith("--"));
    const rows = load(calib, csv);
    const p0 = Object.fromEntries(Object.keys(BOUNDS).map((k) => [k, CM[k]]));
    console.log("== current model");
    report(p0, rows);
    if (!process.argv.includes("--fixed")) { console.log("== fitted"); report(fit(p0, rows), rows); }
}
