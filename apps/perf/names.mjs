// Function names for a stripped release cart, from its unstripped twin.
// Release carts carry no "name" section; tools/perf_names.sh builds the same tree with
// -Dnames=true into a scratch prefix (default zig-out/perf-names/docs). The twin's
// names are used ONLY if every function body is byte-identical to the release build's,
// so a stale twin can never put a wrong name on a hot loop: it is ignored, loudly.
import { existsSync, readFileSync } from "node:fs";
import { basename } from "node:path";
import { parseModule } from "./wasm_bin.mjs";

export const DEFAULT_NAMES_DIR = process.env.ZM_PERF_NAMES || "zig-out/perf-names/docs";

function sameCode(a, b) {
    if (a.bodies.length !== b.bodies.length || a.numImportedFuncs !== b.numImportedFuncs) return false;
    for (let k = 0; k < a.bodies.length; k++) {
        const x = a.bodies[k], y = b.bodies[k];
        if (x.end - x.start !== y.end - y.start) return false;
        if (Buffer.compare(a.buf.subarray(x.start, x.end), b.buf.subarray(y.start, y.end))) return false;
    }
    return true;
}

// -> { names: Map | null, why: string }
export function twinNames(wasmPath, dir = DEFAULT_NAMES_DIR) {
    const twin = `${dir}/${basename(wasmPath)}`;
    const a = parseModule(readFileSync(wasmPath));
    if (a.names.size) return { names: a.names, why: "own name section" };
    if (!existsSync(twin)) return { names: null, why: `no twin (${twin}; run tools/perf_names.sh)` };
    const b = parseModule(readFileSync(twin));
    if (!b.names.size) return { names: null, why: `twin ${twin} has no name section` };
    if (!sameCode(a, b)) return { names: null, why: `twin ${twin} is stale (code differs): rebuild it` };
    return { names: b.names, why: "twin" };
}
