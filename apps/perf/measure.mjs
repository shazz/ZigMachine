// Run one cart for warmup + frames host frames and summarise its steady-state cost.
// Deterministic: fixed dt, no wall clock, counts only.
import { readFile } from "node:fs/promises";
import { bootInstrumented, hostFrame } from "./run_cart.mjs";
import { Profile } from "./profile.mjs";
import { HBL_CALL, FRESCO_PLANE, FRAME_MC, MHZ, icacheCycles } from "./cost_model.mjs";
import { hotRegions, classTotals, causeTotals, libmCalls, paletteWrites } from "./report.mjs";
import { funcName } from "./wasm_bin.mjs";

const CLEAR_MIN = 16000;      // a fill this big is a plane clear (a 320x200 plane is 64,000)
const REDRAWN = 0.95;         // ... and wasted if this much of it is overwritten in the same frame

function checkClears(memory, P, log, clears) {
    const mem = new Uint8Array(memory.buffer);
    for (const e of log) {
        if (e.len < CLEAR_MIN) continue;
        let same = 0;
        for (let i = e.dest, end = e.dest + e.len; i < end; i++) if (mem[i] === e.value) same++;
        const key = `${P.tag}:${e.site}:${e.dest}`;
        const c = clears.get(key) ?? { mod: P.tag, func: funcName(P.plan.module, P.plan.fills[e.site].fi),
            dest: e.dest, len: e.len, frames: 0, overwritten: 0 };
        c.frames++; c.overwritten += 1 - same / e.len;
        clears.set(key, c);
    }
}

const pct = (xs, q) => { const s = [...xs].sort((a, b) => a - b); return s[Math.min(s.length - 1, Math.floor(q * s.length))]; };
const Mc = (c) => Math.round(c / 1e4) / 100;

// One host frame and its cost parts: [cart, rom, icache, blit, hbl, fresco] cycles.
function stepFrame(run, profiles, acc, hw0) {
    hostFrame(run);
    const cyc = profiles.map((P) => P.frame(acc));
    const blit = run.hw.blitCycles - hw0.blitCycles, hbl = (run.hw.hbls - hw0.hbls) * HBL_CALL;
    let planes = 0;
    for (let p = 0; p < run.machine.hwPlanesNumber(); p++) planes += run.demo.isPlaneEnabled(p) ? 1 : 0;
    const code = profiles.reduce((a, P) => a + P.last.code, 0);
    const ic = icacheCycles(profiles.reduce((a, P) => a + P.last.fetch, 0), code);
    return { parts: [cyc[0], cyc[1], ic, blit, hbl, planes * FRESCO_PLANE], code };
}

// opts: { frames, warmup, calls: Map(frame -> [[name, args]]), disk, top, pal, names: {cart, rom} }
export async function measure(cartPath, opts) {
    const run = await bootInstrumented(await readFile(cartPath), opts);
    const profiles = run.mods.map((m) => new Profile(m.tag, m.plan, m.mem));
    const keys = ["cart", "rom", "icache", "blit", "hbl", "fresco"];
    const w = { series: [], split: Object.fromEntries(keys.map((k) => [k, 0])), clears: new Map(), code: 0, hw: null };
    for (let f = 1; f <= opts.warmup + opts.frames; f++) {
        for (const [name, args] of opts.calls.get(f) ?? []) {
            if (typeof run.demo[name] !== "function") throw new Error(`cart has no export ${name}`);
            run.demo[name](...args);
        }
        const acc = f > opts.warmup, hw0 = { ...run.hw, cmd: [...run.hw.cmd] };
        if (acc && !w.hw) w.hw = hw0;
        const { parts, code } = stepFrame(run, profiles, acc, hw0);
        for (const P of profiles) { const log = P.takeLog(); if (acc) checkClears(run.memory, P, log, w.clears); }
        if (!acc) continue;
        keys.forEach((k, i) => { w.split[k] += parts[i]; });
        w.series.push(parts.reduce((a, b) => a + b, 0));
        w.code += code;
    }
    return { ...summarize(cartPath, opts, run, profiles, w), profiles };
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
        blits: per(run.hw.blits - w.hw.blits), hbls: per(run.hw.hbls - w.hw.hbls),
        blitUnits: run.hw.cmd.map((u, i) => per(u - w.hw.cmd[i])),
        codeKB: Math.round(w.code / F / 1024),
        causes: Object.fromEntries(Object.entries(causes).map(([k, v]) => [k, Math.round((100 * v) / avg)])),
        classes: classTotals(profiles), libm: libmCalls(profiles), palette: paletteWrites(profiles),
        clears: [...w.clears.values()].map((c) => ({ ...c, overwritten: Math.round((100 * c.overwritten) / c.frames),
            perFrame: Math.round((10 * c.frames) / F) / 10, wasted: c.overwritten / c.frames >= REDRAWN })),
        hot: hotRegions(profiles, opts.top),
    };
}
