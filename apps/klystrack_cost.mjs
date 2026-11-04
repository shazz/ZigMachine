// Gate: the klystrack tracker cart's repaint cost (apps/frame_cost.mjs, est. board Mc; deterministic op counts,
// so a plain gate, not gate_timed). A repaint is what sets the board's fps while something moves: once a frame
// takes longer than 33 ms the 30 Hz tick is due every frame, so fps ~ 100 / Mc of one repaint.
//   playing   F5 plays STARPRT2.KT (handed to the machine's .kt player): every repaint frame of 121..180
//             (the pattern view follows play: most redraw the VU meters and timer, ~1 in 3 also scrolls)
//   menu      the right button held (klystron's menu bar open) and the pointer moving every frame: every
//             frame repaints (the worst case; a menu open with the pointer still repaints only on events)
// The ceilings sit ~20-25 % above perf/klystrack-ui-3's numbers (4 Nov 2026: playing median 4.9 / max 13.8, menu 3.2;
// round 2 was 5.9 / 14.3 / 3.9, round 1 10.6 / 21.5 / 8.1, and before it a repaint was ~41-46 Mc est). --break cost asks for 0 and must fail.
import { costOf, parseArgs } from "./frame_cost.mjs";

const CART = process.env.CART ?? "docs/demo-klystrack.wasm"; // CART=...: another build (a before/after)
const CEIL = { playMedian: 6, playMax: 16.5, menuMax: 4 };
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

const play = await series(["30:key:57349", "33:keyUp:57349"], 120);
const repaints = play.filter((mc) => mc > 3).sort((a, b) => a - b); // idle frames cost ~0.7 (FRESCO + frame)
const median = repaints[repaints.length >> 1], max = repaints[repaints.length - 1];
check(repaints.length >= 20, `playing: ${repaints.length} repaint frames of 60`);
check(median <= CEIL.playMedian * scale, `playing: median repaint ${median} Mc <= ${CEIL.playMedian * scale}`);
check(max <= CEIL.playMax * scale, `playing: worst repaint (row scroll) ${max} Mc <= ${CEIL.playMax * scale}`);

const moves = ["149:pointer:300,80,0", "150:pointer:300,80,4"];
for (let f = 160; f <= 230; f++) moves.push(`${f}:pointer:${300 + (f % 8) * 4},${80 + (f % 5)},4`);
const menu = await series(moves, 165);
const menuMax = Math.max(...menu);
check(menu.every((mc) => mc > 3), "menu: every frame repaints (the pointer moves with the button held)");
check(menuMax <= CEIL.menuMax * scale, `menu: worst repaint ${menuMax} Mc <= ${CEIL.menuMax * scale}`);

if (broke) {
    console.log(errors.length ? `klystrack_cost: PASS (--break cost was caught)` : "klystrack_cost: FAILED -- --break cost was not caught");
    process.exit(errors.length ? 0 : 1);
}
console.log(errors.length ? `klystrack_cost: FAILED (${errors.length})` : "klystrack_cost: PASS");
process.exit(errors.length ? 1 : 0);
