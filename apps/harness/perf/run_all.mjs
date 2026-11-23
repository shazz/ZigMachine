// --all: every docs/demo-<tag>.wasm that has a disk, one child process per cart (a cart
// that traps or loops cannot take the others down), `jobs` at a time, then a ranking.
import { execFile } from "node:child_process";
import { readdirSync, existsSync, writeFileSync } from "node:fs";
import { printRanking } from "./print.mjs";

// Carts whose steady state is behind a key (the browser's player would press it).
export const CART_ARGS = {
    joust: ["--warmup", "400", "--call", "100:key:49", "--call", "101:keyUp:49"], // '1': a game, not the title
};
const TIMEOUT_MS = 300000; // a cart that runs this long is reported, not waited for

export function shelf(dir = "docs") {
    return readdirSync(dir).filter((f) => /^demo-.+\.wasm$/.test(f) && existsSync(`${dir}/${f.replace(/\.wasm$/, ".zmd")}`))
        .map((f) => `${dir}/${f}`).sort();
}

function runOne(script, cart, passArgs) {
    const tag = cart.replace(/^.*demo-/, "").replace(/\.wasm$/, "");
    // PERF_NO_CART_ARGS=1: no scripted keys, as the board runs a cart unattended (calibration)
    const extra = process.env.PERF_NO_CART_ARGS ? [] : CART_ARGS[tag] ?? [];
    const args = [script, cart, "--json", ...passArgs, ...extra];
    return new Promise((resolve) => {
        execFile(process.execPath, args, { maxBuffer: 64 << 20, timeout: TIMEOUT_MS }, (err, stdout, stderr) => {
            if (err) return resolve({ tag, error: (stderr || err.message).trim().split("\n").pop().slice(0, 160) });
            try { resolve(JSON.parse(stdout)); } catch { resolve({ tag, error: "no JSON from the child" }); }
        });
    });
}

// o: parsed options (jobs, json, out, topN); script: the per-cart CLI; passArgs: forwarded
export async function runAll(o, script, passArgs = [], print = printRanking) {
    const carts = shelf(o.machineDir ?? "docs");
    const rows = [];
    let next = 0;
    const worker = async () => { while (next < carts.length) rows.push(await runOne(script, carts[next++], passArgs)); };
    await Promise.all(Array.from({ length: Math.max(1, o.jobs) }, worker));
    rows.sort((a, b) => (b.mc?.avg ?? -1) - (a.mc?.avg ?? -1));
    if (o.out) writeFileSync(o.out, JSON.stringify({ carts: rows.length, rows }, null, 1));
    if (o.json) console.log(JSON.stringify(rows));
    else print(rows, o.topN || rows.length);
    return rows;
}
