// GEM 5 step 1's cost probe (gem_engine_check.mjs "cost"): apps/frame_cost.mjs on demo-gem.wasm in
// the desk mode with A:\ open and the pointer moving every measured frame, on the old ZigGEM path
// and on the engine. The gesture that gets there is recorded from the harness helpers into
// frame_cost's --call specs (pointer frames), so both runs replay the same session.
import { mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { execFileSync } from "node:child_process";
import { pickRes } from "./gem_desk_lib.mjs";
import { costOf, parseArgs } from "./frame_cost.mjs";

const CART = "docs/demo-gem.wasm";
const BAND_MC = 1.75; // the board's 60 fps band starts here (CLAUDE.md, Board speed)
const FRAMES = 30;

// Records what a session does as frame_cost --call specs (calls of frame f run before frame f).
class Rec {
    constructor() { this.f = 2; this.calls = ["1:insertDisk:2"]; }
    point(x, y, b) { this.calls.push(`${this.f}:pointer:${x},${y},${b}`); this.f++; }
    frame() { this.f++; }
    click(x, y) { this.point(x, y, 0); this.point(x, y, 1); this.point(x, y, 0); }
    open(x, y) { this.point(x, y, 0); this.point(x, y, 2); this.point(x, y, 0); }
}

function session(engine) {
    const r = new Rec();
    for (let i = 0; i < 30; i++) r.frame(); // the desktop settles and the disk's listing arrives
    pickRes(r, (x, y) => r.click(2 * x, y), "medium", 320, 200);
    pickRes(r, (x, y) => r.click(x, y), "desk", 640, 200);
    r.open(35, 40);
    for (let i = 0; i < 10; i++) r.frame();
    if (engine) r.calls.push(`${r.f}:rom.deskSetEngine:1`);
    for (let i = 0; i < 6; i++) r.frame();
    const warmup = r.f;
    for (let i = 0; i < FRAMES; i++) r.point(300 + 7 * (i % 20), 300 + (i & 1), 0); // never still
    return { warmup, calls: r.calls };
}

function floppy() { // two files on A:\ (tools/kos_fat_fixture.py, as kos_desk_check's floppy)
    const dir = mkdtempSync(join(tmpdir(), "gem-engine-")), out = join(dir, "a.st"), prg = join(dir, "alpha.prg");
    writeFileSync(prg, Buffer.alloc(12345));
    execFileSync("python3", ["tools/kos_fat_fixture.py", out, prg]);
    return out;
}

export async function measureBoth() {
    const disk = floppy(), out = {};
    for (const [name, engine] of [["old", false], ["engine", true]]) {
        const s = session(engine);
        const args = ["--warmup", String(s.warmup - 1), "--frames", String(FRAMES), "--disk", disk];
        for (const c of s.calls) args.push("--call", c);
        out[name] = (await costOf(CART, parseArgs(args))).mc;
    }
    return out;
}

// node apps/gem_engine_cost.mjs old|engine   the frame_cost report (hot spots) of one of the two runs
if (process.argv[1]?.endsWith("gem_engine_cost.mjs")) {
    const { printOne } = await import("./perf/print.mjs");
    const s = session(process.argv[2] === "engine");
    const args = ["--warmup", String(s.warmup - 1), "--frames", String(FRAMES), "--disk", floppy(), "--top", "25"];
    for (const c of s.calls) args.push("--call", c);
    printOne(await costOf(CART, parseArgs(args)));
}

export async function cost() {
    const r = await measureBoth(), fails = [];
    console.log(`cost: A:\\ open in the desk, the pointer moving every frame: old path ${r.old.avg} Mc (p95 ${r.old.p95}), engine ${r.engine.avg} Mc (p95 ${r.engine.p95})`);
    if (!(r.engine.avg < BAND_MC)) fails.push(`cost: the engine costs ${r.engine.avg} Mc a frame (60 fps band: < ${BAND_MC})`);
    if (!(r.engine.avg < r.old.avg)) fails.push(`cost: the engine (${r.engine.avg} Mc) is not cheaper than the old path (${r.old.avg} Mc)`);
    return fails;
}
