// Decode one function body into instructions, its loop tree and its counting segments.
//
// A SEGMENT is a straight run of instructions that always executes as a whole (no
// branch target inside, no branch out before its end), so one counter at its head
// times its static contents gives exact dynamic counts. Every loop body starts a
// segment, so a loop's first segment counts its iterations, and no segment spans a
// loop boundary, so each segment belongs to exactly one REGION: its innermost loop,
// or the function's straight code (loop -1).
import { Reader, funcName, funcType } from "./wasm_bin.mjs";
import { decode, OP } from "./wasm_ops.mjs";

const SPLIT_AFTER = new Set([OP.loop, OP.if, OP.else, OP.end, OP.br_if, OP.br, OP.br_table, OP.return, OP.unreachable]);

function readLocals(r) {
    const decls = [];
    for (let n = r.u32(); n--;) decls.push([r.u32(), r.u8()]);
    return decls;
}

// Instructions with their absolute byte offset and innermost enclosing loop.
function walk(r, end) {
    const instrs = [], loops = [], ctl = [];
    let inner = -1;
    while (r.pos < end) {
        const at = r.pos;
        const { op, imm } = decode(r);
        const ins = { op, imm, at, next: r.pos, loop: inner };
        instrs.push(ins);
        // a branch INSIDE the innermost loop's body: an `if`, or a br_if to a block nested
        // in that loop (not the back edge, not an exit): the per-iteration decisions
        if (op === OP.if || op === OP.br_if) {
            const innerPos = ctl.lastIndexOf(inner), target = op === OP.if ? ctl.length : ctl.length - 1 - imm;
            ins.bodyBranch = inner >= 0 && target > innerPos;
        }
        if (op === OP.block || op === OP.if) ctl.push(null);
        else if (op === OP.loop) {
            loops.push({ idx: instrs.length - 1, at, parent: inner, depth: ctl.filter((c) => c !== null).length });
            ctl.push(loops.length - 1);
            inner = loops.length - 1;
        } else if (op === OP.end && ctl.length) {
            const c = ctl.pop();
            if (c !== null) inner = loops[c].parent;
        }
    }
    return { instrs, loops };
}

function segments(instrs) {
    const segs = [];
    for (let i = 0; i < instrs.length; i++) {
        if (i === 0 || SPLIT_AFTER.has(instrs[i - 1].op)) segs.push({ first: i, last: i, loop: instrs[i].loop });
        else segs[segs.length - 1].last = i;
    }
    return segs;
}

// k = index into m.bodies (defined function k is function index numImportedFuncs + k).
export function decodeFunction(m, k) {
    const fi = m.numImportedFuncs + k, body = m.bodies[k];
    const r = new Reader(m.buf, body.start);
    const localDecls = readLocals(r);
    const localsEnd = r.pos;
    const { instrs, loops } = walk(r, body.end);
    const numParams = funcType(m, fi).params.length;
    const numLocals = numParams + localDecls.reduce((s, [n]) => s + n, 0);
    return { k, fi, name: funcName(m, fi), body, localDecls, localsEnd, numLocals, instrs, loops, segs: segments(instrs) };
}
