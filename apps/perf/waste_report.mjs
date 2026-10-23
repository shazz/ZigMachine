// Waste findings from a run (waste.mjs + the store-watch counters), each with its
// estimated WASTED Mc/frame: the cycles that would go if only what changes were written.
import { paletteWrites } from "./report.mjs";
import { cycleReport } from "./cycle_report.mjs";
import { CPI, SNOOP_OVERFLOW, STORE_DRAIN, BLIT_DFLUSH, BLIT_CALL, FRESCO_PLANE, fillCycles, copyCycles } from "./cost_model.mjs";
import { WATCH_WORDS } from "./watch_hook.mjs";
import { funcName } from "./wasm_bin.mjs";
import { PFB_H } from "./frame_diff.mjs";

export const WASTE_HINTS = {
    redundant_store: "only modify what changes: draw the static page once, keep dirty rects / rows, skip unchanged pixels",
    clear_then_redraw: "save-under or dirty rects: restore only what the moving parts covered, not the whole plane",
    static_plane: "draw it once (it never changes); the dirty-line compositor (perf/vseq-dirty) then skips it",
    palette_rewrite: "write only the colour registers that change (a raster coder never rewrites one)",
    tiny_blits: "batch tiny ops into one blit, or do them with CPU word stores",
    scroll_band: "pan it (REG_HSCROLL / FB_BASE) and draw only the new column",
};
const MIN_BYTES = 1024;            // per frame: below this, nothing worth reporting
const Mc = (c) => Math.round(c / 1e3) / 1000; // 3 decimals: at ~2 cycles a posted store, small wastes are kCycles
const hex = (n) => "0x" + n.toString(16);

function regionFinding(P, r, f, F) {
    const reg = P.plan.regions[r], S = P.sum;
    const share = Math.min(1, f.sameStores / Math.max(1, S.stores[r]));
    return { pattern: "redundant_store", mod: P.tag, fi: reg.fi, func: reg.name, loop: reg.loop, at: hex(reg.at),
        waste: Mc((S.cycles[r] * share) / F), bytes: Math.round(f.bytes / F), same: Math.round(f.sameBytes / F),
        detail: `${Math.round(f.bytes / F)} B stored into VRAM a frame, ${Math.round(f.sameBytes / F)} B `
            + `(${Math.round((100 * f.sameBytes) / f.bytes)}%) rewrite what was there at frame start`, hint: WASTE_HINTS.redundant_store };
}

// store-watch sites summed per loop, then the regions worth a finding
function redundantStores(profiles, F) {
    const out = [];
    for (const P of profiles) {
        const byR = new Map();
        P.plan.watch.forEach((s, i) => {
            const w = P.sum.watch.subarray(i * WATCH_WORDS, (i + 1) * WATCH_WORDS);
            if (!w[3]) return;
            const r = P.plan.segRegion[s.seg], a = byR.get(r) ?? { bytes: 0, sameBytes: 0, sameStores: 0 };
            a.bytes += w[3]; a.sameBytes += w[5]; a.sameStores += w[4];
            byR.set(r, a);
        });
        for (const [r, f] of byR) if (f.bytes / F >= MIN_BYTES && f.sameBytes >= f.bytes / 2) out.push(regionFinding(P, r, f, F));
    }
    return out;
}

function fillFindings(W, profiles, F) {
    const out = [];
    const clears = new Set([...W.clears.values()].map((c) => `${c.mod}:${c.site}`)); // reported as clear_then_redraw
    for (const f of W.fills.values()) {
        if (f.bytes / F < MIN_BYTES || f.same < f.bytes / 2 || (!f.copy && clears.has(`${f.mod}:${f.site}`))) continue;
        const P = profiles.find((x) => x.tag === f.mod), site = (f.copy ? P.plan.copies : P.plan.fills)[f.site];
        out.push({ pattern: "redundant_store", mod: f.mod, fi: site.fi, func: funcName(P.plan.module, site.fi), loop: -1,
            at: hex(site.at), waste: Mc((f.copy ? copyCycles : fillCycles)(f.same) / F),
            detail: `${f.copy ? "memcpy" : "memset"} of ${Math.round(f.bytes / F)} B into VRAM a frame, ${Math.round(f.same / F)} B leave the byte as it was`,
            hint: WASTE_HINTS.redundant_store });
    }
    return out;
}

// A big fill whose bytes the same frame redraws: all of them (>= 95 %, the clear itself is
// wasted), or most of them back to exactly what they were (save-under would skip those).
const REDRAWN = 0.95;
function clearFindings(W, profiles) {
    return [...W.clears.values()].filter((c) => c.overwritten / c.frames >= REDRAWN || c.restored / c.frames >= c.len / 2).map((c) => {
        const P = profiles.find((x) => x.tag === c.mod), site = P.plan.fills[c.site], kept = c.restored / c.frames;
        const over = c.overwritten / c.frames, saved = over >= REDRAWN ? c.len : kept;
        return { pattern: "clear_then_redraw", mod: c.mod, fi: site.fi, func: funcName(P.plan.module, site.fi), loop: -1,
            at: hex(site.at), waste: Mc(fillCycles(saved) * (c.frames / W.frames)), bytes: c.len, same: Math.round(kept),
            detail: `${c.len} B cleared ${Math.round((10 * c.frames) / W.frames) / 10}x a frame; ${Math.round(100 * over)}% `
                + `redrawn in the same frame, ${Math.round(kept)} B (${Math.round((100 * kept) / c.len)}%) exactly as they were`,
            hint: WASTE_HINTS.clear_then_redraw };
    });
}

function planeFindings(W, F) {
    return [...W.planes.values()].filter((s) => s.staticFrames === s.frames && s.frames >= Math.min(F, 30)).map((s) => ({
        pattern: "static_plane", mod: "cart", func: `plane ${s.p}`, loop: -1, at: "-",
        waste: 0, stored: Math.round(s.stored / F), // its stores are redundant_store findings already
        detail: `unchanged for all ${s.frames} frames; ${Math.round(s.stored / F)} B stored into it a frame anyway`
            + `; FRESCO still paints it (${Mc(FRESCO_PLANE)} Mc)`, hint: WASTE_HINTS.static_plane }));
}

function blitFindings(W, profiles, F) {
    return [...W.blits.values()].filter((b) => b.tiny / F >= 1).map((b) => {
        const P = profiles.find((x) => x.tag === b.mod);
        return { pattern: "tiny_blits", mod: b.mod, fi: b.fi, func: b.fi >= 0 ? funcName(P.plan.module, b.fi) : "?", loop: -1,
            // a tiny op's fixed cost (start, spin, D$ range flush) against CPU word stores of its bytes
            at: b.site >= 0 ? hex(P.plan.blits[b.site].at) : "-",
            waste: Mc(Math.max(0, b.tiny * BLIT_CALL - (b.tinyBytes / 4) * STORE_DRAIN) / F),
            detail: `${Math.round(b.tiny / F)} of ${Math.round(b.ops / F)} blits a frame under 256 B, each paying `
                + `~${BLIT_CALL} cycles of start, spin and D$ flush (${BLIT_DFLUSH})`,
            hint: WASTE_HINTS.tiny_blits };
    });
}

function scrollFindings(W, F) {
    return [...W.scroll.values()].filter((s) => s.frames >= F / 2 && s.rows / s.frames >= 4).map((s) => {
        const rows = s.rows / s.frames, band = rows * s.width, stored = s.stored / F;
        const k = [...s.k.entries()].sort((a, b) => b[1] - a[1])[0][0];
        // the CPU's shift, word moves at best (a load + a store + addressing); a pan makes the band free.
        // A blit-shift is no longer the fix: at ~2 cycles a posted store it costs more than the CPU's words.
        const waste = (stored / 4) * Math.max(STORE_DRAIN, 4 * CPI);
        return { pattern: "scroll_band", mod: "cart", func: `plane ${s.p}`, loop: -1, at: "-", waste: Mc(waste),
            detail: `${Math.round(rows)} rows a frame are the last frame's shifted ${k} px, ${Math.round(stored)} B stored by the CPU there`,
            hint: WASTE_HINTS.scroll_band };
    }).filter((f) => f.waste > 0);
}

// colour writes of the value already there; past the snoop queue they also stall the pass
function paletteFindings(profiles, overflow) {
    const pal = paletteWrites(profiles);
    return pal.sites.filter((s) => s.unchanged >= 64).map((s) => {
        const share = pal.writes ? s.unchanged / pal.writes : 0;
        return { pattern: "palette_rewrite", mod: s.mod, fi: s.fi, func: s.func, loop: -1, at: s.at,
            waste: Mc(s.unchanged * STORE_DRAIN + overflow * share * SNOOP_OVERFLOW),
            detail: `${s.unchanged} of ${s.writes} colour writes a frame rewrite the value already there`,
            hint: WASTE_HINTS.palette_rewrite };
    });
}

// -> { stored, changed, lines, dirtyGainMc, findings (by waste) }
export function wasteReport(W, profiles, planesOn, overflow = 0) {
    const F = Math.max(1, W.frames);
    const findings = [...redundantStores(profiles, F), ...fillFindings(W, profiles, F), ...clearFindings(W, profiles),
        ...planeFindings(W, F), ...blitFindings(W, profiles, F), ...scrollFindings(W, F),
        ...paletteFindings(profiles, overflow), ...cycleReport(profiles, F)].sort((a, b) => b.waste - a.waste);
    const lines = W.lines / F;
    return { stored: Math.round(W.stored / F), changed: Math.round(W.changed / F), lines: Math.round(lines),
        dirtyGainMc: Mc(planesOn * FRESCO_PLANE * (1 - lines / PFB_H)),
        wasteMc: Mc(findings.reduce((a, f) => a + f.waste * 1e6, 0)), findings };
}
