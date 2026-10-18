// Operand producers inside straight-line code: for every instruction, which earlier
// instruction pushed each value it pops (-1 = unknown: a block boundary or a param).
// Enough to answer "is this store's value a constant / a byte just loaded / the same
// address it was read from" without a full dataflow analysis.
import { funcType } from "./wasm_bin.mjs";
import { OP, stackEffect } from "./wasm_ops.mjs";

const RESET = new Set([OP.block, OP.loop, OP.if, OP.else, OP.end, OP.br, OP.br_if, OP.br_table, OP.return, OP.unreachable]);

function effect(m, ins) {
    if (ins.op === OP.call) { const t = funcType(m, ins.imm); return [t.params.length, t.results.length]; }
    if (ins.op === OP.call_indirect) { const t = m.types[ins.imm[0]]; return [t.params.length + 1, t.results.length]; }
    return stackEffect(ins.op);
}

// -> args: Array(instrs.length) of producer index arrays (bottom .. top of the popped values)
export function producers(m, d) {
    const args = new Array(d.instrs.length);
    let stack = [];
    d.instrs.forEach((ins, i) => {
        const [pops, pushes] = effect(m, ins);
        const a = [];
        for (let k = 0; k < pops; k++) a.unshift(stack.length ? stack.pop() : -1);
        args[i] = a;
        for (let k = 0; k < pushes; k++) stack.push(i);
        if (RESET.has(ins.op)) stack = [];
    });
    return args;
}

// Follow local.tee (its value IS its operand) back to the real producer.
export function source(d, args, i) {
    while (i >= 0 && d.instrs[i].op === OP.local_tee) i = args[i][0];
    return i;
}

// Locals written anywhere inside loop L (nested loops included).
export function localsSetIn(d, L) {
    const set = new Set();
    const inLoop = (ins) => { for (let l = ins.loop; l >= 0; l = d.loops[l].parent) if (l === L) return true; return false; };
    for (const ins of d.instrs) if ((ins.op === OP.local_set || ins.op === OP.local_tee) && inLoop(ins)) set.add(ins.imm);
    return set;
}

// Two address producers that name the same address: the same local (not rewritten in
// between is assumed: straight-line code), or the same constant.
export function sameAddress(d, a, b) {
    if (a < 0 || b < 0) return false;
    const x = d.instrs[a], y = d.instrs[b];
    if (x.op !== y.op) return false;
    return (x.op === OP.local_get || x.op === OP.i32_const) && x.imm === y.imm;
}
