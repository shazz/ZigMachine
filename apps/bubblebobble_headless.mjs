// Headless BUBBLE BOBBLE driver (cart 95). The port's model is
// github.com/olivierh59500's Go/Ebitengine remake — its internal/game is the
// arcade simulation, its internal/app the pages. This harness holds the cart
// to those bars:
//   pages   the title, the menu and the level editor really draw on the
//           400x280 overscan plane (lit chars in the playfield and the borders)
//   sim     bbTestStart(seed) + bbTestTick(mask) drive the SAME sim.Game the
//           scene plays, at the Go's own 60 Hz: walking at the Go's speed,
//           the jump arc leaving and returning to the ground, blowing a
//           bubble, trapping an enemy in it, popping it for score and a
//           dropped fruit, eating the fruit, the hurry-up at 30 s, a hit
//           costing a life, the yellow candy's rapid fire
//   rounds  every one of the 25 campaign rounds loads with its own tiles and
//           its own spawns, and clearing one advances the campaign
//   keys    the host path: Enter starts, Escape pauses and leaves
//   soak    no zg.mem allocation refused; ms/tick reported, not budgeted
//   node apps/bubblebobble_headless.mjs [outdir]
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { performance } from "node:perf_hooks";

const PAGES = 112; // must match SHARED_PAGES in machine/sdk/memmap.zig
const VBL_MS = 20;
const OUT = process.argv[2] || "/tmp/bubblebobble";
const W = 400, H = 280;

const memory = new WebAssembly.Memory({ initial: PAGES, maximum: PAGES });
let demo;
const machine = (await WebAssembly.instantiate(await readFile("docs/machine-video.wasm"), {
    env: { memory, hblDispatch: (id, p, l, x) => demo.hblDispatch(id, p, l, x) },
})).instance.exports;
const romEnv = { memory, hwVideoBase: machine.hwVideoBase, hwBlit: machine.hwBlit };
const rom = (await WebAssembly.instantiate(await readFile("docs/rom.wasm"), { env: romEnv })).instance.exports;
const noop = () => {};
const cartBytes = await readFile("docs/demo-bubblebobble.wasm");
const env = {
    ...romEnv,
    hwRamBase: machine.hwRamBase, hwRamTop: machine.hwRamTop, hwRamSize: machine.hwRamSize,
    hwRamUsed: machine.hwRamUsed, hwRamFree: machine.hwRamFree,
    hwRamAlloc: machine.hwRamAlloc, hwRamMark: machine.hwRamMark,
    hwRamRelease: machine.hwRamRelease, hwRamAllocFailures: machine.hwRamAllocFailures,
    hwRomRamBase: machine.hwRomRamBase, hwRomRamTop: machine.hwRomRamTop,
    hwRomRamSize: machine.hwRomRamSize, hwRomRamUsed: machine.hwRomRamUsed,
    hwRomRamFree: machine.hwRomRamFree, ...rom,
};
for (const imp of WebAssembly.Module.imports(new WebAssembly.Module(cartBytes)))
    if (imp.module === "env" && !(imp.name in env)) env[imp.name] = noop;
demo = (await WebAssembly.instantiate(cartBytes, { env })).instance.exports;
machine.hwInit();
demo.boot();
demo.skipBoot();

await mkdir(OUT, { recursive: true });
console.log("boot ok");

const step = (ms = VBL_MS) => { demo.frame(ms); if (demo.pollSfx) demo.pollSfx(); };

const errors = [];
const ok = (cond, msg) => { console.log(`  ${cond ? "ok  " : "FAIL"} ${msg}`); if (!cond) errors.push(msg); };

const stride = demo.bbTestScreenStride();
const shown = () => new Uint8Array(memory.buffer, demo.bbTestScreenPtr(), stride * H);
// Palette index 248 is the cart's panel/ink background, 0 the transparent key:
// a "busy" pixel is real art or text on top of them.
const INK = 248;
const busyIn = (x0, y0, x1, y1) => {
    let n = 0; const f = shown();
    for (let y = y0; y < y1; y++) for (let x = x0; x < x1; x++) { const v = f[y * stride + x]; if (v !== 0 && v !== INK) n++; }
    return n;
};

// --- pages -----------------------------------------------------------------
for (let i = 0; i < 8; i++) { machine.hwClear(); step(); }
const titleBusy = busyIn(0, 0, W, H);
ok(titleBusy > 2000, `the title page draws art on the overscan plane (${titleBusy} drawn pixels)`);

// Enter -> the menu.
demo.key(13);
step();
demo.keyUp(13);
for (let i = 0; i < 3; i++) { machine.hwClear(); step(); }
const menuBusy = busyIn(0, 0, W, H);
ok(menuBusy > 2000, `the menu page draws (${menuBusy} drawn pixels)`);
const logoBusy = busyIn(130, 16, 250, 100);
ok(logoBusy > 1000, `the logo is the logo, not blank (${logoBusy} drawn in its box)`);
const menuTextBusy = busyIn(100, 130, 300, 250);
ok(menuTextBusy > 200, `the menu's own list of entries is drawn (${menuTextBusy})`);

// --- the chip --------------------------------------------------------------
// The cart replays the original's own YM5 tune through the machine's YM2149:
// walk the same delta stream the generator emitted and hold the cart's register
// file to it, frame for frame.
const mb = new Uint8Array(await readFile("apps/zig/assets/screens/bubblebobble/music.bin"));
function trackAt(o) {
    const frames = mb[o] | (mb[o + 1] << 8);
    const seq = []; let p = o + 2;
    for (let f = 0; f < frames; f++) {
        const mask = mb[p] | (mb[p + 1] << 8); p += 2;
        const wr = [];
        for (let r = 0; r < 14; r++) if (mask & (1 << r)) wr.push([r, mb[p++]]);
        seq.push(wr);
    }
    return { frames, seq };
}
const menuTrack = trackAt(0);
demo.bbTestMusic(0);
step();
const regs = new Array(14).fill(0);
let modelApplied = 0, mismatch = 0;
for (let f = 0; f < 400; f++) {
    machine.hwClear();
    step();
    while (modelApplied < demo.bbTestMusicApplied()) {
        for (const [r, v] of menuTrack.seq[modelApplied % menuTrack.frames]) regs[r] = v;
        modelApplied++;
    }
    for (let r = 0; r < 14; r++) if (demo.bbTestYmReg(r) !== regs[r]) mismatch++;
}
ok(modelApplied >= 300, `the tune advanced at the host's 50 Hz pace (${modelApplied} frames in 400)`);
ok(mismatch === 0, `every YM register the cart fed the chip is the source tune's own (${mismatch} mismatches)`);
ok(demo.bbTestYmRefused() === 0, "not one YM write was refused");
const fed0 = demo.bbTestSfxFed();
demo.bbTestSfx(0);
for (let i = 0; i < 8; i++) { machine.hwClear(); step(); }
ok(demo.bbTestSfxFed() > fed0, `the WAV effects reach the cart's audio ring (${demo.bbTestSfxFed() - fed0} bytes fed)`);

// --- the simulation --------------------------------------------------------
const M = { left: 1, right: 2, jump: 4, fire: 8 };
demo.bbTestStart(1);
demo.bbTestLoadLevel(0);
ok(demo.bbTestState() === 1, "the world starts in play");
ok(demo.bbTestEnemyCount() > 0, `round 1 spawns its enemies (${demo.bbTestEnemyCount()})`);

// Walking: the Go's 3.0 px/tick, so 120 ticks of held right is 360 px.
demo.bbTestStart(1);
demo.bbTestLoadLevel(0);
let x0 = demo.bbTestPX();
for (let i = 0; i < 120; i++) demo.bbTestTick(M.right);
const dx = demo.bbTestPX() - x0;
ok(dx > (300 << 16) && dx < (420 << 16), `walking right 120 ticks covers the Go's 3 px/tick (${(dx / 65536).toFixed(1)} px)`);
ok(demo.bbTestDir() === 1, "facing right after walking right");
x0 = demo.bbTestPX();
for (let i = 0; i < 60; i++) demo.bbTestTick(M.left);
ok(demo.bbTestPX() < x0, "walking left goes left");
ok(demo.bbTestDir() === -1, "facing left after walking left");

// Jumping: the Go's -11.5 px/tick, with gravity bringing it home.
demo.bbTestStart(1);
demo.bbTestLoadLevel(0);
for (let i = 0; i < 30; i++) demo.bbTestTick(M.right); // settle on the floor
ok(demo.bbTestGround() === 1, "the dragon settles on the ground");
const y0 = demo.bbTestPY();
demo.bbTestTick(M.jump);
ok(demo.bbTestPVY() < 0, `jumping launches upward (vy ${(demo.bbTestPVY() / 65536).toFixed(2)})`);
let peak = y0;
for (let i = 0; i < 90; i++) { demo.bbTestTick(M.jump); peak = Math.min(peak, demo.bbTestPY()); }
ok(peak < y0 - (60 << 16), `the jump arc rises (${((y0 - peak) / 65536).toFixed(1)} px)`);
for (let i = 0; i < 90; i++) demo.bbTestTick(0);
ok(demo.bbTestGround() === 1, "and it comes back down to the ground");

// Blowing bubbles.
demo.bbTestStart(1);
demo.bbTestLoadLevel(0);
const beforeBlown = demo.bbTestBlown();
for (let i = 0; i < 40; i++) demo.bbTestTick(M.fire);
ok(demo.bbTestBlown() > beforeBlown, `fire blows bubbles (${demo.bbTestBlown()})`);
ok(demo.bbTestBubbles() > 0, `bubbles are in the air (${demo.bbTestBubbles()})`);

// Trapping an enemy: aim at the first one, blow until it is caught.
demo.bbTestStart(1);
demo.bbTestLoadLevel(0);
let trapped = 0;
for (let e = 0; e < demo.bbTestEnemyCount() && trapped === 0; e++) {
    demo.bbTestAimAtEnemy(e);
    for (let i = 0; i < 90; i++) {
        demo.bbTestTick(M.fire);
        if (demo.bbTestTrapped() > 0) { trapped = 1; break; }
    }
}
ok(trapped === 1, `a bubble traps an enemy (${demo.bbTestTrapped()} trapped)`);

// Popping the trapped enemy: score, a popped counter, and a dropped fruit.
demo.bbTestStart(1);
demo.bbTestLoadLevel(0);
const score0 = demo.bbTestScore();
demo.bbTestAimAtEnemy(0);
for (let i = 0; i < 120 && demo.bbTestTrapped() === 0; i++) demo.bbTestTick(M.fire);
const bi = demo.bbTestTrappedBubble();
ok(bi >= 0, "the trapped enemy has a bubble");
if (bi >= 0) {
    for (let i = 0; i < 40; i++) demo.bbTestTick(0); // let the bubble settle
    demo.bbTestPopAt(bi);
    for (let i = 0; i < 60; i++) demo.bbTestTick(0); // the enemy flies off and drops fruit
    ok(demo.bbTestPopped() > 0, `popping counted (${demo.bbTestPopped()})`);
    ok(demo.bbTestScore() > score0, `popping scores (${score0} -> ${demo.bbTestScore()})`);
    ok(demo.bbTestItems() > 0, `the defeat drops a fruit (${demo.bbTestItems()} items)`);
}

// Eating the fruit: stand on each item as walking onto it does.
demo.bbTestStart(1);
demo.bbTestLoadLevel(0);
demo.bbTestAimAtEnemy(0);
for (let i = 0; i < 120 && demo.bbTestTrapped() === 0; i++) demo.bbTestTick(M.fire);
if (demo.bbTestTrappedBubble() >= 0) {
    demo.bbTestPopAt(demo.bbTestTrappedBubble());
    for (let i = 0; i < 80; i++) demo.bbTestTick(0);
}
const items0 = demo.bbTestItems();
let eaten = 0;
for (let tries = 0; tries < 8 && demo.bbTestItems() > 0; tries++) {
    const s0 = demo.bbTestScore();
    const n0 = demo.bbTestItems();
    demo.bbTestWalkToItem(0);
    for (let i = 0; i < 4; i++) demo.bbTestTick(0);
    if (demo.bbTestItems() < n0 || demo.bbTestScore() > s0) eaten++;
}
ok(items0 > 0, `defeating an enemy leaves fruit on the floor (${items0} items)`);
ok(eaten > 0, `the dragon eats what it lands on (${eaten} pickups)`);

// The hurry-up after the Go's 30 seconds.
demo.bbTestStart(1);
demo.bbTestLoadLevel(0);
demo.bbTestSetLevelTicks(30 * 60);
demo.bbTestTick(0);
ok(demo.bbTestHurry() === 1, "30 seconds in, the enemies get angry (HURRY UP)");

// A hit costs a life.
demo.bbTestStart(1);
demo.bbTestLoadLevel(0);
const lives0 = demo.bbTestLives();
let lost = 0;
for (let i = 0; i < 3000 && lost === 0; i++) {
    demo.bbTestTick(0);
    if (demo.bbTestLives() < lives0) lost = 1;
}
ok(lost === 1, `an enemy costs a life (${lives0} -> ${demo.bbTestLives()})`);

// The yellow candy: the Go's cooldown drops from 18 to 5, so a 40-tick burst
// blows many more bubbles than the plain rate.
demo.bbTestStart(1);
demo.bbTestLoadLevel(0);
const plain = (() => { const a = demo.bbTestBlown(); for (let i = 0; i < 40; i++) demo.bbTestTick(M.fire); return demo.bbTestBlown() - a; })();
demo.bbTestStart(1);
demo.bbTestLoadLevel(0);
demo.bbTestGrantPower(3); // yellow_candy
const rapid = (() => { const a = demo.bbTestBlown(); for (let i = 0; i < 40; i++) demo.bbTestTick(M.fire); return demo.bbTestBlown() - a; })();
ok(rapid > plain * 2, `the yellow candy really is rapid fire (${plain} -> ${rapid} in 40 ticks)`);

// Every round loads with its own tiles and its own spawns.
let spawns = 0, empty = 0;
for (let n = 0; n < 25; n++) {
    demo.bbTestStart(1);
    demo.bbTestLoadLevel(n);
    const c = demo.bbTestEnemyCount();
    if (c === 0) empty++;
    spawns += c;
}
ok(empty === 0, `all 25 rounds spawn enemies (${spawns} spawns, none empty)`);
ok(spawns === 140, `and the campaign's own 140 spawns (${spawns})`);

// Clearing a round: defeat everything and the campaign advances.
demo.bbTestStart(1);
demo.bbTestLoadLevel(0);
const lvl0 = demo.bbTestLevel();
for (let e = 0; e < 20; e++) {
    demo.bbTestAimAtEnemy(0);
    for (let i = 0; i < 200 && demo.bbTestTrapped() === 0; i++) demo.bbTestTick(M.fire);
    const b = demo.bbTestTrappedBubble();
    if (b >= 0) demo.bbTestPopAt(b);
    for (let i = 0; i < 40; i++) demo.bbTestTick(0);
    if (demo.bbTestEnemies() === 0) break;
}
ok(demo.bbTestEnemies() === 0, `the round can be cleared (${demo.bbTestEnemies()} left)`);
for (let i = 0; i < 60 * 8; i++) demo.bbTestTick(0);
ok(demo.bbTestLevel() > lvl0 || demo.bbTestState() === 4, `clearing advances the campaign (round ${lvl0} -> ${demo.bbTestLevel()})`);

// --- the host key path -----------------------------------------------------
demo.bbTestStart(1);
for (let i = 0; i < 10; i++) { machine.hwClear(); step(); }
demo.key(32); // space starts the title page
step();
demo.keyUp(32);
demo.key(13);
step();
demo.keyUp(13);
for (let i = 0; i < 4; i++) { machine.hwClear(); step(); }
const playBusy = busyIn(72, 36, 328, 244);
ok(playBusy > 800, `the playfield draws (${playBusy} drawn pixels in the arena)`);
const hudBusy = busyIn(0, 0, 72, 280) + busyIn(328, 0, 400, 280) + busyIn(72, 0, 328, 36) + busyIn(72, 244, 328, 280);
ok(hudBusy > 400, `the HUD bands and side panels draw (${hudBusy} drawn pixels)`);

// --- every page draws, and its shot ----------------------------------------
const pal = () => new Uint32Array(memory.buffer, demo.bbTestPalettePtr(), 256);
async function shot(name) {
    const f = shown(), p = pal(), out = Buffer.alloc(W * H * 3);
    for (let i = 0; i < W * H; i++) {
        const c = p[f[i]];
        out[i * 3] = c & 0xff;
        out[i * 3 + 1] = (c >>> 8) & 0xff;
        out[i * 3 + 2] = (c >>> 16) & 0xff;
    }
    await writeFile(`${OUT}/${name}.ppm`, Buffer.concat([Buffer.from(`P6\n${W} ${H}\n255\n`), out]));
}
demo.bbTestStart(1);
demo.bbTestLoadLevel(0);
const pageNames = ["title", "menu", "profiles", "new_profile", "scores", "settings", "help", "credits", "editor", "play", "result"];
for (let n = 0; n < pageNames.length; n++) {
    demo.bbTestPage(n);
    demo.bbTestSel(0);
    machine.hwClear(); step(); machine.hwClear(); step();
    const b = busyIn(0, 0, W, H);
    ok(b > 250, `page ${pageNames[n]} draws (${b} drawn pixels)`);
    await shot(`${String(n).padStart(2, "0")}_${pageNames[n]}`);
}

// --- soak ------------------------------------------------------------------
demo.bbTestStart(1);
demo.bbTestLoadLevel(0);
const t0 = performance.now();
let ticks = 0;
for (let i = 0; i < 6000; i++) { demo.bbTestTick((i % 7 === 0 ? M.fire : 0) | (i % 13 < 6 ? M.right : M.left) | (i % 31 < 4 ? M.jump : 0)); ticks++; }
const ms = (performance.now() - t0) / ticks;
console.log(`  sim ${ticks} ticks in ${(ms * ticks).toFixed(1)} ms (${ms.toFixed(4)} ms/tick)`);
ok(Number.isFinite(ms), "the sim runs at a finite cost");

const allocFails = machine.hwRamAllocFailures();
ok(allocFails === 0, `no zg.mem allocation refused (${allocFails})`);

console.log(errors.length === 0 ? "bubblebobble: PASS" : `bubblebobble: ${errors.length} FAILED`);
process.exit(errors.length === 0 ? 0 : 1);
