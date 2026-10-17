// frame_cost: estimate what a cart costs per frame on KESTREL's cart CPU (ZIGGY, rv32imf
// at 100 MHz, f32-only FPU, write-through D$ behind an 8-entry store buffer) WITHOUT a
// Verilator sim. It instruments the cart and the ROM wasm (a counter per straight-line
// segment, byte counters on memory.fill/copy, palette-store checks), runs the REAL cart
// like apps/scene_hash.mjs for warmup + N frames, and turns the exact op counts into an
// ESTIMATE of Mc/frame with apps/perf/cost_model.mjs (calibrated on board numbers).
//
//   node apps/frame_cost.mjs <cart.wasm> [--frames 60] [--warmup 120] [--top 10]
//        [--call F:export:args]... [--disk X.zmd | --no-disk] [--json] [--no-pal] [--names DIR]
//        [--machine DIR]  (machine-video.wasm + rom.wasm; default $MACHINE_DIR or docs)
//   node apps/frame_cost.mjs --all [--jobs 4] [--json] [--top-n 20] [--out F.json]
//        every docs/demo-<tag>.wasm with a disk, ranked by est. Mc/frame (other options forwarded)
//
// Counts are deterministic (fixed dt, no wall clock): the same cart gives the same numbers.
// The disk defaults to docs/demo-<tag>.zmd when it exists (the browser boots a cart from it).
import { existsSync } from "node:fs";
import { basename, resolve } from "node:path";
import { pathToFileURL, fileURLToPath } from "node:url";
import { measure } from "./perf/measure.mjs";
import { twinNames, DEFAULT_NAMES_DIR } from "./perf/names.mjs";
import { printOne } from "./perf/print.mjs";
import { runAll } from "./perf/run_all.mjs";

// option -> [takes a value, set(o, value), forwarded to each cart's child under --all]
const OPTIONS = {
    "--frames": [true, (o, v) => { o.frames = Number(v); }, true],
    "--warmup": [true, (o, v) => { o.warmup = Number(v); }, true],
    "--top": [true, (o, v) => { o.top = Number(v); }, true],
    "--call": [true, (o, v) => { o.callSpecs.push(v); }, true],
    "--disk": [true, (o, v) => { o.disk = v; }, true],
    "--no-disk": [false, (o) => { o.disk = null; }, true],
    "--names": [true, (o, v) => { o.namesDir = v; }, true],
    "--machine": [true, (o, v) => { o.machineDir = v; }, true],
    "--no-pal": [false, (o) => { o.pal = false; }, true],
    "--json": [false, (o) => { o.json = true; }, false],
    "--all": [false, (o) => { o.all = true; }, false],
    "--jobs": [true, (o, v) => { o.jobs = Number(v); }, false],
    "--top-n": [true, (o, v) => { o.topN = Number(v); }, false],
    "--out": [true, (o, v) => { o.out = v; }, false],
};

export function parseArgs(argv) {
    const o = { frames: 60, warmup: 120, top: 10, callSpecs: [], disk: "auto", json: false, pal: true,
        namesDir: DEFAULT_NAMES_DIR, machineDir: process.env.MACHINE_DIR || "docs", all: false, jobs: 4, topN: 20,
        out: null, pos: [], pass: [] };
    for (let i = 0; i < argv.length; i++) {
        const a = argv[i], spec = OPTIONS[a];
        if (!spec && a.startsWith("--")) throw new Error(`frame_cost: unknown option ${a}`);
        if (!spec) { o.pos.push(a); continue; }
        const [hasValue, set, forward] = spec;
        const v = hasValue ? argv[++i] : undefined;
        if (hasValue && v === undefined) throw new Error(`frame_cost: ${a} needs a value`);
        set(o, v);
        if (forward) o.pass.push(a, ...(hasValue ? [v] : []));
    }
    if (!(o.frames > 0) || !(o.warmup >= 0)) throw new Error("frame_cost: --frames must be > 0, --warmup >= 0");
    return o;
}

function parseCalls(list) {
    const calls = new Map();
    for (const spec of list) {
        const [f, name, args = ""] = spec.split(":");
        if (!name || !(Number(f) > 0)) throw new Error(`frame_cost: bad --call ${spec} (want F:export[:a,b])`);
        if (!calls.has(Number(f))) calls.set(Number(f), []);
        calls.get(Number(f)).push([name, args === "" ? [] : args.split(",").map(Number)]);
    }
    return calls;
}

// keep: also return the Profiles and the cart's names (perf_audit cross-checks with them).
export async function costOf(cart, o, keep = false) {
    const tag = basename(cart).replace(/^demo-/, "").replace(/\.wasm$/, "");
    const disk = o.disk === "auto" ? (existsSync(cart.replace(/\.wasm$/, ".zmd")) ? cart.replace(/\.wasm$/, ".zmd") : null) : o.disk;
    const cn = twinNames(cart, o.namesDir), rn = twinNames(`${o.machineDir}/rom.wasm`, o.namesDir);
    const r = await measure(cart, { ...o, calls: parseCalls(o.callSpecs), disk,
        names: { cart: cn.names, rom: rn.names } });
    if (keep) r.cartNames = cn.names;
    else delete r.profiles;
    return { tag, ...r, disk, namesWhy: `cart ${cn.why}, rom ${rn.why}` };
}

async function main() {
    const o = parseArgs(process.argv.slice(2));
    if (o.all) return runAll(o, fileURLToPath(import.meta.url), o.pass);
    if (o.pos.length !== 1) throw new Error("usage: node apps/frame_cost.mjs <cart.wasm> [options] | --all");
    const r = await costOf(o.pos[0], o);
    if (o.json) console.log(JSON.stringify(r));
    else printOne(r);
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
    main().catch((e) => { console.error(e.stack ?? e.message); process.exit(2); });
}
