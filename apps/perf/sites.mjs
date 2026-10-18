// The instrumented SITES of a function (beyond the per-segment counters): memory.fill /
// memory.copy, integer stores (watch_hook.mjs), calls to the hwBlit import. Each site gets
// its counters in memory 1 and an entry in the plan, with the segment it sits in (so its
// counts land in the right loop).
import { OP } from "./wasm_ops.mjs";
import { fillHook, copyHook, blitSiteHook } from "./hooks.mjs";
import { watchHook, WATCHED, WATCH_WORDS } from "./watch_hook.mjs";
import { encU32 } from "./wasm_bin.mjs";

// scratch locals a hooked function gets: 7 i32 then 1 i64, after its own
export const tempsFor = (d) => {
    const b = d.numLocals;
    return { n: b, v: b + 1, d: b + 2, c: b + 3, a: b + 4, r: b + 5, b: b + 6, w: b + 7 };
};
export const TEMP_DECLS = [...encU32(7), 0x7f, ...encU32(1), 0x7e];

// function indices of the hwBlit import (the cart and the ROM both call it)
export const blitImports = (m) => {
    const out = new Set();
    let fi = 0;
    for (const imp of m.imports) if (imp.kind === 0) { if (imp.name === "hwBlit") out.add(fi); fi++; }
    return out;
};

// ctx: { buf, plan, next (counter word), seg (current segment), pal, vlo, blit (Set) }
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
    if (ctx.vlo !== null && WATCHED.has(op) && imm.mem === 0) {
        site(ctx.plan.watch);
        const h = watchHook(ctx.next, op, imm.offset, ctx.pal, ctx.vlo, t, orig);
        ctx.next += WATCH_WORDS;
        return h;
    }
    return null;
}
