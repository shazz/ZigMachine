// Run one cart for warmup + frames host frames and summarise its steady-state cost.
// Deterministic: fixed dt, no wall clock, counts only.
import { readFile } from "node:fs/promises";
import { bootInstrumented, hostFrame } from "./run_cart.mjs";
import { Profile } from "./profile.mjs";
import { TRAP_CYCLES, HBL_CALL, SNOOP_OVERFLOW, DISK_BLOCK, FRESCO_PLANE, FRAME_MC, MHZ, icacheCycles } from "./cost_model.mjs";
import { hotRegions, hintRegions, misSites, classTotals, causeTotals, libmCalls, paletteWrites } from "./report.mjs";
import { Waste } from "./waste.mjs";
import { wasteReport } from "./waste_report.mjs";
import { fitDump } from "./fit_dump.mjs";

const pct = (xs, q) => { const s = [...xs].sort((a, b) => a - b); return s[Math.min(s.length - 1, Math.floor(q * s.length))]; };
const Mc = (c) => Math.round(c / 1e4) / 100;

// One host frame and its cost parts: [cart, rom, icache, blit, hbl, fresco, disk] cycles.
function stepFrame(run, profiles, acc, hw0) {
    hostFrame(run);
    const cyc = profiles.map((P) => P.frame(acc));
    const mis = run.misaligned();
    run.hw.misaligned = mis;
    cyc[0] += (mis - hw0.misaligned) * TRAP_CYCLES; // each one traps into trap.c on the board
    const blit = run.hw.blitCycles - hw0.blitCycles;
    const hbl = (run.hw.hbls - hw0.hbls) * HBL_CALL + (run.hw.snoopOverflow - hw0.snoopOverflow) * SNOOP_OVERFLOW;
    let planes = 0;
    for (let p = 0; p < run.machine.hwPlanesNumber(); p++) planes += run.demo.isPlaneEnabled(p) ? 1 : 0;
    const code = profiles.reduce((a, P) => a + P.last.code, 0);
    const ic = icacheCycles(profiles.reduce((a, P) => a + P.last.fetch, 0), code);
    const disk = (run.hw.diskBlocks - hw0.diskBlocks) * DISK_BLOCK;
    return { parts: [cyc[0], cyc[1], ic, blit, hbl, planes * FRESCO_PLANE, disk], code, planes };
}

// opts: { frames, warmup, calls: Map(frame -> [[name, args]]), disk, top, pal, names: {cart, rom} }
export async function measure(cartPath, opts) {
    const run = await bootInstrumented(await readFile(cartPath), opts);
    const profiles = run.mods.map((m) => new Profile(m.tag, m.plan, m.mem));
    const keys = ["cart", "rom", "icache", "blit", "hbl", "fresco", "disk"];
    const w = { series: [], split: Object.fromEntries(keys.map((k) => [k, 0])), code: 0, hw: null, planes: 0 };
    const waste = new Waste(run);
    for (let f = 1; f <= opts.warmup + opts.frames; f++) {
        for (const [name, args] of opts.calls.get(f) ?? []) {
            if (typeof run.demo[name] !== "function") throw new Error(`cart has no export ${name}`);
            run.demo[name](...args);
        }
        const acc = f > opts.warmup, hw0 = { ...run.hw, cmd: [...run.hw.cmd] };
        if (acc && !w.hw) w.hw = hw0;
        waste.before(profiles);
        const { parts, code, planes } = stepFrame(run, profiles, acc, hw0);
        waste.after(profiles, acc);
        if (!acc) continue;
        w.planes += planes;
        keys.forEach((k, i) => { w.split[k] += parts[i]; });
        w.series.push(parts.reduce((a, b) => a + b, 0));
        w.code += code;
    }
    const r = summarize(cartPath, opts, run, profiles, w);
    r.waste = wasteReport(waste.w, profiles, w.planes / w.series.length, r.snoopOverflow);
    r.fit = fitDump(profiles, w, run);
    return { ...r, profiles };
}

function summarize(cartPath, opts, run, profiles, w) {
    const F = w.series.length, avg = w.series.reduce((a, b) => a + b, 0) / F;
    const causes = causeTotals(profiles);
    Object.assign(causes, { blitter: w.split.blit / F, hbl: w.split.hbl / F, fresco: w.split.fresco / F, icache: w.split.icache / F });
    const per = (n) => Math.round(n / F);
    return {
        cart: cartPath, frames: F, warmup: opts.warmup, calls: opts.callSpecs ?? [],
        mc: { avg: Mc(avg), p95: Mc(pct(w.series, 0.95)), max: Mc(Math.max(...w.series)) },
        fps: Math.min(60, Math.round((10 * MHZ * 1e6) / Math.max(1, avg)) / 10),
        budget: Math.round((100 * avg) / (FRAME_MC * 1e6)),
        split: Object.fromEntries(Object.entries(w.split).map(([k, v]) => [k, Mc(v / F)])),
        blits: per(run.hw.blits - w.hw.blits), hbls: per(run.hw.hbls - w.hw.hbls), hblStores: per(run.hw.hblStores - w.hw.hblStores), snoopOverflow: per(run.hw.snoopOverflow - w.hw.snoopOverflow), misaligned: per(run.hw.misaligned - w.hw.misaligned),
        blitUnits: run.hw.cmd.map((u, i) => per(u - w.hw.cmd[i])),
        codeKB: Math.round(w.code / F / 1024),
        causes: Object.fromEntries(Object.entries(causes).map(([k, v]) => [k, Math.round((100 * v) / avg)])),
        classes: classTotals(profiles), libm: libmCalls(profiles), palette: paletteWrites(profiles),
        hot: hotRegions(profiles, opts.top),
        hints: hintRegions(profiles, 5),
        misSites: misSites(run.mods, 5),
    };
}
