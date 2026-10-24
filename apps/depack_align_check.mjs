// The depack loaders make no misaligned wide access. Why: on the board's `aligned` build a wide
// load or store at a misaligned address TRAPS (~210 cycles, emulated byte by byte), and the TEX
// loader (libs/zig/depackers/tex_loader.zig) copied each glyph out of a 2-mod-4 table in one
// i64 load: ~440 traps a loading frame in every Union screen for months (2026-10-24 fix).
// Each cart below loads with a depack effect; its loading window is run through frame_cost's
// instrumented machine, which counts the misaligned accesses really made (probe_hooks.mjs).
//
//   node apps/depack_align_check.mjs [--max N] [cart.wasm ...]
import { parseArgs, costOf } from "./frame_cost.mjs";

const argv = process.argv.slice(2);
const mi = argv.indexOf("--max");
const MAX = mi >= 0 ? Number(argv.splice(mi, 2)[1]) : 4; // a few one-off header reads per load are fine
// TEX loader (Union), Automation and plain depack users, each a different effect
const carts = argv.length ? argv : ["docs/demo-union_texcopier.wasm", "docs/demo-union_tnt2.wasm",
    "docs/demo-union_multifake.wasm", "docs/demo-union_deltaforce.wasm"];

let failed = false;
for (const cart of carts) {
    const r = await costOf(cart, parseArgs([cart, "--warmup", "0", "--frames", "120"]));
    const ok = r.misaligned <= MAX;
    console.log(`  ${ok ? "ok  " : "FAIL"} ${r.tag}: ${r.misaligned} misaligned wide accesses a frame while it loads (max ${MAX})`
        + (ok ? "" : `; sites (whole run): ${r.misSites.map((s) => `${s.mod}:${s.func} @${s.at} x${s.count}`).join(", ")}`));
    if (!ok) failed = true;
}
console.log(failed ? "depack_align_check: FAIL ❌ a loader makes misaligned accesses (each traps on the board)"
    : "depack_align_check: PASS ✅ the depack loaders make no misaligned access");
process.exit(failed ? 1 : 0);
