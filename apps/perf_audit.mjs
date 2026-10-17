// perf_audit: the bad-pattern suite for KESTREL. Static detectors over the cart's wasm
// (apps/perf/lint.mjs) cross-checked with a dynamic run (apps/frame_cost.mjs): a pattern
// in code that runs hot every frame ranks first by its measured Mc/frame, one that never
// ran in the steady-state window is downgraded to "cold". Each finding: function +
// byte offset, pattern, measured cost, and a one-line fix.
//
//   node apps/perf_audit.mjs <cart.wasm> [frame_cost options] [--json] [--findings N]
//   node apps/perf_audit.mjs --all [--jobs 4] [--out F.json] [--top-n 20]
// (tools/perf_audit.sh is the entry point; it also writes the JSON.)
import { readFile } from "node:fs/promises";
import { resolve } from "node:path";
import { pathToFileURL, fileURLToPath } from "node:url";
import { parseArgs, costOf } from "./frame_cost.mjs";
import { crossCheck } from "./perf/audit.mjs";
import { runAll } from "./perf/run_all.mjs";
import { topCause, short } from "./perf/print.mjs";

const pad = (s, n) => String(s).padEnd(n);

export async function auditCart(cart, o) {
    const dyn = await costOf(cart, o, true);
    const findings = crossCheck(dyn, await readFile(cart), dyn.cartNames);
    for (const f of findings) f.src = f.mod === "cart" && f.at !== "-" ? dyn.cartSrc(parseInt(f.at, 16)) : null;
    delete dyn.profiles; delete dyn.cartNames; delete dyn.cartSrc;
    return { ...dyn, findings };
}

export function printAudit(r, n, out = console.log) {
    out(`${r.tag}: est ${r.mc.avg} Mc/frame (p95 ${r.mc.p95}) ~${r.fps} fps on ZIGGY (ESTIMATE, apps/perf/cost_model.mjs); ${topCause(r)}`);
    const shown = r.findings.filter((f) => f.status !== "cold").slice(0, n);
    const cold = r.findings.filter((f) => f.status === "cold").length;
    if (!shown.length) out("  no per-frame finding");
    for (const [i, f] of shown.entries())
        out(`  ${String(i + 1).padStart(2)}. ${pad(f.status, 9)} ${String(f.mc).padStart(6)} Mc  ${pad(f.pattern, 24)} `
            + `${short(f.func)} ${f.loop >= 0 ? "loop@" : "@"}${f.at}${f.src ? " (" + f.src + ")" : ""}: ${f.detail}\n      fix: ${f.hint}`);
    if (cold) out(`  (${cold} static finding(s) in code that did not run in frames ${r.warmup + 1}..${r.warmup + r.frames}: --json lists them)`);
}

function printRanking(rows, out = console.log) {
    out(`${pad("cart", 24)} ${"est Mc".padStart(7)} ${"fps".padStart(5)}  first finding`);
    for (const r of rows) {
        if (r.error) { out(`${pad(r.tag, 24)} ${"ERR".padStart(7)}        ${r.error}`); continue; }
        const f = r.findings.find((x) => x.status === "hot");
        const what = f ? `${f.pattern} in ${short(f.func)} (${f.mc} Mc)` : topCause(r);
        out(`${pad(r.tag, 24)} ${String(r.mc.avg).padStart(7)} ${String(r.fps).padStart(5)}  ${what}`);
    }
}

async function main() {
    const argv = process.argv.slice(2);
    const fi = argv.indexOf("--findings");
    const nFind = fi >= 0 ? Number(argv.splice(fi, 2)[1]) : 8;
    const o = parseArgs(argv);
    if (o.all) return runAll(o, fileURLToPath(import.meta.url), o.pass, printRanking);
    if (o.pos.length !== 1) throw new Error("usage: node apps/perf_audit.mjs <cart.wasm> [options] | --all");
    const r = await auditCart(o.pos[0], o);
    if (o.json) console.log(JSON.stringify(r));
    else printAudit(r, nFind);
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
    main().catch((e) => { console.error(e.stack ?? e.message); process.exit(2); });
}
