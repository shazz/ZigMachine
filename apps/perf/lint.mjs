// Static bad-pattern detectors over a cart's wasm, one finding per (pattern, loop) or
// (pattern, function). Each finding names the function, the loop's byte offset and a
// one-line fix. Static findings say what the code COULD cost; perf_audit.mjs ranks them
// by what the dynamic run (frame_cost) says they DO cost per frame.
import { parseModule, funcName } from "./wasm_bin.mjs";
import { decodeFunction } from "./wasm_body.mjs";
import { OP, isLoad, LOAD_WIDTH } from "./wasm_ops.mjs";
import { opCost, isLibm, CLS } from "./cost_model.mjs";
import { producers, source, localsSetIn, sameAddress } from "./flow.mjs";

export const HINTS = {
    byte_fill: "@memset (word stores) or a CHISEL FILL instead of a narrow-store loop",
    byte_copy: "@memcpy / u32 copies, or a CHISEL BLIT, instead of a byte-at-a-time copy",
    f64_loop: "fixed point (Q16.16) or f32 on the FPU: every f64 op is a libgcc soft-float call",
    libm_loop: "zg.fixtrig table on a u32 angle, or hoist it: libm per element is hundreds of cycles",
    div_loop: "multiply by a hoisted reciprocal, a reciprocal table or a shift: ZIGGY divides iteratively",
    i64_loop: "u32 maths: i64 is two registers on rv32, its mul/shift/div libgcc sequences",
    table_rebuild: "build the table once at init, not every frame",
    float_phase: "a u32 phase + zg.fixtrig: a float accumulator drifts and costs FPU/soft-float time",
    palette_rewrite: "write only the colour registers that change (a raster coder never rewrites one)",
    pixel_call: "write the span in the loop (pointer + stride, u32 where aligned) or blit: one call per pixel",
};

const NARROW_STORE = new Set([0x3a, 0x3b, 0x3c, 0x3d]);
const NARROW_LOAD = new Set([0x2c, 0x2d, 0x2e, 0x2f, 0x30, 0x31, 0x32, 0x33]);
const DIVS = new Set([0x6d, 0x6e, 0x6f, 0x70, 0x7f, 0x80, 0x81, 0x82]);
const I64_HEAVY = new Set([CLS.i64_mul, CLS.i64_div, CLS.i64_shift]);
const F_ADD = new Set([0x92, 0x93, 0xa0, 0xa1]);
const isConst = (op) => op === OP.i32_const || op === OP.i64_const;
const PIXEL_FN_MAX = 80; // instructions: a setPixel, not a span routine

function loopFindings(m, d, args, L, out, pixelFns) {
    const body = d.instrs.map((ins, i) => [ins, i]).filter(([ins]) => ins.loop === L);
    const written = localsSetIn(d, L);
    const hit = {};
    const add = (k, n = 1) => { hit[k] = (hit[k] ?? 0) + n; };
    const libm = [], pix = []; // callee function indices, one per call site
    let stores = 0;
    for (const [ins, i] of body) {
        const [, cls] = opCost(ins.op);
        if (NARROW_STORE.has(ins.op)) {
            const v = source(d, args, args[i][1]), p = v >= 0 ? d.instrs[v] : null;
            if (p && (isConst(p.op) || (p.op === OP.local_get && !written.has(p.imm)))) add("byte_fill");
            else if (p && NARROW_LOAD.has(p.op)) add("byte_copy");
        }
        if (cls === CLS.f64 && ins.op !== OP.f64_const) add("f64_loop");
        if (ins.op === OP.call && isLibm(funcName(m, ins.imm))) { add("libm_loop"); libm.push(ins.imm); }
        if (ins.op === OP.call && pixelFns.has(ins.imm)) { add("pixel_call"); pix.push(ins.imm); }
        if (DIVS.has(ins.op)) { const v = source(d, args, args[i][1]); if (v < 0 || !isConst(d.instrs[v].op)) add("div_loop"); }
        if (I64_HEAVY.has(cls)) add("i64_loop");
        if (ins.op >= 0x36 && ins.op <= 0x3e) stores++;
    }
    if (libm.length && stores) add("table_rebuild");
    for (const [pattern, count] of Object.entries(hit))
        out.push({ pattern, fi: d.fi, func: d.name, loop: L, at: "0x" + d.loops[L].at.toString(16), count, hint: HINTS[pattern],
            ...(/libm|table/.test(pattern) ? { callees: libm } : pattern === "pixel_call" ? { callees: pix } : {}) });
}

// f32/f64 store of (load of the same address) +/- something: a float accumulator in memory.
function floatPhases(d, args, out) {
    let n = 0, at = -1;
    d.instrs.forEach((ins, i) => {
        if (ins.op !== 0x38 && ins.op !== 0x39) return;
        const v = source(d, args, args[i][1]);
        if (v < 0 || !F_ADD.has(d.instrs[v].op)) return;
        for (const o of args[v]) {
            const l = source(d, args, o);
            if (l < 0 || !isLoad(d.instrs[l].op) || LOAD_WIDTH[d.instrs[l].op] !== (ins.op === 0x38 ? 4 : 8)) continue;
            if (d.instrs[l].imm.offset !== ins.imm.offset) continue;
            if (sameAddress(d, source(d, args, args[l][0]), source(d, args, args[i][0]))) { n++; if (at < 0) at = ins.at; }
        }
    });
    if (n) out.push({ pattern: "float_phase", fi: d.fi, func: d.name, loop: -1, at: "0x" + at.toString(16), count: n, hint: HINTS.float_phase });
}

// -> [{pattern, fi, func, loop, at, count, hint}]
export function lintModule(buf, { names = null } = {}) {
    const m = parseModule(buf);
    if (names && m.names.size === 0) m.names = names;
    const out = [], fns = m.bodies.map((_, k) => decodeFunction(m, k));
    // a "pixel function": small, loop-free, and it stores a byte or a half-word
    const pixelFns = new Set(fns.filter((d) => !d.loops.length && d.instrs.length <= PIXEL_FN_MAX
        && d.instrs.some((ins) => NARROW_STORE.has(ins.op))).map((d) => d.fi));
    for (const d of fns) {
        const args = producers(m, d);
        for (let L = 0; L < d.loops.length; L++) loopFindings(m, d, args, L, out, pixelFns);
        floatPhases(d, args, out);
    }
    return out;
}
