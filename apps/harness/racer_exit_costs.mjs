// RACER M5 exit test, the ESTIMATE half (docs/ports/kestrel_racing/M5.md "M5 finish"; PORT_PLAN's M5 row: each shipped
// track's bench lap, its 5 heaviest poses included, >= 60 fps on the board at the track's R). Not in the gate (the board
// decides; this says where to look). For each shipped track (n taps of t from the oval on the shelf disk: 0 OVAL, 1 CITY,
// 2 SALT, 3 NEON, 4 GLACIER): the whole flyby lap (lap v0, 720 frames) at R, mean and worst frame, and each of the
// walk's 5 heaviest poses (tools/racer/tracks/<name>.heavy.json) at R, on the plain multiply twin, CPU and AFFINE fill.
// 1.67 Mc is a 60 Hz frame at 100 MHz; the board drops below 60 fps between ~1.75 and 2.1 Mc (CLAUDE.md, apps/frame_cost.mjs)
// and has run this cart's scenes faster than the model says (M3.md).
//   node apps/harness/racer_exit_costs.mjs [--r 8] [--tracks 0,1,2,3,4]
import { readFileSync } from "node:fs";
import { costOf, parseArgs } from "./frame_cost.mjs";

const CART = "site/carts/demo-racer.wasm";
const argv = process.argv.slice(2);
const opt = (n, d) => (argv.includes(n) ? argv[argv.indexOf(n) + 1] : d);
const R = Number(opt("--r", 8));
const TRACKS = opt("--tracks", "0,1,2,3,4").split(",").map(Number);
const NAMES = ["oval", "city", "salt_flats", "neon_docks", "glacier_pass"];
const code = (c) => c.charCodeAt(0);

async function cost(n, frames, warmup, affine) {
    const keys = [...Array.from({ length: n }, () => code("t")), code("l"), code("m"), ...(affine ? [code("f")] : []), code("0") + R];
    const o = parseArgs([CART, "--frames", String(frames), "--warmup", String(warmup), "--disk", process.env.RACER_ZMD || "site/carts/demo-racer.zmd",
        "--top", "400", ...keys.flatMap((k) => ["--call", `1:key:${k}`])]);
    return costOf(CART, o);
}

const cell = (r) => `${r.mc.avg.toFixed(2)} / ${r.mc.p95.toFixed(2)} Mc`; // p95: the max is the bench report's once-a-second frame (the oval's too)
console.log(`| track | scene (R = ${R}) | CPU fill avg / p95 | AFFINE fill avg / p95 |\n|---|---|---|---|`);
for (const n of TRACKS) {
    const name = NAMES[n];
    const lap = [await cost(n, 720, 6, false), await cost(n, 720, 6, true)]; // warmup 6: past the frame the keys load the track on
    console.log(`| ${name} | the flyby lap (720 frames) | ${cell(lap[0])} | ${cell(lap[1])} |`);
    let heavy = [];
    try {
        heavy = JSON.parse(readFileSync(`tools/racer/tracks/${name}.heavy.json`, "utf8")).frames;
    } catch {
        heavy = []; // the oval and the city have no walk list (M1's fixed poses cover them: racer_vr_costs.mjs)
    }
    for (const h of heavy) {
        const a = await cost(n, 3, h + 1, false), b = await cost(n, 3, h + 1, true);
        console.log(`| ${name} | heavy pose, frame ${h} | ${cell(a)} | ${cell(b)} |`);
    }
}
