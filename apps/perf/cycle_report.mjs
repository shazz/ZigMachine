// Cycle-waste findings from the round-3 probes (probe_hooks.mjs): divides, recomputed
// values, cache-hostile walks, per-iteration calls, i64 that fits in i32, branches that
// never flip inside a frame. Each with an estimated WASTED Mc/frame and a fix.
import { opCost, CPI, DMISS } from "./cost_model.mjs";
import { funcName } from "./wasm_bin.mjs";
import { DIV_OPS } from "./probe_sites.mjs";

export const CYCLE_HINTS = {
    div_loop: "divide by a hoisted reciprocal (fixed-point 1/x, multiply-high) or a reciprocal table: ZIGGY's divide is ~35 cycles",
    recompute: "the same inputs give the same result: hoist it out of the loop, or keep it from the last iteration/frame",
    cache_hostile: "walk the data in memory order (rows of a row-major table), or transpose/tile it: each miss is a DDR line refill",
    call_in_loop: "inline it (inline fn / comptime) or work on the whole span in one call",
    i64_fits_i32: "use i32/u32: every value seen fits, and i64 is two registers and libgcc sequences on rv32",
    invariant_branch: "the condition never changes inside the frame: test it once, outside the loop (two loops)",
};
export const CALL_OVERHEAD = 12;      // cycles: jal/ret, prologue/epilogue, argument moves
const MIN_EXECS = 2000;               // a site run fewer times a frame is not worth a finding
const Mc = (c) => Math.round(c / 1e4) / 100;
const hex = (n) => "0x" + n.toString(16);

// cycles a call of function fi costs (its regions over its entries), for a libm site
function funcCost(P, fi) {
    let cycles = 0, calls = 0;
    P.plan.regions.forEach((reg, r) => {
        if (reg.fi !== fi) return;
        cycles += P.sum.cycles[r];
        if (reg.loop === -1 && P.headSeg[r] >= 0) calls = P.sum.seg[P.headSeg[r]];
    });
    return calls ? cycles / calls : 0;
}

function finding(P, q, pattern, waste, detail) {
    const reg = P.plan.regions[P.plan.segRegion[q.seg]];
    return { pattern, mod: P.tag, fi: q.fi, func: funcName(P.plan.module, q.fi), loop: reg.loop, at: hex(q.at),
        waste: Mc(waste), detail, hint: CYCLE_HINTS[pattern] };
}

function valueFindings(P, q, i, F, out) {
    const n = P.sum.seg[q.seg] / F, both = P.sum.probe[2 * i] / F, sameB = P.sum.probe[2 * i + 1] / F;
    if (n < MIN_EXECS) return;
    const cost = q.callee !== undefined ? funcCost(P, q.callee) : opCost(q.op)[0] * CPI;
    if (DIV_OPS.has(q.op)) {
        const saved = n * (cost - 6 * CPI); // a reciprocal multiply instead
        out.push(finding(P, q, "div_loop", saved, `${Math.round(n)} divides a frame, divisor the same as the last one `
            + `${Math.round((100 * sameB) / n)}% of the time, both operands ${Math.round((100 * both) / n)}%`));
    } else if (both >= n / 2) {
        out.push(finding(P, q, "recompute", both * cost, `${Math.round(n)} a frame, ${Math.round((100 * both) / n)}% with the `
            + `same inputs as the previous one${q.callee !== undefined ? ` (${funcName(P.plan.module, q.callee)})` : ""}`));
    }
}

// loads summed per loop: misses from the D$ model, the share at a stride of a line or more
function cacheFindings(P, F, out) {
    const byR = new Map();
    P.plan.probes.forEach((q, i) => {
        if (q.kind !== "load") return;
        const r = P.plan.segRegion[q.seg], a = byR.get(r) ?? { q, loads: 0, misses: 0, strided: 0 };
        a.loads += P.sum.seg[q.seg]; a.misses += P.sum.probe[2 * i]; a.strided += P.sum.probe[2 * i + 1];
        byR.set(r, a);
    });
    for (const a of byR.values()) {
        const misses = a.misses / F, rate = a.misses / Math.max(1, a.loads), stride = a.strided / Math.max(1, a.loads);
        if (misses < 1000 || rate < 0.15) continue;
        out.push(finding(P, a.q, "cache_hostile", misses * DMISS * Math.min(1, stride / rate),
            `${Math.round(a.loads / F)} loads a frame, ${Math.round(misses)} D$ misses (${Math.round(100 * rate)}%), `
            + `${Math.round(100 * stride)}% of loads a line or more from the previous one`));
    }
}

export function cycleReport(profiles, frames) {
    const F = Math.max(1, frames), out = [];
    for (const P of profiles) {
        P.plan.probes.forEach((q, i) => {
            const n = P.sum.seg[q.seg] / F;
            if (q.kind === "value") valueFindings(P, q, i, F, out);
            else if (q.kind === "fit" && n >= MIN_EXECS && P.sum.probe[2 * i] / F >= n * 0.999)
                out.push(finding(P, q, "i64_fits_i32", n * (opCost(q.op)[0] - 1) * CPI, `${Math.round(n)} i64 ops a frame, every result fits in an i32`));
            else if (q.kind === "branch" && n >= MIN_EXECS * 2 && P.sum.probe[2 * i] / F <= 2)
                out.push(finding(P, q, "invariant_branch", n * 2 * CPI, `${Math.round(n)} tests a frame inside the loop, the outcome flips ${Math.round(P.sum.probe[2 * i] / F)}x a frame`));
        });
        for (const c of P.plan.calls) {
            const n = P.sum.seg[c.seg] / F;
            if (n >= MIN_EXECS) out.push(finding(P, c, "call_in_loop", n * CALL_OVERHEAD,
                `${Math.round(n)} calls a frame to ${funcName(P.plan.module, c.callee)} from inside the loop`));
        }
        cacheFindings(P, F, out);
    }
    return out.filter((f) => f.waste > 0);
}
