// Headless The B.I.G. Demo check (CODEF screen 23, TEX): the instruction screen
// hands over to the jukebox on the right frame, the screen is byte-identical to
// frames measured against the remake's own screen.js, the list navigates with the
// original's post-increment clamps, and an entry with no SNDH behind it plays
// NOTHING rather than something else. The numbered sections below say what each
// check is; the one that matters most is 6, the no-silent-substitution guard.
//
//   node apps/big_demo_headless.mjs [cart.wasm] [--break nav|music|noop|songs]
// --break drives the list through demo.key() (ignored by the screen), expects the
// neighbouring subtune, runs the silent-entry test on a PLAYABLE entry, or points
// one entry at an SNDH that is not on disk: each must be caught, which is what
// makes the checks worth running.
import { readFile } from "node:fs/promises";
import { createHash } from "node:crypto";
import { performance } from "node:perf_hooks";
import { boot, sndhPlay } from "./big_demo_machine.mjs";
import { readList, checkSongs, ENTRIES, CURSOR } from "./big_demo_list.mjs";

const TOP = 5, LEFT = 40, CW = 320, CH = 270; // the screen, centred in the 400x280 plane
const WAIT = 200; // wait()'s `if((mytempo++)>=200)`; frame 201 is go()'s first
const WANT_SONG = "big/Ace_2.sndh", WANT_TUNE = 1; // wait() ends on "Big - Ace 2.ym"
const ART = "apps/zig/assets/screens/big_demo";
const BAND_TOP = 52, BAND_ROW = 60, CYCLE_W = 32, CYCLE_H = 5; // the top band; one cycle tile
const LIST_Y = 92, LIST_X = 17, LIST_W = 280, ROWS = 5, RH = 8, RULES = [107, 115];
const RED = [255, 0, 0]; // mylist3.fill('#ff0000'), the cursor row
// Whole-frame SHA-256s of an input-free run, from the build whose every row
// outside the three cycler bands matched a Chrome replay of the remake's
// screen.js exactly (0 px wrong on frames 1, 201, 202, 400, 600 and 1000),
// re-baked when the colour bands became cycle.png's real PATTERN. Frame 1 is
// the wait screen, which has no bands: its hash is unchanged across that fix.
// BIG_DEMO_HASHES=1 re-prints them if the screen is deliberately changed.
const FRAMES = {
    1: "6d2299731df28521dba73affc2ae7856d66139042e69b340240d8a56b8e37e2e", 201: "59ca35735a784ea4be8aeac1cc6120fcc2a952b43cf380598016c7fad5ac2423",
    400: "a1a63a604e7e3dead42d9d4a09e24a3e9cd48bc43393f1bfaa698376f3daca6b", 1000: "c5724b7a028b63f940ddb833cb7f5cf551e07ec0414911c5b4fc80b3ac1e5148",
};

const argv = process.argv.slice(2), bi = argv.indexOf("--break");
const brk = bi >= 0 ? argv.splice(bi, 2)[1] : null;
if (brk && !["nav", "music", "noop", "songs"].includes(brk)) throw new Error(`--break ${brk}: nav|music|noop|songs`);
const errors = [];

// The list is the screen's own data (big_demo_list.mjs reads it), and every SNDH
// it names must be on disk: a missing file plays SILENCE, which is exactly what
// the four entries with no SNDH do — an accidental no-op hiding among deliberate ones.
const LIST = readList(brk);
const songs = checkSongs(LIST);
if (LIST.length !== ENTRIES) errors.push(`big/list.zig holds ${LIST.length} entries, TEX's list is ${ENTRIES}`);
errors.push(...songs.errors);
const playable = LIST.findIndex((e, n) => n > CURSOR[0] && e.song);
// One of the four entries the archive has no SNDH for; not one of the separators.
const silent = LIST.findIndex((e) => !e.song && /THALAMUS|DELTA PREVIEW|V8 *#2/.test(e.label));
const want = LIST[playable];
if (silent < 0) errors.push("no unmapped tune (Thalamus / Delta preview / V8 #2) found in big/list.zig");

const { memory, machine, demo } = await boot(argv[0] || "docs/demo-big_demo.wasm");
const PW = machine.hwPhysWidth(), dec = new TextDecoder(); // 800: the visible x is DOUBLED
let frame = 0, song = null, tune = 0, songAt = -1, cartMs = 0;

/// The host loop: clear, frame, render every enabled plane. HBL handlers only
/// run inside hwRenderPlane, and this screen's open borders ARE a per-plane HBL.
function step() {
    const t0 = performance.now();
    machine.hwClear();
    demo.frame(1000 / 60);
    cartMs += performance.now() - t0; // the cart's own cost, not the machine's
    for (let p = 0; p < 4; p++) if (demo.isPlaneEnabled(p)) machine.hwRenderPlane(p);
    frame++;
    if (!demo.pollSongRequest()) return;
    song = dec.decode(new Uint8Array(memory.buffer, demo.songNamePtr(), demo.songNameLen()));
    tune = demo.songTune(); songAt = frame;
}
const runTo = (f) => { while (frame < f) step(); };
const pixels = () => new Uint8Array(memory.buffer, machine.hwPhysicalPtr(), PW * machine.hwPhysHeight() * 4);
const at = (px, x, y) => { const o = ((TOP + y) * PW + 2 * (LEFT + x)) * 4; return [px[o], px[o + 1], px[o + 2], px[o + 3]]; };
const same = (a, b) => a[0] === b[0] && a[1] === b[1] && a[2] === b[2];

function hashRows(y0, y1, x0, x1, skip = []) {
    const px = pixels(), h = createHash("sha256");
    for (let y = y0; y < y1; y++) if (!skip.includes(y))
        for (let x = x0; x < x1; x++) h.update(Buffer.from(at(px, x, y)));
    return h.digest("hex");
}
const hashFrame = () => hashRows(0, CH, 0, CW);
/// The list block alone, minus the two animated rules: stable unless the cursor
/// or the highlight moves, so it isolates navigation from the scroller.
const hashList = () => hashRows(LIST_Y, LIST_Y + ROWS * RH, LIST_X, LIST_X + LIST_W, RULES);

/// Up (0) / Down (1) arrive through input(); --break nav sends them as keys,
/// which the screen does not bind, so nothing should move.
function nav(dir, n = 1) {
    for (let k = 0; k < n; k++) brk === "nav" ? demo.key(dir === 0 ? 38 : 40) : demo.input(dir);
    step();
    return hashList();
}
// 1. wait(): static, silent, and the borders really are open
runTo(1);
const waitHash = hashFrame(), px1 = pixels();
for (const y of [1, CH - 2]) if (at(px1, 10, y)[3] !== 255) errors.push(`content row ${y} is transparent: the borders never opened`);

/// THE BORDER. hashFrame() covers the 320x270 CONTENT only, so the border around
/// it was never looked at by anything — and it shipped BLACK while the top row of
/// main.png and wait.png is rgb(160,160,160) across all 640 px, leaving a visible
/// seam on the live site until Matt spotted it by eye. An excluded region is a
/// declared blind spot; this is the check that region never had.
/// Samples the physical framebuffer OUTSIDE the content: the opened bands above
/// and below, and the closed side margins.
{
    const PANEL = [160, 160, 160];
    const raw = pixels(), PH = machine.hwPhysHeight();
    const rgb = (x, y) => { const o = (y * PW + x) * 4; return [raw[o], raw[o + 1], raw[o + 2]]; };
    const probes = [
        ["top band", PW >> 1, 2],
        ["bottom band", PW >> 1, PH - 3],
        ["left margin", 4, PH >> 1],
        ["right margin", PW - 5, PH >> 1],
    ];
    for (const [what, x, y] of probes) {
        const got = rgb(x, y);
        if (!same(got, PANEL))
            errors.push(`${what} at (${x},${y}) is rgb(${got}) — the border must be the screen's own grey rgb(${PANEL}), or the join shows`);
    }
}
runTo(WAIT);
if (hashFrame() !== waitHash) errors.push("the instruction screen is not static over its 200 frames");
if (song) errors.push(`music started at frame ${songAt}, during wait()`);
// 2. go() takes over on frame 201, with the first tune
runTo(WAIT + 1);
const wantTune = brk === "music" ? WANT_TUNE + 1 : WANT_TUNE;
if (songAt !== WAIT + 1) errors.push(`go() asked for music at frame ${songAt}, wait() hands over at ${WAIT + 1}`);
if (song !== WANT_SONG || tune !== wantTune) errors.push(`first song ${JSON.stringify(song)} #${tune}, wanted "${WANT_SONG}" #${wantTune}`);
const got = { 1: waitHash, [WAIT + 1]: hashFrame() };
// 3. the rasters. cycle.png is a tile SHEET (8 tiles of 32x5), not eight flat
// colours, so this checks the whole PATTERN and reads back WHICH tile is showing
// — a flat fill and a one-pixel sample both passed the check this replaced.
const main = new Uint8Array(await readFile(`${ART}/main.raw`));
const cyc = new Uint8Array(await readFile(`${ART}/cycle.raw`));
const pal = new Uint8Array(await readFile(`${ART}/pal.dat`));
const holes = [...Array(CW).keys()].filter((x) => main[BAND_ROW * CW + x] === 0);
const TROW = (BAND_ROW - BAND_TOP) % CYCLE_H; // the tile row this screen row lands on
/// The cycle tile the band is showing, by matching every pixel main.png lets
/// through, or -1 if the band is not any tile of the sheet.
function bandTile() {
    const px = pixels();
    for (let t = 0; t < 8; t++) if (holes.every((x) => {
        const i = cyc[(t * CYCLE_H + TROW) * CYCLE_W + (x % CYCLE_W)] * 4, g = at(px, x, BAND_ROW);
        return g[0] === pal[i] && g[1] === pal[i + 1] && g[2] === pal[i + 2];
    })) return t;
    return -1;
}
// texbg += 0.4 accumulated in double, NOT floor(0.4f): the drift is the effect.
const tiles = [], wantTiles = [];
for (let f = 0, texbg = 0; f < 24; f++, texbg += 0.4) wantTiles.push(Math.floor(texbg) % 8);
for (let f = 0; f < 24; f++) { tiles.push(bandTile()); step(); }
if (holes.length < 20) errors.push(`only ${holes.length} band px show through main.png row ${BAND_ROW}: the check is vacuous`);
if (tiles.join() !== wantTiles.join()) errors.push(`band tiles over 24 frames ${tiles.join()}, texbg += 0.4 gives ${wantTiles.join()}`);
// 4. whole-frame fingerprints, and the playing row's filled bar
for (const f of [400, 1000]) { runTo(f); got[f] = hashFrame(); }
if (process.env.BIG_DEMO_HASHES) console.log(JSON.stringify(got, null, 1));
for (const [f, want] of Object.entries(FRAMES))
    if (got[f] !== want) errors.push(`frame ${f}: ${got[f]?.slice(0, 12)} is not the measured ${want.slice(0, 12)}`);
let bar = 0; // the cursor row is filled ('source-over'), the others glyphs only
for (let x = 0; x < LIST_W; x++) if (same(at(pixels(), LIST_X + x, LIST_Y + 2 * RH + 4), RED)) bar++;
if (bar < 150) errors.push(`the playing row is ${bar} px of #ff0000 wide, it should be a filled bar`);
// 5. Up/Down clamp at exactly [2, 113]
const atTop = hashList();
if (nav(0, 5) !== atTop) errors.push("Up at the top of the list moved the cursor: `if((curent--)<=2)` does not clamp");
if (nav(1) === atTop) errors.push("Down did not move the cursor");
if (nav(0) !== atTop) errors.push("Up did not come back to the top of the list");
const h112 = nav(1, CURSOR[1] - CURSOR[0] - 1); // 2 -> 112
const h113 = nav(1); // 112 -> 113, the last cursor position
if (h113 === h112) errors.push(`Down from ${CURSOR[1] - 1} did not move: the clamp is one entry early`);
if (nav(1, 5) !== h113) errors.push(`Down past ${CURSOR[1]} moved: \`if((curent++)>=mylist.length-3)\` does not clamp`);
if (nav(0) !== h112) errors.push(`Up from ${CURSOR[1]} did not come back one entry`);
// 6. Return: a mapped entry plays, an unmapped one plays NOTHING
nav(0, 200); // back to the top, whatever the clamp did
nav(1, playable - CURSOR[0]);
demo.key(13); step();
if (song !== want.song || tune !== want.tune) errors.push(`Return on "${want.label.trim()}" asked for ${JSON.stringify(song)} #${tune}, wanted "${want.song}" #${want.tune}`);
const target = brk === "noop" ? playable : silent;
nav(0, 200);
nav(1, target - CURSOR[0]);
const before = hashList(), songBefore = songAt;
demo.key(13); step();
if (songAt !== songBefore) errors.push(`Return on "${LIST[target].label.trim()}" (no SNDH) asked for ${JSON.stringify(song)} #${tune}: a silent entry must request nothing`);
if (hashList() === before) errors.push("Return did not move the highlight: KeyCheck sets curentlplay whatever the entry is");
// 7. the tune really makes sound, and the frame cost
const r = await sndhPlay(want.song, want.tune), perFrame = cartMs / frame;
if (r.why) errors.push(`${want.song}: ${r.why}`);
else if (r.peak <= 0.01 || r.stuckPc) errors.push(`${want.song} #${want.tune}: peak ${r.peak.toFixed(4)}, stuck PC ${r.stuckPc}`);
if (perFrame > 4) errors.push(`cart takes ${perFrame.toFixed(3)} ms/frame`);

if (brk) {
    const caught = errors.length > 0;
    console.log(caught ? `=> PASS ✅ fail proof: --break ${brk} was caught (${errors[0]})`
        : `=> FAIL ❌ fail proof: --break ${brk} passed every check`);
    process.exit(caught ? 0 : 1);
}
if (errors.length) { console.error(`big_demo: WRONG\n  ${errors.slice(0, 12).join("\n  ")}`); process.exit(1); }
if (songs.orphans.length) console.log(`big_demo: ${songs.orphans.length} SNDH in docs/music/big/ that no entry names: ${songs.orphans.join(" ")}`);
console.log(`big_demo: FITS wait() 200 frames then go() with ${WANT_SONG} #${WANT_TUNE}; 4 frame hashes; ${LIST.length} entries, ` +
    `cursor clamps at [${CURSOR}], "${LIST[silent].label.trim()}" requests nothing; all ${songs.named} named SNDH present ` +
    `(${songs.onDisk} on disk); band tiles ${tiles.slice(0, 6).join("")}... follow texbg += 0.4; ${want.song.split("/")[1]} #${want.tune} ` +
    `peak ${r.peak?.toFixed(3)}; ${perFrame.toFixed(3)} ms/frame`);
