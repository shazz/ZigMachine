// STCS STARGOOSE's ZIG MODE (apps/zig/scenes/stcs_zig.zig), checked on the
// COMPOSED picture of two copies of the cart run in lockstep for one whole
// choreography cycle (9500 frames, every scroller shape): A is never touched
// (ORIGINAL, itself the reference of apps/stcs_headless.mjs), B gets the keys.
//
//   ORIGINAL   1, 2, 3 change nothing: B == A
//   Z          ZIG: letters in the LEFT and RIGHT borders (opened per line),
//              stars, the logo fading; in every scroller shape
//   1          the borders close (B's sides == A's) and open again
//   2          the fade stops: the logo is A's again
//   3          the stars go: none left anywhere
//   stars      only on the stars' 3 colours, which ORIGINAL never shows; never
//              on a logo pixel; moving right to left 1..3 px a frame
//   Z again    ORIGINAL again: B == A, pixel for pixel
//
//   node apps/stcs_zig_headless.mjs [--cart X.wasm --disk X.zmd] [--break nokeys|key1|key2|key3]
//     --break    that key is never sent: the checks that need it must fail
import { readFileSync } from "node:fs";
import { boot } from "./stcs_zig_boot.mjs";

const argv = process.argv.slice(2);
const opt = (name, dflt) => { const i = argv.indexOf(name); return i < 0 ? dflt : argv[i + 1]; };
const brk = opt("--break", null);
if (brk && !["nokeys", "key1", "key2", "key3"].includes(brk)) throw new Error(`--break: unknown ${brk}`);
const cart = opt("--cart", "docs/demo-stcs.wasm"), disk = opt("--disk", "docs/demo-stcs.zmd");

const FRAMES = 9500, BX = 40, BY = 40, W = 320, H = 200;
const rgba = (r, g, b) => ((255 << 24) | (b << 16) | (g << 8) | r) >>> 0;
const STARS = new Set([rgba(80, 96, 144), rgba(144, 160, 208), rgba(208, 224, 255)]); // stcs_stars.colours
const LOGO = readFileSync("apps/zig/assets/screens/stcs/logo.raw"); // 320 x 73, 0 = no logo
const LOGO_ROWS = LOGO.length / W;

const A = await boot(cart, disk), B = await boot(cart, disk);
let failed = 0;
const check = (what, ok) => { console.log(`  ${ok ? "ok  " : "FAIL"} ${what}`); if (!ok) failed++; };
const press = (k) => {
    if (brk === "nokeys" || brk === `key${k}`) return;
    B.demo.key(k.charCodeAt(0));
};

// What one frame of B shows, against A's same frame.
function look() {
    const s = { same: true, side: 0, sideDiff: 0, stars: 0, starOnLogo: 0, starsA: 0, logoDiff: 0, starPts: [] };
    for (let y = 0; y < 280; y++) for (let x = 0; x < 400; x++) {
        const a = A.at(x, y), b = B.at(x, y);
        if (a !== b) s.same = false;
        if (STARS.has(a)) s.starsA++;
        const win = x >= BX && x < BX + W && y >= BY && y < BY + H;
        const side = !win && y >= BY && y < BY + H;
        if (STARS.has(b)) {
            s.stars++;
            s.starPts.push(y * 400 + x);
            const lx = x - BX, ly = y - BY;
            if (win && ly < LOGO_ROWS && LOGO[ly * W + lx] !== 0) s.starOnLogo++;
            continue;
        }
        if (side && a !== b) s.sideDiff++;
        if (side && a !== b) s.side++;
        if (win && y - BY < LOGO_ROWS && LOGO[(y - BY) * W + x - BX] !== 0 && a !== b) s.logoDiff++;
    }
    return s;
}

// Stars move left 1..3 px a frame: most of this frame's star pixels have one
// 1..3 px to their right in the last frame's.
function moved(prev, now) {
    if (!now.length) return 0;
    const was = new Set(prev);
    return now.filter((p) => [1, 2, 3].some((d) => was.has(p + d))).length / now.length;
}

// The run: [frame, keys] events, and what each stretch of frames must show.
const events = new Map([[100, "123"], [300, "Z"], [600, "1"], [700, "1"], [780, "2"], [900, "2"], [1000, "3"], [1100, "3"], [9430, "Z"]]);
const stats = { origSame: true, zigSide: new Map(), zigStars: 0, starOnLogo: 0, starsA: 0, moveSum: 0, moveN: 0, logoVaries: [Infinity, 0],
    closedSides: true, fadeOff: true, noStars: true, backSame: true };
const PERIODS = [[1, "threelines"], [600, "big_font"], [780, "threelines"], [1800, "big_font"], [3000, "interlaced_mirror"],
    [4800, "interlaced_big_font"], [6360, "inverted"], [6960, "interlaced_steam"], [8220, "inverted_mirror"]];
const periodOf = (f) => PERIODS.filter(([from]) => f >= from).at(-1)[1];

let prevStars = [];
for (let f = 1; f <= FRAMES; f++) {
    for (const k of events.get(f) ?? "") press(k);
    A.step(); B.step();
    const s = look();
    stats.starsA += s.starsA;
    const zig = f > 300 && f < 9430;
    if (f > 100 && f < 300) stats.origSame &&= s.same;
    if (zig) {
        stats.starOnLogo += s.starOnLogo;
        const bordersOn = !(f >= 600 && f < 700);
        if (bordersOn && s.side > 0) stats.zigSide.set(periodOf(f), true);
        if (f > 610 && f < 700) stats.closedSides &&= s.sideDiff === 0;
        if (f > 790 && f < 900) stats.fadeOff &&= s.logoDiff === 0;
        if (f >= 1000 && f < 1100) stats.noStars &&= s.stars === 0;
        else if (f > 310) {
            stats.zigStars += s.stars > 0 ? 1 : 0;
            // (not across a border toggle: the field's origin moves 40 px there)
            if (prevStars.length && !events.has(f)) { stats.moveSum += moved(prevStars, s.starPts); stats.moveN++; }
        }
        if (f > 310 && f < 590) {
            const lum = s.logoDiff; // pixels of the logo that are not A's
            stats.logoVaries = [Math.min(stats.logoVaries[0], lum), Math.max(stats.logoVaries[1], lum)];
        }
    }
    if (f > 9430) stats.backSame &&= s.same;
    prevStars = s.stars && zig ? s.starPts : [];
}

console.log(`stcs ZIG MODE over ${FRAMES} frames (${cart})`);
check("ORIGINAL never shows a star colour (they are the stars' alone)", stats.starsA === 0);
check("ORIGINAL: 1, 2 and 3 change nothing (frames 101..299 == the untouched cart)", stats.origSame);
for (const [, name] of PERIODS)
    check(`ZIG: letters in the opened side borders during ${name}`, stats.zigSide.get(name) === true);
check("1: the side borders close again (frames 611..699 == ORIGINAL's sides)", stats.closedSides);
check(`ZIG: the logo fades (pixels off ORIGINAL's: from ${stats.logoVaries[0]} to ${stats.logoVaries[1]})`,
    stats.logoVaries[0] < 100 && stats.logoVaries[1] > 2000);
check("2: the fade stops, the logo is ORIGINAL's (frames 791..899)", stats.fadeOff);
check(`ZIG: stars on screen (${stats.zigStars} frames)`, stats.zigStars > 9000);
check("3: no star left (frames 1000..1099)", stats.noStars);
const move = stats.moveSum / Math.max(1, stats.moveN);
check(`stars move right to left 1..3 px a frame (${(100 * move).toFixed(0)}% of star pixels, mean over ${stats.moveN} frames)`, move > 0.8);
check("stars stay behind the logo (never on a logo pixel)", stats.starOnLogo === 0);
check("Z again: ORIGINAL, pixel for pixel (frames 9431..9500)", stats.backSame);
if (B.machine.hwRamAllocFailures() || A.machine.hwRamAllocFailures()) check("no zg.mem allocation refused", false);

if (brk) {
    console.log(failed ? `stcs ZIG: PASS (--break ${brk} caught: ${failed} checks failed)` : `stcs ZIG: FAIL, --break ${brk} was NOT caught`);
    process.exit(failed ? 0 : 1);
}
console.log(failed ? `stcs ZIG: FAIL, ${failed} checks failed` : "stcs ZIG: PASS");
process.exit(failed ? 1 : 0);
