// RACER M6 perf pass, the ESTIMATE half (docs/ports/kestrel_racing/M6.md): the views the board fps table is taken on, per
// track and POV, on the plain multiply twin (frame_cost bills the ZM-X import as a ROM call: an upper bound), CPU fill unless
// --affine. Not in the gate (the board decides; this says where to look, and frame_cost is ~2x pessimistic on this cart:
// the oval's flyby at 1.82 Mc p95 runs 60 fps at R 8 on the board).
//   node apps/harness/racer_m6_costs.mjs [--r 8] [--tracks 0,2,3,4] [--affine] [--haze off] [--frames 20]
// RACER_WASM / RACER_ZMD pick another cart / disk (a baseline build, the LOCAL 32X disk: tracks 5.. are its DX courses).
// Mid-race cells are not like-for-like between builds: frame_cost drops VBLs by cost, so the race 600 frames in differs.
// Rows: the flyby lap (720 frames), the race at the grid (8 cars, before the start) and mid-race (frame ~600 after s, the AI
// pilot driving) in each POV (v: far, near, cockpit). Mean / p95 Mc.
import { costOf, parseArgs } from "./frame_cost.mjs";

const CART = process.env.RACER_WASM || "site/carts/demo-racer.wasm";
const DISK = process.env.RACER_ZMD || "site/carts/demo-racer.zmd";
const argv = process.argv.slice(2);
const opt = (n, d) => (argv.includes(n) ? argv[argv.indexOf(n) + 1] : d);
const R = Number(opt("--r", 8)), FRAMES = Number(opt("--frames", 20));
const TRACKS = opt("--tracks", "0,2,3,4").split(",").map(Number);
const AFFINE = argv.includes("--affine"), HAZE_OFF = opt("--haze", "on") === "off";
const NAMES = ["oval", "city", "salt", "neon", "glacier", "dx1", "dx2", "dx3", "dx4", "dx5"];
const code = (c) => c.charCodeAt(0);

// keys at frame 1: n taps of t (track n), the plain twin, the fill, R, the haze; then the scene's own keys at frame 2
async function cost(n, scene, warmup, frames = FRAMES) {
    const k1 = [...Array.from({ length: n }, () => code("t")), code("m"), ...(AFFINE ? [code("f")] : []), code("0") + R, ...(HAZE_OFF ? [code("q")] : [])];
    const calls = [...k1.map((k) => `1:key:${k}`), ...scene.map((k) => `2:key:${k}`)];
    const o = parseArgs([CART, "--frames", String(frames), "--warmup", String(warmup), "--disk", DISK, "--top", "400", ...calls.flatMap((c) => ["--call", c])]);
    return costOf(CART, o);
}

// the model's total (mean / p95) and, after "|", the same frame without the I$ term (cart + blit + HBL + FRESCO): the board
// has run this cart near that figure, not the total (M3: 60 fps where the total said 33; M6.md)
const noI = (r) => r.split.cart + r.split.rom + r.split.blit + r.split.hbl + r.split.fresco;
const cell = (r) => `${r.mc.avg.toFixed(2)} / ${r.mc.p95.toFixed(2)} | ${noI(r).toFixed(2)}`;

// --hot <track>:<scene>: the top functions of one view (needs the names twin, tools/perf_names.sh), scene = flyby | grid |
// mid, then the POV's v taps: e.g. --hot 4:grid0 (Glacier, the grid, far), --hot 5:mid1 (DXFOREST mid-race, near)
const HOT = opt("--hot", null);
if (HOT) {
    const [n, sc] = HOT.split(":");
    const pov = Number(sc.slice(-1)) || 0, kind = sc.replace(/\d$/, "");
    const keys = kind === "flyby" ? [code("l")] : [code("e"), ...Array.from({ length: pov }, () => code("v")), ...(kind === "mid" ? [code("s")] : [])];
    const r = await cost(Number(n), keys, kind === "mid" ? 600 : 30);
    console.log(`${NAMES[n]} ${sc}: ${cell(r)} Mc; split ${JSON.stringify(r.split)}; names: ${r.namesWhy}`);
    for (const h of r.hot.slice(0, Number(opt("--top-n", 25)))) console.log(`  ${h.mc.toFixed(3)} Mc  ${h.mod}  ${h.func}  ${JSON.stringify(h.src ?? "")} ${h.iters ?? ""}`);
    process.exit(0);
}
console.log(`cart ${CART}, R ${R}, ${AFFINE ? "AFFINE" : "CPU"} fill, haze ${HAZE_OFF ? "off" : "on"}; mean / p95 Mc | mean without the I$ term\n`);
console.log("| track | flyby lap | grid far | grid near | grid cockpit | mid-race far | mid-race near | mid-race cockpit |\n|---|---|---|---|---|---|---|---|");
for (const n of TRACKS) {
    const row = [cell(await cost(n, [code("l")], 6, 720))];
    for (const go of [false, true]) {
        for (let pov = 0; pov < 3; pov++) {
            const keys = [code("e"), ...Array.from({ length: pov }, () => code("v")), ...(go ? [code("s")] : [])];
            row.push(cell(await cost(n, keys, go ? 600 : 30)));
        }
    }
    console.log(`| ${NAMES[n]} | ${row.join(" | ")} |`);
}
