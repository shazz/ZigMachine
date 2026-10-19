// Rewrite a wasm module with a counter at the head of every segment (wasm_body.mjs),
// byte counters on memory.fill/memory.copy, watched stores (palette, VRAM) and hwBlit sites.
// Returns the new bytes and the PLAN: what each counter means and the static contents
// of every segment, so a segment's count x its contents = exact dynamic op counts.
import { parseModule, encU32, encName, section, funcName } from "./wasm_bin.mjs";
import { decodeFunction } from "./wasm_body.mjs";
import { OP, isLoad, isStore, LOAD_WIDTH, STORE_WIDTH } from "./wasm_ops.mjs";
import { opCost, isLibm, CLASSES, CLS, CONST_DIV } from "./cost_model.mjs";
import { producers, source } from "./flow.mjs";
import { inc, FIRST_COUNTER } from "./hooks.mjs";
import { hookFor, TEMP_DECLS, TEMP_GROUPS, blitImports } from "./sites.mjs";

const NCLS = CLASSES.length;
const DIVIDES = new Set([0x6d, 0x6e, 0x6f, 0x70, 0x7f, 0x80, 0x81, 0x82]);

// A divide by a constant: GCC turns wasm2c's x / 7 into a multiply-high and shifts.
export function constDivisor(d, args, i) {
    const v = source(d, args, args[i][1]);
    return v >= 0 && (d.instrs[v].op === OP.i32_const || d.instrs[v].op === OP.i64_const);
}

function segStatics(m, d, args, seg, plan, s) {
    let instr = 0, stores = 0, fetch = 0;
    for (let i = seg.first; i <= seg.last; i++) {
        const { op, imm } = d.instrs[i];
        const [c, cls, st] = DIVIDES.has(op) && constDivisor(d, args, i) ? [op < 0x7f ? CONST_DIV : 4 * CONST_DIV, -1, 0] : opCost(op);
        instr += c; stores += st;
        fetch += Math.min(c, 3); // inline rv32 instructions: a soft-float op is a call into shared libgcc
        if (cls >= 0) { plan.cls[s * NCLS + cls]++; plan.clsCyc[s * NCLS + cls] += c; }
        if (op === OP.call && isLibm(funcName(m, imm))) plan.cls[s * NCLS + CLS.libm_call]++;
        if ((isLoad(op) || isStore(op)) && (1 << imm.align) < (LOAD_WIDTH[op] ?? STORE_WIDTH[op])) plan.cls[s * NCLS + CLS.unaligned]++;
    }
    plan.segInstr[s] = instr; plan.segStores[s] = stores; plan.segFetch[s] = fetch;
}

function regionOf(d, loopIdx, plan, regionIds) {
    const key = loopIdx;
    if (!regionIds.has(key)) {
        const loop = loopIdx >= 0 ? d.loops[loopIdx] : null;
        regionIds.set(key, plan.regions.length);
        plan.regions.push({ fi: d.fi, name: d.name, loop: loopIdx, at: loop ? loop.at : d.body.start,
            depth: loop ? loop.depth + 1 : 0, parentLoop: loop ? loop.parent : -2 });
    }
    return regionIds.get(key);
}

function rewriteBody(m, k, ctx) {
    const d = decodeFunction(m, k), plan = ctx.plan, regionIds = new Map();
    const args = producers(m, d);
    const heads = new Map();
    for (const seg of d.segs) {
        const s = plan.segFunc.length;
        plan.segFunc.push(d.fi); plan.segRegion.push(regionOf(d, seg.loop, plan, regionIds));
        plan.segWord.push(ctx.next); plan.segAt.push(d.instrs[seg.first].at);
        heads.set(seg.first, [inc(ctx.next++), s]);
        segStatics(m, d, args, seg, plan, s);
    }
    const code = [];
    let hooked = false;
    for (let i = 0; i < d.instrs.length; i++) {
        if (heads.has(i)) { const [b, s] = heads.get(i); code.push(...b); ctx.seg = s; }
        ctx.args = args; ctx.i = i;
        const h = hookFor(d, i, ctx);
        if (h) { hooked = true; code.push(...h); } else code.push(...ctx.buf.subarray(d.instrs[i].at, d.instrs[i].next));
    }
    const decls = d.localDecls.map(([n, t]) => [...encU32(n), t]).flat();
    const nDecls = d.localDecls.length + (hooked ? TEMP_GROUPS : 0);
    const body = [...encU32(nDecls), ...decls, ...(hooked ? TEMP_DECLS : []), ...code];
    return [...encU32(body.length), ...body];  // array literals spread without the call stack
}

const SECTION_ORDER = [1, 2, 3, 4, 5, 13, 6, 7, 8, 9, 12, 10, 11];
const rank = (id) => SECTION_ORDER.indexOf(id);

function concat(parts) {
    const n = parts.reduce((a, p) => a + p.length, 0), out = new Uint8Array(n);
    let o = 0;
    for (const p of parts) { out.set(p, o); o += p.length; }
    return out;
}

function assemble(m, codeParts, words) {
    const pages = Math.max(1, Math.ceil((words * 4) / 65536));
    const memIdx = m.numMemories;
    const out = [m.buf.subarray(0, 8)];
    let memDone = false, expDone = false;
    const addMem = () => { memDone = true; out.push(section(5, [1, 0, ...encU32(pages)])); };
    const addExp = (old) => {
        expDone = true;
        const n = old ? m.exports.length : 0;
        const body = old ? [...m.buf.subarray(old.vecStart, old.end)] : [];
        out.push(section(7, [...encU32(n + 1), ...body, ...encName("__fc"), 2, ...encU32(memIdx)]));
    };
    for (const s of m.sections) {
        if (s.id !== 0 && !memDone && rank(s.id) > rank(5)) addMem();
        if (s.id !== 0 && !expDone && rank(s.id) > rank(7)) addExp(null);
        if (s.id === 5) throw new Error("instrument: a module that defines its own memory is not supported");
        if (s.id === 7) { addExp({ vecStart: vecStart(m.buf, s.payload), end: s.end }); continue; }
        if (s.id === 10) {
            const code = concat(codeParts);
            out.push(new Uint8Array([10, ...encU32(code.length)]), code);
            continue;
        }
        out.push(m.buf.subarray(s.start, s.end));
    }
    return concat(out);
}

function vecStart(buf, p) { while (buf[p] & 0x80) p++; return p + 1; }

// pal: [lo, hi) absolute byte addresses of the palette window, or null for no check.
// vlo: the VRAM pool's absolute base (stores into it are watched), or null.
// probes: the round-3 probes (D$ model, value repeats, i64 fits, branch flips).
// names: a Map(function index -> name) from an unstripped twin (names.mjs), for a
// stripped release build.
export function instrument(buf, { pal = null, vlo = null, names = null, probes = true } = {}) {
    const m = parseModule(buf);
    if (names && m.names.size === 0) m.names = names;
    const plan = { names: m.names, regions: [], segFunc: [], segRegion: [], segWord: [], segAt: [],
        segInstr: [], segStores: [], segFetch: [], cls: [], fills: [], copies: [], watch: [], mis: [], blits: [], probes: [], calls: [] };
    const ctx = { buf, m, plan, pal, vlo, probes, blit: blitImports(m), next: FIRST_COUNTER };
    const nSegGuess = m.bodies.length * 64;
    plan.cls = new Uint32Array(nSegGuess * NCLS);
    plan.clsCyc = new Float32Array(nSegGuess * NCLS);
    const grow = (n) => {
        if (n * NCLS <= plan.cls.length) return;
        const c = new Uint32Array(n * NCLS * 2), y = new Float32Array(n * NCLS * 2);
        c.set(plan.cls); y.set(plan.clsCyc); plan.cls = c; plan.clsCyc = y;
    };
    const parts = [new Uint8Array(encU32(m.bodies.length))];
    for (let k = 0; k < m.bodies.length; k++) {
        grow(plan.segFunc.length + 20000);
        parts.push(new Uint8Array(rewriteBody(m, k, ctx)));
    }
    plan.words = ctx.next;
    plan.module = m;
    return { bytes: assemble(m, parts, ctx.next), plan };
}
