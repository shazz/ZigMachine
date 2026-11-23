// Which instructions get a round-3 probe (probe_hooks.mjs), and the plan entry for each:
// every load (the D$ model), costly ops and libm calls (value repeats), i64 arithmetic
// (fits in i32?), branches inside a loop body (constant over the frame?).
import { OP, isLoad } from "./wasm_ops.mjs";
import { funcName, funcType } from "./wasm_bin.mjs";
import { isLibm } from "./cost_model.mjs";
import { loadProbe, valueProbe, fitProbe, branchProbe, PROBE_WORDS } from "./probe_hooks.mjs";
import { source } from "./flow.mjs";

// a divide whose divisor is a constant: GCC already made it a multiply (cost_model CONST_DIV)
function constDiv(d, ctx) {
    const v = source(d, ctx.args, ctx.args[ctx.i][1]);
    return v >= 0 && (d.instrs[v].op === OP.i32_const || d.instrs[v].op === OP.i64_const);
}

// a direct call, in a loop, to a small defined function: its call overhead is paid per iteration
const SMALL_BODY = 160; // bytes of wasm: a setPixel, a min/max, an accessor
function smallCall(m, d, ins) {
    const k = ins.imm - m.numImportedFuncs;
    return ins.loop >= 0 && k >= 0 && m.bodies[k].end - m.bodies[k].start <= SMALL_BODY;
}

// op -> [kind, operand count] for the value probe
const VALUE_OPS = {
    0x6d: ["i32", 2], 0x6e: ["i32", 2], 0x6f: ["i32", 2], 0x70: ["i32", 2],
    0x7f: ["i64", 2], 0x80: ["i64", 2], 0x81: ["i64", 2], 0x82: ["i64", 2],
    0xa0: ["f64", 2], 0xa1: ["f64", 2], 0xa2: ["f64", 2], 0xa3: ["f64", 2], 0x9f: ["f64", 1],
    0x95: ["f32", 2], 0x91: ["f32", 1],
};
export const DIV_OPS = new Set([0x6d, 0x6e, 0x6f, 0x70, 0x7f, 0x80, 0x81, 0x82]);
const FIT_OPS = new Set([0x7c, 0x7d, 0x7e, 0x86, 0x87, 0x88]);

// a libm call with 1 or 2 float params of one kind -> [kind, n], else null
function libmShape(m, fi) {
    if (!isLibm(funcName(m, fi))) return null;
    const p = funcType(m, fi).params;
    if (!p.length || p.length > 2 || p.some((x) => x !== p[0]) || (p[0] !== "f32" && p[0] !== "f64")) return null;
    return [p[0], p.length];
}

// -> [kind, hook bytes] or null. ctx.next is the first free counter word.
export function probeFor(m, d, ins, t, orig, ctx) {
    const { op, imm } = ins;
    const add = (kind, extra = {}) => {
        ctx.plan.probes.push({ kind, word: ctx.next, fi: d.fi, at: ins.at, seg: ctx.seg, op, ...extra });
        const w = ctx.next;
        ctx.next += PROBE_WORDS[kind];
        return w;
    };
    if (isLoad(op) && imm.mem === 0) return loadProbe(add("load"), imm.offset, t, orig);
    if (VALUE_OPS[op]) {
        if (DIV_OPS.has(op) && constDiv(d, ctx)) return null;
        const [k, n] = VALUE_OPS[op];
        return valueProbe(add("value"), k, n, t, orig);
    }
    if (FIT_OPS.has(op)) return fitProbe(add("fit"), t, orig);
    if ((op === OP.br_if || op === OP.if) && ins.bodyBranch) return branchProbe(add("branch"), t, orig);
    if (op === OP.call) {
        const shape = libmShape(m, imm);
        if (shape) return valueProbe(add("value", { callee: imm }), shape[0], shape[1], t, orig);
        if (smallCall(m, d, ins)) ctx.plan.calls.push({ fi: d.fi, at: ins.at, seg: ctx.seg, callee: imm });
    }
    return null;
}
