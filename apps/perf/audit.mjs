// Cross-check: static findings (lint.mjs) against the dynamic run (measure.mjs).
// A static finding in code that runs hot every frame ranks first, by its measured
// Mc/frame; one whose loop never ran in the steady-state window is downgraded to "cold"
// (init-only, or a path the run did not take). Dynamic-only findings (palette rewrites,
// cleared-then-redrawn planes, hot narrow-store loops the static rules missed) join in.
import { lintModule, HINTS } from "./lint.mjs";

export const HOT_MC = 0.05;         // 3 % of a 60 Hz frame at 100 MHz
const Mc = (c) => Math.round(c / 1e4) / 100;

function regionIndex(P) {
    const byLoop = new Map(), byFunc = new Map();
    P.plan.regions.forEach((r, i) => {
        byLoop.set(`${r.fi}:${r.loop}`, i);
        if (!byFunc.has(r.fi)) byFunc.set(r.fi, []);
        byFunc.get(r.fi).push(i);
    });
    return { byLoop, byFunc };
}

function measured(P, idx, f) {
    const F = Math.max(1, P.frames);
    const regs = f.loop >= 0 ? [idx.byLoop.get(`${f.fi}:${f.loop}`)] : idx.byFunc.get(f.fi) ?? [];
    let cycles = 0, runs = 0;
    for (const r of regs) {
        if (r === undefined) continue;
        cycles += P.sum.cycles[r];
        if (P.headSeg[r] >= 0) runs = Math.max(runs, P.sum.seg[P.headSeg[r]]);
    }
    // A libm call's cost is in the callee: charge the loop its calls x the callee's cost a call.
    for (const fi of f.callees ?? []) cycles += runs * perCall(P, idx, fi);
    return { mc: Mc(cycles / F), perFrame: Math.round(runs / F) };
}

function perCall(P, idx, fi) {
    const regs = idx.byFunc.get(fi) ?? [];
    const body = regs.find((r) => P.plan.regions[r].loop === -1);
    const calls = body !== undefined && P.headSeg[body] >= 0 ? P.sum.seg[P.headSeg[body]] : 0;
    return calls ? regs.reduce((a, r) => a + P.sum.cycles[r], 0) / calls : 0;
}

const status = (mc, perFrame) => (mc >= HOT_MC ? "hot" : perFrame > 0 ? "per-frame" : "cold");

function dynamicOnly(dyn, staticKeys) {
    const out = [];
    // the waste detectors (waste_report.mjs): ranked by the Mc/frame they waste
    for (const f of dyn.waste.findings) out.push({ ...f, mc: f.waste, status: f.waste >= HOT_MC ? "hot" : "per-frame" });
    for (const h of dyn.hot.filter((x) => x.cause === "bus: narrow stores" && x.mc >= HOT_MC))
        if (!staticKeys.has(`${h.mod}:${h.fi}:${h.loop}`))
            out.push({ pattern: "narrow_store_hot", mod: h.mod, func: h.func, at: h.at, loop: h.loop,
                detail: `${h.iters} iterations a frame, bound by byte/half stores`, hint: HINTS.byte_fill, mc: h.mc, status: "hot" });
    return out;
}

// dyn: measure() result WITH profiles. cartBytes: the cart wasm. names: cart name Map.
export function crossCheck(dyn, cartBytes, names) {
    const P = dyn.profiles.find((p) => p.tag === "cart");
    const idx = regionIndex(P);
    const findings = lintModule(cartBytes, { names }).map((f) => {
        // a float phase is one store a call: its cost is not the function's, its drift is the point
        const m = f.pattern === "float_phase" ? { ...measured(P, idx, f), mc: 0 } : measured(P, idx, f);
        return { ...f, mod: "cart", ...m, status: status(m.mc, m.perFrame),
            detail: f.loop >= 0 ? `${f.count} op(s) in a loop run ${m.perFrame} times a frame`
                : `${f.count} site(s) in a function run ${m.perFrame} times a frame` };
    });
    for (const f of findings) if (f.pattern === "table_rebuild" && f.status !== "cold") f.pattern = "table_rebuild_per_frame";
    const keys = new Set(findings.map((f) => `cart:${f.fi}:${f.loop}`));
    const all = [...findings, ...dynamicOnly(dyn, keys)];
    const order = { hot: 0, "per-frame": 1, cold: 2 };
    all.sort((a, b) => order[a.status] - order[b.status] || b.mc - a.mc || a.func.localeCompare(b.func));
    return all;
}
