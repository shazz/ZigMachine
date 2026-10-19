// Headless KICK OFF 2 driver (the friendly, cart 91). The port's model is
// github.com/olivierh59500/kickoff2 — the Go/Ebitengine re-creation of Dino
// Dini's Kick Off 2 engine — and this harness holds the cart to its bars:
//   title    the front page is the ripped title art (a dense lit plane, not
//            the system font) and FIRE starts the kickoff
//   sim      ko2TestStart(seed) + ko2TestTick() drive the SAME MatchP the
//            scene plays, 3 simulated minutes from a fixed seed: the ball
//            leaves the centre circle, stays on-pitch while in play, the
//            phase machine never leaves a legal state, and the clock
//            advances only while in play
//   keys     the host path: Space starts, Escape leaves the match for the
//            title, Escape again hands the screen to the menu
//   pace     holding a direction moves the controlled player at the Go's pace
//            word plus the human's free-running bonus (236 -> 3.60 units/tick =
//            180 units/s), and diagonals keep the Go's 707/1000 per axis -- the
//            fixed-point step that wrapped i32, leaving the runners at a snails
//            0.30 units/tick while still "moving"
//   soak     no zg.mem allocation refused; ms/tick reported, not budgeted
//   node apps/kickoff2_headless.mjs [outdir]
import { mkdir, readFile } from "node:fs/promises";
import { performance } from "node:perf_hooks";

const PAGES = 112; // must match SHARED_PAGES in machine/sdk/memmap.zig
const VBL_MS = 20;
const OUT = process.argv[2] || "/tmp/kickoff2";
const W = 320, H = 200;

const memory = new WebAssembly.Memory({ initial: PAGES, maximum: PAGES });
let demo;
const machine = (await WebAssembly.instantiate(await readFile("docs/machine-video.wasm"), {
    env: { memory, hblDispatch: (id, p, l, x) => demo.hblDispatch(id, p, l, x) },
})).instance.exports;
const romEnv = { memory, hwVideoBase: machine.hwVideoBase, hwBlit: machine.hwBlit };
const rom = (await WebAssembly.instantiate(await readFile("docs/rom.wasm"), { env: romEnv })).instance.exports;
const noop = () => {};
const cartBytes = await readFile("docs/demo-kickoff2.wasm");
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

const errors = [];
const ok = (cond, msg) => { console.log(`  ${cond ? "ok  " : "FAIL"} ${msg}`); if (!cond) errors.push(msg); };
const shown = () => new Uint8Array(memory.buffer, demo.ko2ScreenPtr(), W * H);
const lit = (y0, y1) => { let n = 0; const f = shown(); for (let y = y0; y < y1; y++) for (let x = 0; x < W; x++) n += f[y * W + x] !== 0 ? 1 : 0; return n; };

for (let i = 0; i < 8; i++) { machine.hwClear(); demo.frame(VBL_MS); }
const titleLit = lit(20, 180);
ok(titleLit > 2000, `the front page is the title art (${titleLit} lit chars rows 20..180)`);

// FIRE -> the kickoff freezes on the centre, then play starts. The tick sees a
// rising edge only if FIRE is still held when one runs, so hold it across a
// frame (down+up with no frame between never starts anything — which is how
// this block used to pass on the title screen alone).
demo.key(32);
machine.hwClear(); demo.frame(VBL_MS);
demo.keyUp(32);
for (let i = 0; i < 12; i++) { machine.hwClear(); demo.frame(VBL_MS); }
const phase = demo.ko2Phase();
ok(phase === 1 || phase === 2, `FIRE started the match (phase ${phase}, 1 = kickoff, 2 = playing)`);
const pitchLit = lit(40, 160);
ok(pitchLit > titleLit / 2, `the plane shows the pitch (${pitchLit} lit chars)`);
ok(demo.ko2Score(0) === 0 && demo.ko2Score(1) === 0, "the scoreboard starts 0-0");
// The match paints its own art indices, and showTitle() left TITLE_PAL in the
// plane: unless the match re-asserts MATCH_PAL the pitch shows through the
// title's greens (pale speckle, wrong kit/skin) — the "wrong colours" report.
// Read the live table back out of the machine, not the scene's constant.
{
    const pal = [];
    const dv = new DataView(memory.buffer, machine.hwVideoBase() + 0x100, 64);
    for (let i = 0; i < 16; i++) pal.push([dv.getUint8(i * 4), dv.getUint8(i * 4 + 1), dv.getUint8(i * 4 + 2)]);
    const want = [[0,0,0],[0,170,0],[51,153,0],[0,136,0],[204,221,187],[255,221,204],[255,255,255],[0,0,255],[170,0,0],[0,0,255],[0,102,0],[255,255,255],[0,0,0],[153,153,153],[119,119,119],[0,204,255]];
    ok(JSON.stringify(pal) === JSON.stringify(want), `the match re-applied MATCH_PAL (slot 1 = ${pal[1].join(",")}, want 0,170,0)`);
}
demo.key(0xE012); demo.keyUp(0xE012);
for (let i = 0; i < 12; i++) demo.frame(VBL_MS);
const afterEsc = lit(20, 180);
ok(afterEsc > 40000, `Escape left the match for the title (${afterEsc} lit chars)`);
demo.key(0xE012); demo.keyUp(0xE012);
for (let i = 0; i < 4; i++) demo.frame(VBL_MS);
ok(demo.pollCartRequest() === -1, "Escape at the title hands back to the menu (pollCartRequest -1)");
demo.keyUp(0xE012);

// ---------------------------------------------------------------- the sim
const SEED = 0x2a2a2a2a;
demo.ko2TestStart(SEED);
const ram = () => new Uint8Array(memory.buffer, demo.ko2RamPtr(), demo.ko2RamLen());
const readI32 = (o) => ram()[o] | ram()[o + 1] << 8 | ram()[o + 2] << 16 | ram()[o + 3] << 24;
// Ball's offset within MatchP: find the centre positions 456/696 in 16.16.
function findBallOffset() {
    const wantX = 456 * 65536, wantY = 696 * 65536;
    for (let o = 0; o + 8 <= demo.ko2RamLen() - 4; o += 4)
        if (readI32(o) === wantX && readI32(o + 4) === wantY) return o;
    return -1;
}
demo.ko2TestStart(SEED); // fresh state for the scan
const BALL_OFF = findBallOffset();
ok(BALL_OFF > 0, `the ball's state was located in the match RAM (offset ${BALL_OFF})`);

const CX = 456, CY = 696; // centre (fixed 1.0 units)
let leftCentre = false, onPitchOK = true, phaseOK = true, clockHeldOut = true;
let lastClock = -1;
const PENX_LO = -90, PENX_HI = 1002, PENY_LO = -120, PENY_HI = 1512;
const t0 = performance.now();
let strayOut = 0;
const TICKS = 60 * 50 * 3; // 3 simulated minutes
for (let k = 0; k < TICKS; k++) {
    // the scripted driver presses fire in pulses + wiggles the pad
    const dirBits = 1 << ((k >>> 3) % 4);
    const mask = (k % 150 < 40 ? 16 : 0) | (k % 7 === 0 ? dirBits : 0);
    const ph = demo.ko2TestTick(mask);
    if (!(ph >= 1 && ph <= 4)) phaseOK = false;
    const bx = readI32(BALL_OFF) / 65536, by = readI32(BALL_OFF + 4) / 65536;
    if (Math.abs(bx - CX) > 35 || Math.abs(by - CY) > 35) leftCentre = true;
    if (ph === 2 || ph === 3) {
        if (bx < PENX_LO || bx > PENX_HI || by < PENY_LO || by > PENY_HI) strayOut++;
    }
    const cl = demo.ko2Clock();
    if (ph !== 2 && lastClock >= 0 && cl !== lastClock) clockHeldOut = false;
    lastClock = cl;
}
const simMs = performance.now() - t0;
ok(leftCentre, "the ball left the centre circle");
ok(phaseOK, "the phase machine never left a legal state");
ok(strayOut === 0, `the ball never drifted off-pitch while in play (${strayOut} stray frames)`);
ok(clockHeldOut, "the clock advances only while in play");
ok(demo.ko2Score(0) >= 0 && demo.ko2Score(1) >= 0, "the score is sane after 3 sim minutes");
ok(simMs < 12000, `3 sim minutes ran in ${simMs.toFixed(0)} ms`);

// ------------------------------------------------------- the runner's pace
// The pace word is the Go's Step*1000*TPS/65536 (original_controls.go:685):
// 216*1000*50/65536 = 164.8 units/s, i.e. 216000 in 16.16 = 3.296 units/tick.
// moveBy multiplies a 16.16 direction by that step, and 65536*216000 is 1.4e10
// -- wider than i32. Wrapped, the product left the runners at 0.30 units/tick
// (165 -> 15 units/s: the "the players move like snails" report) while still
// moving, so only a measured speed catches it. Hold a direction and read the
// controlled player back out of the match state.
function stepStats(mask, ticks) {
    demo.ko2TestStart(SEED);
    const ax = [], ay = [], mag = [];
    let idx = -1, px = 0, py = 0;
    for (let k = 0; k < ticks; k++) {
        demo.ko2TestTick(mask);
        if (demo.ko2Phase() !== 2) { idx = -1; continue; }
        const ci = demo.ko2TestControlled();
        const x = demo.ko2TestPosX(0, ci), y = demo.ko2TestPosY(0, ci);
        if (ci === idx) {
            const dx = (x - px) / 65536, dy = (y - py) / 65536;
            const m = Math.hypot(dx, dy);
            // >0.05 skips the ticks a carrier stands still; <4 drops the one
            // discontinuity a restart can place under the player.
            if (m > 0.05 && m < 4) { ax.push(Math.abs(dx)); ay.push(Math.abs(dy)); mag.push(m); }
        }
        idx = ci; px = x; py = y;
    }
    const med = (a) => { const s = a.slice().sort((p, q) => p - q); return s.length ? s[s.length >> 1] : 0; };
    return { x: med(ax), y: med(ay), mag: med(mag), n: mag.length };
}
const runE = stepStats(8, 200); // right: direction 2, (1,0)
const runDiag = stepStats(1 | 8, 200); // up+right: direction 1, (.707,-.707)
// The man the human steers carries the source's free-running bonus: 236, not the
// ordinary NPC's 216 (original_controls.go:1025 vs :1120), i.e. 3.60 units/tick
// = 180 units/s. An NPC walks the same moveBy at the plain 3.30.
ok(runE.mag > 3.4 && runE.mag < 3.8,
    `the controlled runner carries the Go's pace+20 (${runE.mag.toFixed(2)} units/tick = ${(runE.mag * 50).toFixed(0)} units/s)`);
// OriginalDirection's diagonals are 707/1000 on EACH AXIS (never renormalized),
// so a diagonal carries 0.707 on both axes and the same total -- the bar is the
// per-axis component. (The old 23170 was 0.707 in Q15: a half-speed diagonal,
// 1.65/tick, that this per-axis check catches.)
ok(Math.abs(runDiag.x - runE.mag * 0.7071) < 0.2 && Math.abs(runDiag.y - runE.mag * 0.7071) < 0.2,
    `diagonals keep the Go's 707/1000 (per axis ${runDiag.x.toFixed(2)}/${runDiag.y.toFixed(2)}, want ${(runE.mag * 0.7071).toFixed(2)})`);

// --------------------------------------------------- who defends which end
// resetPositions puts each keeper on the line he defends. attackDown is the
// Go's AttackDirection(team) > 0 (match.go:246-258): team 0 attacks +y in the
// first half, so its own goal is the TOP line and team 1's is the bottom. The
// keeper line, the restart facing and the score attribution used to be written
// the other way round, which left each keeper standing in the goal his own
// team was attacking.
{
    demo.ko2TestStart(SEED);
    const k0y = demo.ko2TestPosY(0, 0) / 65536, k1y = demo.ko2TestPosY(1, 0) / 65536;
    ok(k0y < 216 && k1y > 1176,
        `each keeper stands on his own line at the kickoff (team 0 ${k0y}, team 1 ${k1y})`);
}

// ---------------------------------------------- the goal kick is the keeper's
// restarts.go:24-32 forces Restart.Player = 0 for GoalKick and picks the
// nearest outfielder for every other kind. The port sent an outfielder while
// the keeper stood on the ball — "for kick off the goalie is supposed to kick
// the ball".
function toPlay() {
    demo.ko2TestStart(SEED);
    for (let k = 0; k < 200 && demo.ko2Phase() !== 2; k++) demo.ko2TestTick(0);
}
{
    // First half: team 0 attacks +y (the bottom). An ATTACKER's touch over the
    // bottom line is a goal kick for team 1, taken by team 1's keeper (0).
    toPlay();
    demo.ko2TestForceEndOut(0, 1);
    demo.ko2TestTick(0);
    let kind = demo.ko2TestRestartKind(), team = demo.ko2TestRestartTeam(), taker = demo.ko2TestRestartTaker();
    ok(kind === 1 && team === 1 && taker === 0,
        `an attacker's touch over the bottom line is team 1's goal kick, taken by the keeper (kind ${kind}, team ${team}, taker ${taker})`);
    // The same line touched by a DEFENDER is a corner for the attackers.
    toPlay();
    demo.ko2TestForceEndOut(1, 1);
    demo.ko2TestTick(0);
    kind = demo.ko2TestRestartKind(); team = demo.ko2TestRestartTeam();
    ok(kind === 2 && team === 0, `a defender's touch there is a corner for team 0 (kind ${kind}, team ${team})`);
    // The top line is team 0's own: team 1's touch is a goal kick for team 0.
    toPlay();
    demo.ko2TestForceEndOut(1, 0);
    demo.ko2TestTick(0);
    kind = demo.ko2TestRestartKind(); team = demo.ko2TestRestartTeam(); taker = demo.ko2TestRestartTaker();
    ok(kind === 1 && team === 0 && taker === 0,
        `the top line gives team 0 a goal kick, taken by the keeper (kind ${kind}, team ${team}, taker ${taker})`);
}

// ------------------------------------------------------------ score attribution
// The ball in a goal mouth is outKind 3 (top, y < 0) or 4 (bottom); the scorer
// is the team attacking that end, i.e. team 0 for the bottom in the first half.
{
    toPlay();
    demo.ko2TestForceGoal(1);
    demo.ko2TestTick(0);
    ok(demo.ko2Score(0) === 1 && demo.ko2Score(1) === 0,
        `a goal in the bottom mouth is team 0's (${demo.ko2Score(0)}-${demo.ko2Score(1)})`);
    toPlay();
    demo.ko2TestForceGoal(0);
    demo.ko2TestTick(0);
    ok(demo.ko2Score(0) === 0 && demo.ko2Score(1) === 1,
        `a goal in the top mouth is team 1's (${demo.ko2Score(0)}-${demo.ko2Score(1)})`);
}

// --------------------------------------------------------------- second half
// The scene swaps ends when the half turns over (kickoff2.zig:118-128). The
// scorer, the keeper lines and the goal kicks all follow attackDown, and the
// score attribution used to ignore the swap completely.
{
    demo.ko2TestStart(SEED);
    demo.ko2TestSecondHalf();
    const k0y = demo.ko2TestPosY(0, 0) / 65536, k1y = demo.ko2TestPosY(1, 0) / 65536;
    ok(k0y > 1176 && k1y < 216, `at the second half the keepers have swapped ends (team 0 ${k0y}, team 1 ${k1y})`);
    const play2 = () => {
        demo.ko2TestStart(SEED);
        demo.ko2TestSecondHalf();
        for (let k = 0; k < 200 && demo.ko2Phase() !== 2; k++) demo.ko2TestTick(0);
    };
    play2();
    demo.ko2TestForceEndOut(1, 1); // team 1 attacks the bottom in the second half
    demo.ko2TestTick(0);
    const kind = demo.ko2TestRestartKind(), team = demo.ko2TestRestartTeam(), taker = demo.ko2TestRestartTaker();
    ok(kind === 1 && team === 0 && taker === 0,
        `second half: an attacker's touch over the bottom line is team 0's goal kick, taken by the keeper (kind ${kind}, team ${team}, taker ${taker})`);
    play2();
    demo.ko2TestForceGoal(1);
    demo.ko2TestTick(0);
    ok(demo.ko2Score(0) === 0 && demo.ko2Score(1) === 1,
        `second half: a bottom-mouth goal is team 1's (${demo.ko2Score(0)}-${demo.ko2Score(1)})`);
}

// soak
ok(machine.hwRamAllocFailures() === 0, "no zg.mem allocation refused");
console.log(`  ${(simMs / TICKS * 1000).toFixed(1)} us per match tick (full sim, no render)`);

const total = errors.length;
console.log(total === 0 ? "kickoff2: PASS" : `kickoff2: FAILED (${total})`);
process.exit(total ? 1 : 0);
