// Tests for the perf suite (apps/perf_audit.mjs, apps/frame_cost.mjs): every detector
// on a tiny cart with its pattern planted in frame() and on the clean twin, statically
// and, for the dynamic findings, through a real run on the machine. The two patterns
// the board tour paid for most -- a byte-loop plane clear and an f64 loop -- must also
// come out hot, ranked first, at their modelled cost.
//
//   node apps/perf_audit_test.mjs                    all checks; exit 1 on a failure
//   node apps/perf_audit_test.mjs --break bytefill   frame() gets the clean twin where the
//   node apps/perf_audit_test.mjs --break f64        byte-loop clear / f64 loop was planted:
//                                                    passes only if the checks catch it
import { mkdtempSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { CASES } from "./perf/test_cases.mjs";
import { cart } from "./perf/fixture.mjs";
import { lintModule } from "./perf/lint.mjs";
import { parseArgs } from "./frame_cost.mjs";
import { auditCart } from "./perf_audit.mjs";

const bi = process.argv.indexOf("--break");
const broke = bi > 0 ? process.argv[bi + 1] : null;
const BREAKS = { bytefill: "byte_fill", f64: "f64_loop" };
if (broke && !BREAKS[broke]) throw new Error(`--break ${Object.keys(BREAKS).join(" | ")}`);

const dir = mkdtempSync(`${tmpdir()}/perf_audit_test-`);
const failed = [];
const check = (name, ok, why) => { console.log(`${ok ? "ok  " : "FAIL"} ${name}${ok ? "" : ": " + why}`); if (!ok) failed.push(name); };

async function audit(name, bytes) {
    const path = `${dir}/demo-${name}.wasm`;
    writeFileSync(path, bytes);
    return auditCart(path, parseArgs([path, "--warmup", "2", "--frames", "4", "--no-disk", "--names", dir]));
}

for (const c of CASES) {
    const planted = broke && BREAKS[broke] === c.pattern ? c.without : c.with; // --break: the pattern removed
    const withB = cart(planted, c.opts), withoutB = cart(c.without, c.opts);
    const want = c.lintAs ?? c.pattern;
    if (!c.dynamicOnly) {
        check(`${c.pattern}: static finds it`, lintModule(withB).some((f) => f.pattern === want), `no ${want} finding`);
        check(`${c.pattern}: static, clean twin`, !lintModule(withoutB).some((f) => f.pattern === want), `${want} reported`);
    }
    if (!c.dynamic) continue;
    const a = await audit(`${c.pattern}_with`, withB), b = await audit(`${c.pattern}_without`, withoutB);
    const hit = a.findings.find((f) => f.pattern === c.dynamic && f.status === "hot");
    check(`${c.pattern}: dynamic, hot`, !!hit, `no hot ${c.dynamic}: ${JSON.stringify(a.findings.slice(0, 2))}`);
    check(`${c.pattern}: dynamic, clean twin`, !b.findings.some((f) => f.pattern === c.dynamic && f.status === "hot"), `${c.dynamic} hot in the twin`);
    if (c.first) check(`${c.pattern}: ranked first`, a.findings[0]?.pattern === c.dynamic, `first is ${a.findings[0]?.pattern}`);
    if (c.mc) check(`${c.pattern}: ${c.mc[0]}..${c.mc[1]} Mc/frame`, hit && hit.mc >= c.mc[0] && hit.mc <= c.mc[1], `${hit?.mc} Mc`);
    if (c.cause) check(`${c.pattern}: cause ${c.cause}`, (a.causes[c.cause] ?? 0) >= 50, JSON.stringify(a.causes));
    if (c.pattern === "byte_fill") {
        const twice = await audit(`${c.pattern}_again`, withB);
        check("deterministic: same counts twice", JSON.stringify(twice.classes) === JSON.stringify(a.classes)
            && twice.mc.avg === a.mc.avg, "the counts moved between two runs");
    }
}
rmSync(dir, { recursive: true, force: true });

if (broke) {
    const caught = failed.some((n) => n.startsWith(BREAKS[broke]));
    console.log(caught ? `--break ${broke}: caught (${failed.length} check(s) failed, as they must)` : `--break ${broke}: NOT caught`);
    process.exit(caught ? 0 : 1);
}
console.log(failed.length ? `perf_audit_test: ${failed.length} FAILED` : "perf_audit_test: all checks passed");
process.exit(failed.length ? 1 : 0);
