// RACER's frame-cost ESTIMATES on the disk's tracks (docs/ports/kestrel_racing/M5.md, M5_VR.md). Not in the gate. Track n is
// n taps of t from the oval in the disk's order (the shelf disk: 1 CITY, 2 SALT, 3 NEON, 4 GLACIER; a LOCAL disk built with
// RACER_EXTRA adds the decoded Virtua Racing tracks after them: RACER_ZMD=<that disk> to read it; it holds no track data itself):
//   node apps/harness/racer_vr_costs.mjs [--frames 20] [--warmup 30] [--tracks 2,3,4]
// For each track: the heaviest of the eight fixed poses at R = 5 and R = 8, and the race (lap v2 on the AI's pilot) at the
// start grid and mid-lap, on the plain multiply twin, CPU and AFFINE fill. 1.67 Mc is a 60 Hz frame at 100 MHz; the board
// drops below 60 fps between ~1.75 and 2.1 Mc, and beat this model by ~2x on the racer's M3 (docs/ports/kestrel_racing/M3.md).
import { costOf, parseArgs } from "./frame_cost.mjs";

const CART = "site/carts/demo-racer.wasm";
const argv = process.argv.slice(2);
const opt = (n, d) => (argv.includes(n) ? argv[argv.indexOf(n) + 1] : d);
const FRAMES = Number(opt("--frames", 20)), WARMUP = Number(opt("--warmup", 30));
const TRACKS = opt("--tracks", "2,3,4").split(",").map(Number);
const code = (c) => c.charCodeAt(0);
const row = (r) => `${r.mc.avg.toFixed(2)} Mc (cart ${r.split.cart.toFixed(2)}, max ${r.mc.max?.toFixed?.(2) ?? "?"}), ~${r.fps} fps`;

async function cost(vr, keys, warmup, { affine = false } = {}) {
    const taps = Array.from({ length: vr }, () => code("t")); // track n: n taps of t from the oval
    const ks = [...taps, code("m"), ...(affine ? [code("f")] : []), ...keys];
    const o = parseArgs([CART, "--frames", String(FRAMES), "--warmup", String(warmup), "--disk", process.env.RACER_ZMD || "site/carts/demo-racer.zmd", "--top", "400", ...ks.flatMap((k) => ["--call", `1:key:${k}`])]);
    return costOf(CART, o);
}

for (const n of TRACKS) {
    const vr = n;
    console.log(`\n## track ${n} (n taps of t; plain multiply twin, estimates)\n\n| scene | R | CPU fill | AFFINE fill |\n|---|---|---|---|`);
    let worst = { pose: 0, mc: 0 };
    for (let k = 0; k < 8; k++) {
        const r = await cost(vr, [code("5"), code("A") + k], 30);
        if (r.mc.avg > worst.mc) worst = { pose: k, mc: r.mc.avg };
    }
    for (const r of [5, 8]) {
        const a = await cost(vr, [code("0") + r, code("A") + worst.pose], 30), b = await cost(vr, [code("0") + r, code("A") + worst.pose], 30, { affine: true });
        console.log(`| heaviest pose ${"ABCDEFGH"[worst.pose]} (flyby) | ${r} | ${row(a)} | ${row(b)} |`);
    }
    for (const [name, warm] of [["race grid, 8 cars (lap v2 start)", 30], ["race mid-lap (AI ticking, pilot)", 700]]) {
        const a = await cost(vr, [code("x")], warm), b = await cost(vr, [code("x")], warm, { affine: true });
        console.log(`| ${name} | 5 (pinned) | ${row(a)} | ${row(b)} |`);
    }
}
