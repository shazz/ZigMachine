// Text rendering of frame_cost results (one cart, and the --all ranking).
const pad = (s, n) => String(s).padEnd(n);
const lpad = (s, n) => String(s).padStart(n);
// Zig generic instances carry their arguments in the name: keep the function, drop those.
export const short = (name) => String(name).replace(/\((?:[^()]|\([^()]*\))*\)/g, "(..)");

export function topCause(r) {
    const c = Object.entries(r.causes).filter(([k]) => k !== "integer" && k !== "fresco").sort((a, b) => b[1] - a[1])[0];
    const hot = r.hot[0];
    const where = hot ? `${short(hot.func)}${hot.loop >= 0 ? " loop@" + hot.at : ""}` : "-";
    if (!c || c[1] < 10) return `integer code (${r.causes.integer ?? 0}%), hottest ${where} [${hot?.cause ?? "-"}]`;
    return `${c[0]} ${c[1]}%, hottest ${where} [${hot?.cause ?? "-"}]`;
}

export function printOne(r, out = console.log) {
    out(`${r.cart}: est ${r.mc.avg} Mc/frame (p95 ${r.mc.p95}, max ${r.mc.max}) = ${r.budget}% of a 60 Hz frame at 100 MHz, ~${r.fps} fps`);
    out(`  ESTIMATE from wasm op counts x apps/perf/cost_model.mjs; frames ${r.warmup + 1}..${r.warmup + r.frames}; names: ${r.namesWhy}`);
    out(`  split Mc: cart ${r.split.cart}, rom ${r.split.rom}, I$ misses ${r.split.icache}, CHISEL wait ${r.split.blit} (${r.blits} blits/frame, units by op ${r.blitUnits.slice(1).join("/")}), HBL entry ${r.split.hbl} (${r.hbls}/frame), FRESCO ${r.split.fresco}`);
    out(`  code run per frame: ~${r.codeKB} KB of rv32 (I$ 16 KB)`);
    out(`  causes %: ${Object.entries(r.causes).map(([k, v]) => `${k} ${v}`).join(", ")}`);
    out(`  per frame: ${Object.entries(r.classes).filter(([, v]) => v).map(([k, v]) => `${k} ${v}`).join(", ")}`);
    if (Object.keys(r.libm).length) out(`  libm calls/frame: ${Object.entries(r.libm).map(([k, v]) => `${k} ${v}`).join(", ")}`);
    if (r.palette.writes) out(`  palette stores/frame: ${r.palette.writes}, ${r.palette.unchanged} of them rewrite the colour already there`);
    for (const c of r.clears) out(`  big fill ${c.mod}:${c.func} ${c.len} B ${c.perFrame}/frame, ${c.overwritten}% overwritten later in the frame${c.wasted ? "  <- cleared then redrawn" : ""}`);
    out(`  hot regions (Mc/frame, iterations/frame, cause):`);
    for (const h of r.hot) out(`    ${lpad(h.mc, 6)}  ${lpad(h.iters, 8)}  ${pad(h.mod + ":" + short(h.func), 52)} ${h.loop >= 0 ? "loop@" + h.at : "body@" + h.at}  ${h.cause}`);
}

export function printRanking(rows, out = console.log) {
    out(`${pad("cart", 26)} ${lpad("est Mc", 7)} ${lpad("fps", 5)}  top cause`);
    for (const r of rows) {
        if (r.error) { out(`${pad(r.tag, 26)} ${lpad("ERR", 7)} ${lpad("-", 5)}  ${r.error}`); continue; }
        out(`${pad(r.tag, 26)} ${lpad(r.mc.avg, 7)} ${lpad(r.fps, 5)}  ${topCause(r)}`);
    }
}
