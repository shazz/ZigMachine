// Gate: the klystrack tracker cart's repaint cost (apps/frame_cost.mjs, est. board Mc; deterministic op counts,
// so a plain gate, not gate_timed). A repaint is what sets the board's fps while something moves.
//   playing   F5 plays STARPRT2.KT (handed to the machine's .kt player), frames 161..220: between two rows a
//             repaint redraws the VU meters and little else (round 4: views skipped when nothing they read
//             changed); on a row change the pattern rows scroll in their caches and one new row is drawn
//   menu      the right button held (klystron's menu bar open), the pointer moving every frame: the views
//             behind the menu are skipped, only the menu draws
//   both      playing with the menu open
// Round 4 (6 Nov 2026), est Mc: playing median 1.4, row change ~8 (worst ~10), mean ~2.0; menu 0.95; both mean
// ~2.5. Round 3: playing median 4.9 / worst 13.8, menu 3.2. The ceilings sit ~20-30 % above round 4's.
// A palette compaction (~35-80 Mc, when the 256 window colours fill up with VU gradient shades) is left out of
// the window on purpose: it comes every few hundred frames in both rounds. --break cost asks for 0 and must fail.
import { costOf, parseArgs } from "./frame_cost.mjs";

const CART = process.env.CART ?? "docs/demo-klystrack.wasm"; // CART=...: another build (a before/after)
const CEIL = { playMedian: 2, playRow: 13, playMean: 2.8, menuMax: 1.3, bothMean: 3.4 };
const broke = process.argv.includes("--break") ? process.argv[process.argv.indexOf("--break") + 1] : null;
if (broke && broke !== "cost") throw new Error("--break cost");
const scale = broke ? 0 : 1; // --break cost: every ceiling ~0

async function series(calls, warmup) {
    const args = [CART, "--disk", "docs/demo-klystrack.zmd", "--frames", "60", "--warmup", String(warmup), "--top", "1"];
    for (const c of calls) args.push("--call", c);
    const r = await costOf(CART, parseArgs(args));
    return r.mc.series ?? r.series;
}

const errors = [];
const check = (ok, msg) => { console.log(`  ${ok ? "ok  " : "FAIL"}  ${msg}`); if (!ok) errors.push(msg); };
const mean = (s) => +(s.reduce((a, b) => a + b, 0) / s.length).toFixed(2);
const F5 = ["30:key:57349", "33:keyUp:57349"];
const menuMoves = () => {
    const m = ["149:pointer:300,80,0", "150:pointer:300,80,4"];
    for (let f = 160; f <= 230; f++) m.push(`${f}:pointer:${300 + (f % 8) * 4},${80 + (f % 5)},4`);
    return m;
};

const play = await series(F5, 160);
const repaints = play.filter((mc) => mc > 1.2).sort((a, b) => a - b); // idle frames cost ~0.7 (FRESCO + frame)
const rows = play.filter((mc) => mc > 4);
check(repaints.length >= 20 && rows.length >= 4, `playing: ${repaints.length} repaints, ${rows.length} of them row changes`);
check(repaints[repaints.length >> 1] <= CEIL.playMedian * scale, `playing: median repaint ${repaints[repaints.length >> 1]} Mc <= ${CEIL.playMedian * scale}`);
check(Math.max(...rows) <= CEIL.playRow * scale, `playing: worst row change ${Math.max(...rows)} Mc <= ${CEIL.playRow * scale}`);
check(mean(play) <= CEIL.playMean * scale, `playing: mean ${mean(play)} Mc a frame <= ${CEIL.playMean * scale}`);

const menu = await series(menuMoves(), 165);
check(menu.every((mc) => mc > 0.8), "menu: every frame draws the menu (the pointer moves with the button held)");
check(Math.max(...menu) <= CEIL.menuMax * scale, `menu: worst repaint ${Math.max(...menu)} Mc <= ${CEIL.menuMax * scale}`);

const both = await series([...F5, ...menuMoves()], 165);
check(mean(both) <= CEIL.bothMean * scale, `playing + menu: mean ${mean(both)} Mc a frame <= ${CEIL.bothMean * scale}`);

if (broke) {
    console.log(errors.length ? `klystrack_cost: PASS (--break cost was caught)` : "klystrack_cost: FAILED -- --break cost was not caught");
    process.exit(errors.length ? 0 : 1);
}
console.log(errors.length ? `klystrack_cost: FAILED (${errors.length})` : "klystrack_cost: PASS");
process.exit(errors.length ? 1 : 0);
