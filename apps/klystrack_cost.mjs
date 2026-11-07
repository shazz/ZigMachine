// Gate: the klystrack tracker cart's repaint cost (apps/frame_cost.mjs, est. board Mc; deterministic op counts,
// so a plain gate, not gate_timed). A repaint is what sets the board's fps while something moves.
//   playing   F5 plays STARPRT2.KT (handed to the machine's .kt player), frames 161..220: between two rows a
//             repaint redraws the VU meters and little else (round 4: views skipped when nothing they read
//             changed); on a row change the pattern rows scroll in their caches and one new row is drawn
//   menu      the right button held (klystron's menu bar open), the pointer moving every frame: the views
//             behind the menu are skipped, only the menu draws
//   both      playing with the menu open
//   inst      playing with the instrument tab open (F3): round 5 skips its views between events
//   submenu   File > Import's sub-menu, the pointer over one item (idle) and crossing its items while playing:
//             round 4 overflowed the command list there (41-48 est, board 5 fps); round 5: 1.26 / 6.6
//   editpat   Edit > Pattern's sub-menu (Clone, Expand 2X...) with the instrument tab behind it, the pointer over one
//             item (idle) and crossing its items while playing: round 5 still overflowed the list there (39.6 /
//             40.1 est, board 5 fps); round 6 draws a bevel's uniform parts as one copy each: 1.25 / 3.1
// Round 5 (6 Nov 2026), est Mc: playing median 1.44, worst row change 7.8, mean 1.85; menu 0.98; both mean 2.3;
// instrument tab mean 1.04 / worst 1.47. Round 4: 1.47 / 9.3 / 2.03, 0.95, 2.51, instrument tab 2.0 / 3.2.
// Round 3: playing median 4.9 / worst 13.8, menu 3.2. The ceilings sit ~20-30 % above round 5's.
// A palette compaction (~35-80 Mc, when the 256 window colours fill up with VU gradient shades) is left out of
// the window on purpose: it comes every few hundred frames in both rounds. --break cost asks for 0 and must fail.
import { costOf, parseArgs } from "./frame_cost.mjs";

const CART = process.env.CART ?? "docs/demo-klystrack.wasm"; // CART=...: another build (a before/after)
const CEIL = { playMedian: 1.8, playRow: 9.5, playMean: 2.3, menuMax: 1.25, bothMean: 2.9, instMean: 1.35, instMax: 1.9, subOne: 1.7, subCross: 10, patOne: 1.6, patCross: 4.5 };
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

// File > Import's submenu open, the button held: over one item, and crossing its items every frame. Round 4
// overflowed the 4,096-command list there (every frame redrawn whole, ~41-48 est, board 5 fps).
const P = (f, x, y, b) => `${f}:pointer:${x * 2},${y - 20},${b}`;   // klystrack 320x240 coordinates
const toSub = () => {
    const c = [P(100, 10, 5, 0), P(101, 10, 5, 4)];
    for (let f = 102; f <= 120; f++) c.push(P(f, 20, 5 + (f - 102) * 4, 4));
    for (let f = 121; f <= 140; f++) c.push(P(f, 20 + (f - 120) * 12, 69, 4));
    return c;
};
const sub1 = [...toSub()], subX = [...toSub()];
for (let f = 141; f <= 230; f++) { sub1.push(P(f, 230 + (f % 16) * 4, 70 + (f % 3), 4)); subX.push(P(f, 250 + (f % 8) * 4, 69 + (f % 4) * 9, 4)); }
const s1 = await series(sub1, 160), sx = await series([...F5, ...subX], 160);
check(Math.max(...s1) <= CEIL.subOne * scale, `submenu, the pointer over one item: worst ${Math.max(...s1)} Mc <= ${CEIL.subOne * scale}`);
check(mean(sx) <= CEIL.subCross * scale, `submenu, playing, a new item every frame: mean ${mean(sx)} Mc <= ${CEIL.subCross * scale}`);

// Edit > Pattern's submenu over the instrument tab (F3): round 5's ~4,600 commands ran the 4,608 list over.
const F3 = ["20:key:57347", "23:keyUp:57347"];
const toPat = () => {
    const c = [P(100, 10, 5, 0), P(101, 10, 5, 4)];
    for (let f = 102; f <= 120; f++) c.push(P(f, 110, Math.min(134, 5 + (f - 102) * 8), 4));
    for (let f = 121; f <= 140; f++) c.push(P(f, 110 + (f - 120) * 7, 134, 4));
    return c;
};
const pat1 = [...F3, ...toPat()], patX = [...F3, ...F5, ...toPat()];
for (let f = 141; f <= 230; f++) { pat1.push(P(f, 250 + (f % 16) * 2, 135 + (f % 3), 4)); patX.push(P(f, 250 + (f % 8) * 4, 134 + (f % 7) * 9, 4)); }
const p1 = await series(pat1, 160), px = await series(patX, 160);
check(Math.max(...p1) <= CEIL.patOne * scale, `Edit > Pattern over the instrument tab, one item: worst ${Math.max(...p1)} Mc <= ${CEIL.patOne * scale}`);
check(mean(px) <= CEIL.patCross * scale, `Edit > Pattern over the instrument tab, playing, a new item every frame: mean ${mean(px)} Mc <= ${CEIL.patCross * scale}`);

const inst = await series([...F5, "60:key:57347", "63:keyUp:57347"], 160);   // F3: the instrument tab
check(inst.filter((mc) => mc > 1.2).length >= 20, "instrument tab: it repaints while the song plays");
check(mean(inst) <= CEIL.instMean * scale, `instrument tab, playing: mean ${mean(inst)} Mc a frame <= ${CEIL.instMean * scale}`);
check(Math.max(...inst) <= CEIL.instMax * scale, `instrument tab, playing: worst ${Math.max(...inst)} Mc <= ${CEIL.instMax * scale}`);

if (broke) {
    console.log(errors.length ? `klystrack_cost: PASS (--break cost was caught)` : "klystrack_cost: FAILED -- --break cost was not caught");
    process.exit(errors.length ? 0 : 1);
}
console.log(errors.length ? `klystrack_cost: FAILED (${errors.length})` : "klystrack_cost: PASS");
process.exit(errors.length ? 1 : 0);
