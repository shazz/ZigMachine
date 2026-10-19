// Summaries of a profiled run: totals per op class, hot regions with their cause,
// libm calls, palette rewrites, the cart-level cost split. Plain data (JSON-ready).
import { CLASSES, CAUSES, CPI, STORE_DRAIN, isLibm } from "./cost_model.mjs";
import { funcName } from "./wasm_bin.mjs";
import { WATCH_WORDS } from "./watch_hook.mjs";

const NCLS = CLASSES.length;
const Mc = (c) => Math.round(c / 1e4) / 100;
const hex = (n) => "0x" + n.toString(16);

// Split one region's window cycles into causes (cycles). "integer" is what is left.
export function regionCauses(P, r) {
    const S = P.sum, out = { bus: 0, f64: 0, div: 0, i64: 0, f32: 0, calls: 0, integer: 0 };
    const total = S.cycles[r];
    const compute = S.instr[r] * CPI, bus = S.stores[r] * STORE_DRAIN;
    out.bus = Math.max(0, bus - compute) + Math.max(0, total - Math.max(compute, bus)); // + fills/copies
    const scale = Math.min(1, compute / Math.max(1, total)); // a bus-bound region's ops hide behind its stores
    for (const [cause, classes] of Object.entries(CAUSES))
        for (const c of classes) out[cause] += S.clsCyc[r * NCLS + CLASSES.indexOf(c)] * CPI * scale;
    const named = Object.values(out).reduce((a, b) => a + b, 0);
    out.integer = Math.max(0, total - named);
    return out;
}

function causeLabel(P, r, causes) {
    const top = Object.entries(causes).sort((a, b) => b[1] - a[1])[0][0];
    if (top !== "bus") return top;
    const narrow = P.sum.cls[r * NCLS + CLASSES.indexOf("narrow_store")];
    const wide = P.sum.cls[r * NCLS + CLASSES.indexOf("store32")];
    return narrow > wide ? "bus: narrow stores" : "bus: stores";
}

export function hotRegions(profiles, n) {
    const all = [];
    for (const P of profiles) {
        const F = Math.max(1, P.frames);
        P.plan.regions.forEach((reg, r) => {
            if (!P.sum.cycles[r]) return;
            const causes = regionCauses(P, r);
            all.push({ mod: P.tag, func: reg.name, fi: reg.fi, loop: reg.loop, at: hex(reg.at), depth: reg.depth,
                iters: Math.round(P.sum.iters[r] / F), mc: Mc(P.sum.cycles[r] / F), cycles: P.sum.cycles[r] / F,
                cause: causeLabel(P, r, causes), region: r });
        });
    }
    return all.sort((a, b) => b.cycles - a.cycles).slice(0, n);
}

export function classTotals(profiles) {
    const out = Object.fromEntries(CLASSES.map((c) => [c, 0]));
    for (const P of profiles) {
        const F = Math.max(1, P.frames);
        for (let i = 0; i < P.sum.cls.length; i++) out[CLASSES[i % NCLS]] += P.sum.cls[i] / F;
        out.fill_bytes = (out.fill_bytes ?? 0) + P.sum.fill.reduce((a, b) => a + b, 0) / F;
        out.copy_bytes = (out.copy_bytes ?? 0) + P.sum.copy.reduce((a, b) => a + b, 0) / F;
    }
    for (const k of Object.keys(out)) out[k] = Math.round(out[k]);
    return out;
}

export function causeTotals(profiles) {
    const out = {};
    for (const P of profiles) {
        const F = Math.max(1, P.frames);
        P.plan.regions.forEach((_, r) => {
            if (!P.sum.cycles[r]) return;
            for (const [k, v] of Object.entries(regionCauses(P, r))) out[k] = (out[k] ?? 0) + v / F;
        });
    }
    return out;
}

// Calls a frame into libm-named functions (needs a name section).
export function libmCalls(profiles) {
    const out = {};
    for (const P of profiles) {
        const F = Math.max(1, P.frames);
        P.plan.regions.forEach((reg, r) => {
            if (reg.loop !== -1 || !isLibm(reg.name) || P.headSeg[r] < 0) return;
            const n = P.sum.seg[P.headSeg[r]] / F;
            if (n) out[reg.name] = Math.round(n);
        });
    }
    return out;
}

export function paletteWrites(profiles) {
    let writes = 0, same = 0;
    const sites = [];
    for (const P of profiles) {
        const F = Math.max(1, P.frames);
        P.plan.watch.forEach((s, i) => {
            const w = P.sum.watch[WATCH_WORDS * i] / F, u = P.sum.watch[WATCH_WORDS * i + 1] / F;
            writes += w; same += u;
            if (w) sites.push({ mod: P.tag, func: funcName(P.plan.module, s.fi), at: hex(s.at), writes: Math.round(w),
                unchanged: Math.round(u), fi: s.fi, region: P.plan.segRegion[s.seg] });
        });
    }
    sites.sort((a, b) => b.unchanged - a.unchanged);
    return { writes: Math.round(writes), unchanged: Math.round(same), sites: sites.slice(0, 5) };
}

// Where the wide accesses of unproven alignment run (the memarg hint is below the width):
// the places a misaligned address can come from when the audit counts traps.
export function hintRegions(profiles, n) {
    const all = [], u = CLASSES.indexOf("unaligned");
    for (const P of profiles) {
        const F = Math.max(1, P.frames);
        P.plan.regions.forEach((reg, r) => {
            const k = P.sum.cls[r * NCLS + u] / F;
            if (k >= 1) all.push({ mod: P.tag, func: reg.name, loop: reg.loop, at: hex(reg.at), hints: Math.round(k) });
        });
    }
    return all.sort((a, b) => b.hints - a.hints).slice(0, n);
}

/// The sites that really trapped (a misaligned address), by function, from the per-site counters
/// of the whole run (warm-up included): where to look when MISALIGNED is large.
export function misSites(mods, n) {
    const all = [];
    for (const m of mods) {
        if (!m.mem || !m.plan?.mis) continue;
        const w = new Uint32Array(m.mem.buffer);
        for (const s of m.plan.mis) {
            const k = w[s.word];
            if (k) all.push({ mod: m.tag, func: funcName(m.plan.module, s.fi), at: hex(s.at), count: k });
        }
    }
    return all.sort((a, b) => b.count - a.count).slice(0, n);
}
