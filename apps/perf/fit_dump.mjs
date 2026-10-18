// The raw per-frame quantities the cost model multiplies, so apps/perf_fit.mjs can refit
// its parameters against board fps without re-running any cart: per loop the modelled
// instructions and bus stores (the roofline needs them apart), and the totals the other
// parameters scale (memset/memcpy bytes, D$ misses, HBL calls, snoop-queue overflow,
// enabled planes). Blitter and I$ cycles ride along as already costed.
import { PROBE_COUNTERS } from "./probe_hooks.mjs";

const MIN_REGION = 200; // modelled instructions a frame: smaller loops are lumped together

export function fitDump(profiles, w, run) {
    const F = Math.max(1, w.series.length), regions = [];
    let small = 0, fill = 0, copy = 0, misses = 0;
    for (const P of profiles) {
        const S = P.sum;
        for (let r = 0; r < S.instr.length; r++) {
            const i = S.instr[r] / F, s = S.stores[r] / F;
            if (!i && !s) continue;
            if (i < MIN_REGION && s < MIN_REGION / 4) small += i;
            else regions.push([Math.round(i), Math.round(s)]);
        }
        fill += S.fill.reduce((a, b) => a + b, 0) / F;
        copy += S.copy.reduce((a, b) => a + b, 0) / F;
        P.plan.probes.forEach((q, k) => { if (q.kind === "load" && PROBE_COUNTERS.load) misses += S.probe[2 * k] / F; });
    }
    regions.push([Math.round(small), 0]);
    const hw = (k) => (run.hw[k] - w.hw[k]) / F;
    return { regions, fill: Math.round(fill), copy: Math.round(copy), misses: Math.round(misses),
        blit: Math.round(w.split.blit / F), icache: Math.round(w.split.icache / F), hbls: hw("hbls"),
        overflow: hw("snoopOverflow"), disk: hw("diskBlocks"), planes: w.planes / F };
}
