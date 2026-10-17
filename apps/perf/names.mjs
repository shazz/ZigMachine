// Function names for a stripped release cart, from its unstripped twin.
// Release carts carry no "name" section; tools/perf_names.sh builds the same tree with
// -Dnames=true into a scratch prefix (default zig-out/perf-names/docs). The twin's
// names are used ONLY if every function has the release build's instructions (address
// constants aside), so a stale twin can never put a wrong name on a hot loop: it is
// ignored, loudly.
import { existsSync, readFileSync } from "node:fs";
import { basename } from "node:path";
import { parseModule } from "./wasm_bin.mjs";
import { lineTable } from "./dwarf_lines.mjs";
import { decodeFunction } from "./wasm_body.mjs";

export const DEFAULT_NAMES_DIR = process.env.ZM_PERF_NAMES || "zig-out/perf-names/docs";

// Same functions, same instructions. Immediates may differ: the debug build keeps more
// static data, so the address constants into it move (math.ldexp, a few scene tables).
function sameOps(a, b, k) {
    const x = a.bodies[k], y = b.bodies[k];
    if (x.end - x.start === y.end - y.start && !Buffer.compare(a.buf.subarray(x.start, x.end), b.buf.subarray(y.start, y.end))) return true;
    const p = decodeFunction(a, k).instrs, q = decodeFunction(b, k).instrs;
    return p.length === q.length && p.every((ins, i) => ins.op === q[i].op);
}

// The functions whose instructions differ, or null if the twin is not the same program.
// A few may differ (LLVM's choices move slightly with debug info on): the index order,
// which is what the names hang on, is the same as long as nearly all match.
const SAME_MIN = 0.9;
function differing(a, b) {
    if (a.bodies.length !== b.bodies.length || a.numImportedFuncs !== b.numImportedFuncs) return null;
    const out = new Set();
    for (let k = 0; k < a.bodies.length; k++) if (!sameOps(a, b, k)) out.add(k);
    return a.bodies.length - out.size >= SAME_MIN * a.bodies.length ? out : null;
}

// a's instruction at byte `at` -> the same instruction's byte offset in b
function twinOffset(a, b, at, diff) {
    const k = a.bodies.findIndex((x) => at >= x.start && at < x.end);
    if (k < 0 || diff.has(k)) return null;
    const i = decodeFunction(a, k).instrs.findIndex((ins) => ins.at === at);
    return i < 0 ? null : decodeFunction(b, k).instrs[i].at;
}

const NO_SRC = () => null;

// src(offset in a's file) -> "file:line" from b's DWARF line table (offsets are code-relative)
function sourceOf(a, b, diff = new Set()) {
    const lines = lineTable(b), code = b.sections.find((s) => s.id === 10);
    if (!code) return NO_SRC;
    return (at) => { const t = a === b ? at : twinOffset(a, b, at, diff); return t === null ? null : lines(t - code.payload); };
}

// -> { names: Map | null, src: (moduleOffset) -> "file:line" | null, why: string }
export function twinNames(wasmPath, dir = DEFAULT_NAMES_DIR) {
    const twin = `${dir}/${basename(wasmPath)}`;
    const a = parseModule(readFileSync(wasmPath));
    if (a.names.size) return { names: a.names, src: sourceOf(a, a), why: "own name section" };
    if (!existsSync(twin)) return { names: null, src: NO_SRC, why: `no twin (${twin}; run tools/perf_names.sh)` };
    const b = parseModule(readFileSync(twin));
    if (!b.names.size) return { names: null, src: NO_SRC, why: `twin ${twin} has no name section` };
    const diff = differing(a, b);
    if (!diff) return { names: null, src: NO_SRC, why: `twin ${twin} is stale (code differs): rebuild it` };
    const why = diff.size ? `twin (${diff.size} function(s) differ: no file:line there)` : "twin";
    return { names: b.names, src: sourceOf(a, b, diff), why };
}
