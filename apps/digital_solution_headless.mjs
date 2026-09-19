// Headless "The Digital Solution" check — the B.I.G. Demo's sound-test screen,
// reached from the jukebox row "-:THE DIGITAL DEPARTMENT:-". It is a screen OF
// big_demo, not a cart of its own, so this drives docs/demo-big_demo.wasm: past
// wait(), down the list to the Digital Department row, Return.
//
// Every visible pixel must equal screen.raw through its own pal.dat — the plane
// really is the captured picture, not something that merely hashes
// consistently — EXCEPT rows 179..194, the 16 the shared scrolltext owns. That
// band cannot be asserted against the capture (the scroll offset at capture
// time is unknown, and the remake's text may not even be the real screen's), so
// it is excluded and covered instead by checks of its own: it moves, its pixels
// come from the shared font and nowhere else, and it is pixel-identical to a
// SECOND machine left running the jukebox — which is what proves the text
// carries on across the screen change rather than restarting. On top of that: the row that opens it is the
// LAST one the cursor can reach (`mylist.length - 3`) and the row before it does
// not open it, nothing moves, opening it plays nothing, keys 1-6 request the
// right FILE and the right SUBTUNE, Space goes back to the running jukebox,
// Escape leaves, every named SNDH is on disk, and every one of the six really
// makes sound (all six are FLAG ~ay, the flag that usually means silence — so
// it is measured, not assumed).
//
//   node apps/digital_solution_headless.mjs [cart.wasm] [--break pixels|tune|songs|exit|route|drift]
// --break perturbs an INPUT — the reference picture, an entry's subtune, an
// entry's filename, which key is pressed to leave, which ROW is selected, or
// the shadow machine's frame count — and each must be caught.
import { readFile } from "node:fs/promises";
import { performance } from "node:perf_hooks";
// The sealed machine, not big_demo's own: boot() is screen-agnostic and lives
// in that file only because it is where it was first needed.
import { boot } from "./big_demo_machine.mjs";
import { readTunes, checkSongs, measurePeaks, ENTRIES } from "./digital_solution_tunes.mjs";
import { CURSOR, DIGITAL } from "./big_demo_list.mjs";
import { shadow, view, BAND_ROWS } from "./digital_solution_band.mjs";

const CW = 320, CH = 200; // the visible window inside the 400x280 overscan plane
const ART = "apps/zig/assets/screens/digital_solution";
const WAIT = 200; // wait()'s 200 frames; go() takes over on 201
const K_ESC = 0xE012, K_SPACE = 32, K_RETURN = 13, K_1 = 49, DIR_DOWN = 1, DIR_BACK = 6;
const STATIC_AT = 120; // two seconds: long enough for anything animated to show
const SHADOW_DELAY = 17; // how much later the shadow machine opens the screen

const argv = process.argv.slice(2), bi = argv.indexOf("--break"), MODES = ["pixels", "tune", "songs", "exit", "route", "drift"];
const brk = bi >= 0 ? argv.splice(bi, 2)[1] : null;
if (brk && !MODES.includes(brk)) throw new Error(`--break ${brk}: ${MODES.join("|")}`);
const CART = argv[0] || "docs/demo-big_demo.wasm";
const errors = [];

// 1. the table, and the files behind it
const TUNES = readTunes(brk);
const songs = checkSongs(TUNES);
if (TUNES.length !== ENTRIES) errors.push(`the scene lists ${TUNES.length} entries, the picture prints ${ENTRIES}`);
errors.push(...songs.errors);
const phantom = TUNES.filter((e) => /PHANTOMS/.test(e.label));
if (phantom.length !== 2 || phantom[0].song !== phantom[1].song || phantom[0].tune === phantom[1].tune)
    errors.push("PHANTOMS 1 and 2 must be two DIFFERENT subtunes of one SNDH, not two entries on one tune");
if (DIGITAL !== CURSOR[1]) errors.push(`the Digital Department row ${DIGITAL} is not the cursor's last stop ${CURSOR[1]}`);

const { memory, machine, demo } = await boot(CART);
const V = view(memory, machine), band = V.band, hashFrame = V.hashStill;
const diffPicture = (raw, pal) => V.diff(raw, pal);
const PW = machine.hwPhysWidth(), dec = new TextDecoder(); // 800: the visible x is DOUBLED
let frame = 0, song = null, tune = 0, songAt = -1, cart = 0, cartMs = 0;

function step() {
    const t0 = performance.now();
    machine.hwClear();
    demo.frame(1000 / 60);
    cartMs += performance.now() - t0; // the cart's own cost, not the machine's
    for (let p = 0; p < 4; p++) if (demo.isPlaneEnabled(p)) machine.hwRenderPlane(p);
    frame++;
    cart = demo.pollCartRequest();
    if (!demo.pollSongRequest()) return;
    song = dec.decode(new Uint8Array(memory.buffer, demo.songNamePtr(), demo.songNameLen()));
    tune = demo.songTune(); songAt = frame;
}

// 2. down the list to the Digital Department row, and Return.
// --break route stops ONE row short. That row (ZOOLOOK) has a tune, so the
// wrong-row case is not silently indistinguishable from the right one.
while (frame <= WAIT) step();
const rows = (brk === "route" ? DIGITAL - 1 : DIGITAL) - CURSOR[0];
for (let k = 0; k < rows; k++) { demo.input(DIR_DOWN); step(); }
const jukebox = hashFrame();
const songBefore = songAt;
demo.key(K_RETURN); step();
if (brk !== "route" && songAt !== songBefore)
    errors.push(`the Digital Department row asked for ${JSON.stringify(song)} #${tune}: it opens a screen, it does not play`);

// 3. THE PICTURE: every visible pixel is screen.raw through pal.dat.
// --break pixels flips one byte of the REFERENCE, so a check that only compared
// the frame with itself would sail through this.
const raw = new Uint8Array(await readFile(`${ART}/screen.raw`));
const pal = new Uint8Array(await readFile(`${ART}/pal.dat`));
if (raw.length !== CW * CH) errors.push(`screen.raw is ${raw.length} bytes, not 320x200`);
if (brk === "pixels") raw[CH / 2 * CW + CW / 2] ^= 1;
const bad = diffPicture(raw, pal);
if (bad) errors.push(bad);
const first = hashFrame();
if (first === jukebox) errors.push("Return on the Digital Department row changed nothing: the screen never opened");

// 3b. THE BAND — the 16 rows the picture check above deliberately skips.
// Three compensating checks, because an exclusion with nothing behind it is how
// a bug hides: it is a real scroller (many colours, all of them the shared
// font's), it MOVES, and it is in lockstep with a second machine that stayed in
// the jukebox — which is continuity across the screen change, measured.
const bigPal = new Uint8Array(await readFile("apps/zig/assets/screens/big_demo/pal.dat"));
const BASE = 124; // where digital_solution_assets.py appends; below it is big_demo's own
const shared = new Set(); // the colours the jukebox's font can paint
for (let i = 0; i < BASE; i++) shared.add(`${bigPal[i * 4]},${bigPal[i * 4 + 1]},${bigPal[i * 4 + 2]}`);
const PANEL = `${pal[128 * 4]},${pal[128 * 4 + 1]},${pal[128 * 4 + 2]}`; // what the band sits on
const b0 = band();
if (b0.colours.size < 9) errors.push(`the band shows ${b0.colours.size} colours: the fontbg fill alone is 8, so it is not drawing`);
const alien = [...b0.colours].filter((c) => c !== PANEL && !shared.has(c));
if (alien.length) errors.push(`the band paints ${alien.length} colour(s) that are not the shared font's or the panel: ${alien[0]}`);
step();
if (band().hash === b0.hash) errors.push("the band did not change between two frames: the scrolltext is not running");
// The second machine, which opened this screen SHADOW_DELAY frames later and
// is then stepped to the same absolute frame. --break drift gives it one frame
// more, which must be caught: a check that could not see one frame of drift
// could not see a reset either.
const shadowRun = await shadow(CART, { waitFrames: WAIT, rows, delay: SHADOW_DELAY });
/// Step BOTH machines to a common frame and compare the band there.
///
/// The sync has to go both ways: the shadow's constructor leaves it ahead (it
/// dawdles SHADOW_DELAY frames before entering), and runTo cannot go backwards
/// — comparing without this silently measured two different frames and read as
/// a scrolltext bug. The frame numbers are asserted equal so it cannot come
/// back. --break drift deliberately puts the shadow one frame out.
function bandsAgree(what) {
    while (frame < shadowRun.frame) step();
    shadowRun.runTo(frame + (brk === "drift" ? 1 : 0));
    if (!brk && shadowRun.frame !== frame) errors.push(`${what}: compared frame ${frame} against ${shadowRun.frame}`);
    if (shadowRun.band().hash !== band().hash) errors.push(what);
}
bandsAgree(`the band differs from a run that opened this screen ${SHADOW_DELAY} frames later: the scrolltext RESTARTED on entry or runs at a different rate`);

// 4. nothing moves, and nothing plays by itself
const seen = songAt;
const until = frame + STATIC_AT;
while (frame < until) step();
if (hashFrame() !== first) errors.push(`the screen changed over ${STATIC_AT} frames outside the band: the rest is STATIC`);
if (songAt !== seen) errors.push(`music changed by itself at frame ${songAt} (${song}): the screen waits for a key`);
if (cart !== 0) errors.push(`the screen asked to leave (${cart}) with no key pressed`);

// 5. keys 1-6: the right file AND the right subtune, and no pixel moves
for (const [n, want] of TUNES.entries()) {
    demo.key(K_1 + n); step();
    if (song !== want.song || tune !== want.tune)
        errors.push(`"${want.label}" asked for ${JSON.stringify(song)} #${tune}, wanted "${want.song}" #${want.tune}`);
}
const before = songAt;
for (const cp of [K_1 - 1, K_1 + ENTRIES, 66]) { demo.key(cp); step(); } // '0', '7', 'B'
if (songAt !== before) errors.push(`an unbound key asked for ${JSON.stringify(song)} #${tune}: only 1-6 play`);
if (hashFrame() !== first) errors.push("a key changed the picture: the screen has no cursor or highlight");

// 6. Space goes back to the jukebox, which is RUNNING again (its scroller moves).
// --break exit presses the key next to Space's codepoint, which nothing binds.
demo.key(brk === "exit" ? K_SPACE + 1 : K_SPACE);
step();
if (!diffPicture(raw, pal)) errors.push("Space did not leave the Digital Solution");
const back = hashFrame();
step();
if (hashFrame() === back) errors.push("the jukebox is frozen after coming back: it should be running again");
// ...and the scrolltext carries on the OTHER way too. Come back IN — the cursor
// is still on the Digital Department row — and the band must still agree with
// the shadow, which never left. That can only hold if the jukebox advanced the
// same one-per-frame while we were away and nothing reset on either crossing.
demo.key(K_RETURN); step();
bandsAgree("after leaving and re-entering, the band no longer agrees with the shadow: the scrolltext restarted on a crossing");
demo.key(K_ESC); step();
if (cart !== -1) errors.push(`Escape asked for cart ${cart}, wanted -1 (the menu disk)`);
step();
demo.input(DIR_BACK); step();
if (cart !== -1) errors.push(`Back asked for cart ${cart}, wanted -1`);

// 7. all six really make sound (measurePeaks says why that is not assumed)
const missing = new Set(TUNES.filter((e) => songs.errors.some((m) => m.startsWith(e.song))).map((e) => e.song));
const peaks = await measurePeaks(TUNES, missing, errors);
const perFrame = cartMs / frame;
if (perFrame > 4) errors.push(`cart takes ${perFrame.toFixed(3)} ms/frame`);

if (brk) {
    const caught = errors.length > 0;
    console.log(caught ? `=> PASS ✅ fail proof: --break ${brk} was caught (${errors[0]})`
        : `=> FAIL ❌ fail proof: --break ${brk} passed every check`);
    process.exit(caught ? 0 : 1);
}
if (errors.length) { console.error(`digital_solution: WRONG\n  ${errors.slice(0, 12).join("\n  ")}`); process.exit(1); }
if (songs.orphans.length) console.log(`digital_solution: ${songs.orphans.length} unused SNDH in docs/music/digital/: ${songs.orphans.join(" ")}`);
console.log(`digital_solution: FITS list row ${DIGITAL} ("-:THE DIGITAL DEPARTMENT:-") opens it, all ${CW * (CH - (BAND_ROWS[1] - BAND_ROWS[0]))} still px match screen.raw ` +
    `outside rows ${BAND_ROWS[0]}..${BAND_ROWS[1] - 1} (frame ${first.slice(0, 12)}), static over ${STATIC_AT} frames; ` +
    `the band is the shared scrolltext — ${b0.colours.size} colours, all the font's, in lockstep with a run that opened it ${SHADOW_DELAY} frames later; ` +
    `keys 1-6 -> ${songs.named} SNDH (all on disk), ` +
    `PHANTOMS = subtunes ${phantom.map((e) => e.tune).join("/")} of one image; Space -> the jukebox, Escape/Back -> menu; ` +
    `peaks ${peaks.join(", ")}; ${perFrame.toFixed(3)} ms/frame`);
