// The instrumented SITES of a function (beyond the per-segment counters): memory.fill /
// memory.copy, integer stores (watch_hook.mjs), calls to the hwBlit import. Each site gets
// its counters in memory 1 and an entry in the plan, with the segment it sits in (so its
// counts land in the right loop).
import { OP, LOAD_WIDTH } from "./wasm_ops.mjs";
const LOAD_BYTES = LOAD_WIDTH;
import { fillHook, copyHook, blitSiteHook, inc, I32, LGET, LTEE, MIS_LOADS } from "./hooks.mjs";
import { watchHook, WATCHED, WATCH_WORDS } from "./watch_hook.mjs";
import { encU32 } from "./wasm_bin.mjs";
import { probeFor } from "./probe_sites.mjs";

// scratch locals a hooked function gets, after its own: 7 i32, 1 i64, then the probes'
// 2 i32, 2 i64, 2 f32, 2 f64 (TEMP_GROUPS local declarations)
export const tempsFor = (d) => {
    const b = d.numLocals;
    return { n: b, v: b + 1, d: b + 2, c: b + 3, a: b + 4, r: b + 5, b: b + 6, w: b + 7,
        p1: b + 8, p2: b + 9, q1: b + 10, q2: b + 11, x1: b + 12, x2: b + 13, y1: b + 14, y2: b + 15 };
};
export const TEMP_DECLS = [...encU32(7), 0x7f, ...encU32(1), 0x7e, ...encU32(2), 0x7f, ...encU32(2), 0x7e,
    ...encU32(2), 0x7d, ...encU32(2), 0x7c];
export const TEMP_GROUPS = 6;

// function indices of the hwBlit import (the cart and the ROM both call it)
export const blitImports = (m) => {
    const out = new Set();
    let fi = 0;
    for (const imp of m.imports) if (imp.kind === 0) { if (imp.name === "hwBlit") out.add(fi); fi++; }
    return out;
};

// ctx: { buf, m, plan, next (counter word), seg (current segment), pal, vlo, blit (Set), probes (bool) }
export function hookFor(d, i, ctx) {
    const { op, imm, at, next } = d.instrs[i];
    const orig = [...ctx.buf.subarray(at, next)];
    const t = tempsFor(d), site = (list) => list.push({ fi: d.fi, at, word: ctx.next, seg: ctx.seg }) - 1;
    if (op === OP.memory_fill) { const s = site(ctx.plan.fills); return fillHook(ctx.next++, s, t, ctx.vlo, orig); }
    if (op === OP.memory_copy) { const s = site(ctx.plan.copies); return copyHook(ctx.next++, s, t, ctx.vlo, orig); }
    if (op === OP.call && ctx.blit.has(imm)) {
        ctx.plan.blits.push({ fi: d.fi, at, seg: ctx.seg });
        return blitSiteHook(ctx.plan.blits.length - 1, orig);
    }
    if (imm && imm.mem === 0 && LOAD_BYTES[op] > 1) { // [addr] -> count a misaligned one, then the load
        const w = ctx.next++; // this site's own count, for the report of where the traps come from
        ctx.plan.mis.push({ fi: d.fi, at, word: w });
        const inner = ctx.probes ? probeFor(ctx.m, d, d.instrs[i], t, orig, ctx) : null;
        return [...LTEE(t.a), ...I32(imm.offset), 0x6a, ...I32(Math.min(LOAD_BYTES[op], 4) - 1), 0x71, 0x04, 0x40, ...inc(MIS_LOADS), ...inc(w), 0x0b, ...LGET(t.a), ...(inner ?? orig)];
    }
    if (ctx.vlo !== null && WATCHED.has(op) && imm.mem === 0) {
        site(ctx.plan.watch);
        const w = ctx.next++;
        ctx.plan.mis.push({ fi: d.fi, at, word: w });
        const h = watchHook(ctx.next, op, imm.offset, ctx.pal, ctx.vlo, t, orig, w);
        ctx.next += WATCH_WORDS;
        return h;
    }
    return ctx.probes ? probeFor(ctx.m, d, d.instrs[i], t, orig, ctx) : null;
}
