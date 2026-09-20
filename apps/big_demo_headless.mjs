// Headless The B.I.G. Demo check (CODEF screen 23, TEX): the instruction screen
// hands over to the jukebox on the right frame, the screen is byte-identical to
// frames measured against the remake's own screen.js, the list navigates with the
// original's post-increment clamps, and an entry with no SNDH behind it plays
// NOTHING rather than something else. The numbered sections below say what each
// check is; the one that matters most is 6, the no-silent-substitution guard.
//
//   node apps/big_demo_headless.mjs [cart.wasm] [--break nav|music|noop|songs|screens]
// --break drives the list through demo.key() (ignored by the screen), expects the
// neighbouring subtune, runs the silent-entry test on a PLAYABLE entry, points
// one entry at an SNDH that is not on disk, or never presses the sub-screen
// keys at all: each must be caught, which is what makes the checks worth
// running.
import { readFile } from "node:fs/promises";
import { createHash } from "node:crypto";
import { performance } from "node:perf_hooks";
import { boot, sndhPlay } from "./big_demo_machine.mjs";
import { readList, checkSongs, ENTRIES, CURSOR, DIGITAL } from "./big_demo_list.mjs";

const TOP = 5, LEFT = 40, CW = 320, CH = 270; // the screen, centred in the 400x280 plane
const WAIT = 200; // wait()'s `if((mytempo++)>=200)`; frame 201 is go()'s first
const WANT_SONG = "big/Ace_2.sndh", WANT_TUNE = 1; // wait() ends on "Big - Ace 2.ym"
const ART = "apps/zig/assets/screens/big_demo";
const BAND_TOP = 52, BAND_ROW = 60, CYCLE_W = 32, CYCLE_H = 5; // the top band; one cycle tile
const LIST_Y = 92, LIST_X = 17, LIST_W = 280, ROWS = 5, RH = 8, RULES = [107, 115];
const RED = [255, 0, 0]; // mylist3.fill('#ff0000'), the cursor row
// Whole-frame SHA-256s of an input-free run.
//
// RE-BAKED TWICE on 2026-09-19, both times by design.
//
// (1) big/list.zig became TEX's OWN 118-row table, ripped out of the running
//     demo's memory, so the five rows on screen at curent = 2 are the real ones
//     and carry their durations.
//
//     1    6d2299731df2  ->  6d2299731df2   UNCHANGED
//     201  59ca35735a78  ->  f56c8c8f606c
//     400  a1a63a604e7e  ->  caafe3b57044
//     1000 c5724b7a028b  ->  1c71895efdfc
//
// (2) The rules' pulse became the real demo's 43-word gradient stepped once a
//     frame, instead of the remake's 30 greys stepped every second frame.
//
//     1    6d2299731df2  ->  6d2299731df2   UNCHANGED
//     201  f56c8c8f606c  ->  aa9a1176ac3a
//     400  caafe3b57044  ->  36975381270f
//     1000 1c71895efdfc  ->  006f3eff520e
//
// Frame 1 is the wait() instruction screen, which draws no list and whose rules
// are not yet the gradient's — that it did NOT move either time is the control.
// For (2) the confinement was also checked directly: rendering the old and new
// carts side by side and hashing each content row, EXACTLY rows 107 and 115
// differ, on all three frames. A re-bake without that check would hide any
// regression the new hash happened to absorb.
//
// The earlier baseline was the build whose every row outside the three cycler
// bands matched a Chrome replay of the remake's screen.js exactly (0 px wrong
// on frames 1, 201, 202, 400, 600 and 1000). That comparison no longer applies
// to the LIST ROWS, deliberately: they are the demo's, not the remake's.
// Everything outside the list block is still the replayed screen.
// BIG_DEMO_HASHES=1 re-prints them if the screen is deliberately changed.
const FRAMES = {
    1: "6d2299731df28521dba73affc2ae7856d66139042e69b340240d8a56b8e37e2e", 201: "aa9a1176ac3a4dad97e5a0c998351e35e7df7bf385fd625fc837e37b9cc4aae0",
    400: "36975381270f74bdf741c0b703166be07efe0f974ddca0cb72f56e377ed1cf2a", 1000: "006f3eff520e9f569b0b49be88a919af6c54ff633f4a1430ad673a991a542438",
};
let key3 = "key 3 not reached", key2 = "key 2 not reached", key1 = "key 1 not reached", keyb = "key B not reached";
const argv = process.argv.slice(2), bi = argv.indexOf("--break");
const brk = bi >= 0 ? argv.splice(bi, 2)[1] : null;
if (brk && !["nav", "music", "noop", "songs", "screens"].includes(brk)) throw new Error(`--break ${brk}: nav|music|noop|songs|screens`);
const errors = [];

// The list is the screen's own data (big_demo_list.mjs reads it), and every SNDH
// it names must be on disk: a missing file plays SILENCE, which is exactly what
// the four entries with no SNDH do — an accidental no-op hiding among deliberate ones.
const LIST = readList(brk);
const songs = checkSongs(LIST);
if (LIST.length !== ENTRIES) errors.push(`big/list.zig holds ${LIST.length} entries, TEX's list is ${ENTRIES}`);
// The clamp is `mylist.length - 3`, so the Digital Department row is reachable
// ONLY if it sits exactly there. Appending it after the trailing blank and
// "END OF LIST" would leave it selectable by nobody, silently.
if (!/DIGITAL DEPARTMENT/.test(LIST[DIGITAL]?.label ?? "")) errors.push(`entry ${DIGITAL} is "${LIST[DIGITAL]?.label.trim()}", not the Digital Department row: the clamp cannot reach it`);
if (LIST[DIGITAL]?.song) errors.push("the Digital Department row has a tune: it opens a screen, it does not play");
if (CURSOR[1] !== LIST.length - 3) errors.push(`the cursor clamp ${CURSOR[1]} is not mylist.length-3 = ${LIST.length - 3}`);
errors.push(...songs.errors);
const playable = LIST.findIndex((e, n) => n > CURSOR[0] && e.song);
// One of the four entries the archive has no SNDH for; not one of the separators.
const silent = LIST.findIndex((e) => !e.song && /THALAMUS|DELTA +PREVIEW|V8 *#2/.test(e.label));
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

/// Enter a sub-screen. --break screens does NOT press the key, so every check
/// in sections 7..10 is then reading the jukebox instead of the screen it
/// names. If any of them still passes, that check was not reading the screen.
const enter = (cp) => { if (brk !== "screens") demo.key(cp); step(); };

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
///
/// It checks EVERY border row on BOTH sides, not a sample. The four-probe
/// version this replaced sat at the vertical midpoint, which is inside the one
/// long flat run — it would have passed against a border of nothing but panel
/// grey, i.e. against the bug it was meant to catch once the border grew
/// content. The table below is the same measurement big/border.zig carries,
/// transcribed independently: a typo has to be made twice to pass.
{
    const PH = machine.hwPhysHeight();
    const raw = pixels();
    const rgb = (x, y) => { const o = (y * PW + x) * 4; return [raw[o], raw[o + 1], raw[o + 2]]; };
    // ST level x 32, which is main.png's own grey ladder.
    const g = (n) => [n * 32, n * 32, n * 32];
    const PANEL = g(5);
    // [lastContentRow, left, right] — the rule rows (107, 115) are PANEL here
    // because this runs during wait(), before go() hands them to the gradient.
    const RUNS = [
        [93, 5, 5], [94, 5, 4], [98, 5, 3], [99, 5, 4], [146, 5, 5],
        [147, 5, 4], [151, 5, 3], [152, 5, 4], [213, 5, 5],
        [214, 6, 6], [215, 7, 7], [216, 6, 6], [217, 5, 5], [218, 4, 4], [219, 3, 3],
        [223, 5, 5], [224, 4, 4], [228, 3, 3], [229, 4, 4], [239, 5, 5],
        [240, 6, 6], [241, 7, 7], [242, 6, 6], [243, 5, 5], [244, 4, 4], [245, 3, 3],
        [249, 5, 5], [250, 4, 4], [254, 3, 3], [255, 4, 4], [269, 5, 5],
    ];
    let y = 0, bad = 0, split = 0;
    for (const [last, l, r] of RUNS)
        for (; y <= last; y++) {
            const got = [rgb(4, TOP + y), rgb(PW - 5, TOP + y)];
            for (const [i, what, want] of [[0, "left", g(l)], [1, "right", g(r)]])
                if (!same(got[i], want) && bad++ < 4)
                    errors.push(`${what} border, content row ${y}: rgb(${got[i]}), wanted rgb(${want})`);
            if (!same(got[0], got[1])) split++; // counted off the PIXELS, not the table
        }
    // The bands above and below the content, which the border table does not cover.
    for (const [what, py] of [["top band", 2], ["bottom band", PH - 3]])
        if (!same(rgb(PW >> 1, py), PANEL))
            errors.push(`${what} is rgb(${rgb(PW >> 1, py)}) — it must be the screen's own grey rgb(${PANEL}), or the join shows`);
    // The song-list frame's shadow is the ONLY one-sided feature, and it is the
    // whole reason this border is more than a colour: on the machine it is the
    // HBL writing colour 0 TWICE on those lines, so the left shows the early
    // value and the right the late one. Counted off the rendered pixels, so a
    // border that goes symmetric fails here even if someone flattens the table
    // above to match it.
    if (split !== 12) errors.push(`${split} rendered rows have different left and right borders, the real screen has 12`);
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
/// 7. KEY 3, the raster field. The picture advertises "Hit 1...3 for
/// Psych-O-Screens" and the remake binds none of them. What is checked here is
/// the SCHEDULE, because that is what was measured off the real screen and it
/// is what a wrong line, a wrong band width or a wrong window offset breaks:
///
///   lines 0,1    black
///   4n+2, 4n+4   FLAT, one colour across all 320 (the two per-line words)
///   4n+3, 4n+5   27 bands, boundaries at x = 9 + 12k
///
/// 12 px is one `move.w` to $FF8240 at 1 pixel per cycle, and 320/12 = 26.7 is
/// why there are 27 of them. The first band is 9 px because the display opens
/// in the middle of a write, and the last is 11 for the same reason.
{
    enter(51); // '3'
    const px = pixels(), PH = machine.hwPhysHeight();
    const TOP3 = (PH - 200) >> 1, L3 = (PW - 640) >> 1; // 320x200, borders closed
    const rgb = (x, y) => { const o = ((TOP3 + y) * PW + L3 + 2 * x) * 4; return `${px[o]},${px[o+1]},${px[o+2]}`; };
    // The cross sits at x 125..193, y 86..154 in the bitmap, and it draws OVER
    // the field — so every check below reads the columns it cannot reach.
    // Excluding it is a declared blind spot, so the cross gets its own check.
    const CLEAR = [...Array(120).keys()].concat([...Array(120).keys()].map((x) => x + 200));
    const edges = (y) => CLEAR.filter((x, i) => i > 0 && CLEAR[i - 1] === x - 1 && rgb(x, y) !== rgb(x - 1, y));
    let flat = 0, field = 0, offgrid = 0, wrongCount = 0;
    for (let y = 0; y < 200; y++) {
        const e = edges(y);
        if (y < 2) { if (e.length) errors.push(`key 3 line ${y} is not flat`); continue; }
        if ((y - 2) % 2 === 0) {
            if (e.length === 0 && rgb(0, y) === rgb(319, y)) flat++;
            else errors.push(`key 3 line ${y} should be one flat per-line colour across the whole width`);
            continue;
        }
        field++;
        // Every edge on the 12-px grid, AND every band a constant colour. The
        // second half is the one that cannot be fooled: two neighbouring bands
        // carrying the same word show no edge at all, so counting edges gives a
        // number that moves with the data while "each band is flat" does not.
        for (const x of e) if (x % 12 !== 9) offgrid++;
        for (const x0 of CLEAR) {
            // and not a band that reaches into the cross box at x 125..193
            if (x0 % 12 !== 9 || x0 + 12 > 320 || (x0 + 12 > 125 && x0 < 194)) continue;
            const c = rgb(x0, y);
            for (let x = x0 + 1; x < x0 + 12 && x < 320; x++) if (rgb(x, y) !== c) { wrongCount++; break; }
        }
        if (rgb(0, y) === rgb(119, y) && rgb(200, y) === rgb(319, y)) wrongCount++; // not a field at all
    }
    if (flat !== 99) errors.push(`key 3 has ${flat} flat per-line rows, the schedule gives 99`);
    if (field !== 99) errors.push(`key 3 has ${field} banded rows, the schedule gives 99`);
    if (wrongCount) errors.push(`${wrongCount} key-3 bands are not a constant colour across their 12 px`);
    if (offgrid) errors.push(`${offgrid} key-3 band boundaries are off the x = 9 + 12k grid`);
    // The cross is the only thing in the bitmap: 1,224 px of 64,000, at
    // x 125..193, y 86..154. If it stopped being drawn the field alone would
    // still pass every check above, which is exactly the blind spot to close.
    let crossRows = 0;
    for (let y = 86; y <= 154; y++) {
        for (let x = 126; x <= 193; x++) if (rgb(x, y) !== rgb(x - 1, y) && (x % 12 !== 9)) { crossRows++; break; }
    }
    if (crossRows < 60) errors.push(`the key-3 cross shows on ${crossRows} of its 69 rows`);
    key3 = `key 3: ${field} banded + ${flat} flat rows on the 12 px grid, cross on ${crossRows}/69`;
    // Space comes back to the jukebox, and the jukebox comes back intact.
    demo.key(32); step(); step();
    if (hashFrame() === waitHash) errors.push("leaving key 3 did not restore the jukebox");
}

/// 8. KEY 2, the 512-colour Psych-O-Screen. A FULL 16-colour palette per
/// scanline for display lines 45..194, played by this plane's own HBL — the
/// bitmap is blitted once and never touched, and every bit of the motion is in
/// the palette. What is checked is that the palette really is PER LINE, because
/// a static palette would still draw a plausible-looking screen.
///
/// Not a hash, and not a comparison against a capture: the demo generates this
/// table from a PRNG seeded with the 200 Hz clock and the live beam position,
/// so two runs of the REAL demo do not agree either.
{
    enter(50); step(); // '2'
    const px = pixels(), PH = machine.hwPhysHeight();
    const TOP2 = (PH - 200) >> 1;
    const rgb = (x, y) => { const o = ((TOP2 + y) * PW + ((PW - 640) >> 1) + 2 * x) * 4; return `${px[o]},${px[o+1]},${px[o+2]}`; };
    const rowColours = (y) => new Set([...Array(320).keys()].map((x) => rgb(x, y)));
    // Inside the band: lines differ from each other, and each carries several
    // colours. Two lines 100 apart agreeing on every pixel would mean one
    // palette for the whole screen.
    let sameAsFirst = 0, thin = 0;
    const first = [...Array(320).keys()].map((x) => rgb(x, 60)).join("|");
    for (let y = 46; y < 194; y++) {
        if ([...Array(320).keys()].map((x) => rgb(x, y)).join("|") === first) sameAsFirst++;
        if (rowColours(y).size < 3) thin++;
    }
    if (sameAsFirst > 4) errors.push(`${sameAsFirst} of key 2's 148 banded lines are pixel-identical to line 60: the palette is not per line`);
    if (thin > 40) errors.push(`${thin} of key 2's banded lines carry fewer than 3 colours`);
    // Outside the band the VBL's base palette is live, and it has only SIX
    // distinct words: $18F24 = 0000 0007 0000 x4 0110 0330 0660 0000 x6 0700.
    // A line there showing a seventh colour means the table leaked out of its
    // 45..194 range, which is the one thing that could silently go wrong in a
    // handler that runs on all 280 physical rows.
    for (const y of [10, 30, 197]) if (rowColours(y).size > 6) errors.push(`key 2 line ${y} is outside the table's band but shows ${rowColours(y).size} colours, the base palette has 6`);
    key2 = `key 2: per-line palette live on 148 lines, ${thin} thin`;
    demo.key(32); step(); step();
    if (hashFrame() === waitHash) errors.push("leaving key 2 did not restore the jukebox");
}

/// 9. KEY 1, Colorright. Three things, each the mechanism rather than a hash:
/// the 15-row band is 15 rows and carries $1478A's words in order; it SWEEPS
/// one line a frame; and the stars ACCUMULATE — the real demo removed not one
/// star over 400 frames, so a port that clears, moves or re-randomises them is
/// wrong in a way no single frame would show.
{
    enter(49); // '1'
    const PH = machine.hwPhysHeight(), TOP1 = (PH - 200) >> 1;
    const at1 = (x, y) => { const px = pixels(), o = ((TOP1 + y) * PW + 2 * x) * 4; return `${px[o]},${px[o+1]},${px[o+2]}`; };
    // The band is read in the SIDE BORDER, x = 4, where no picture pixel can
    // reach it: on this screen colour 0 is the border, which is how a raster
    // meant for the picture shows up out there at all.
    const bandRows = () => { const out = []; for (let y = -30; y < 220; y++) if (at1(4, y) !== "0,0,0") out.push(y); return out; };
    const first = bandRows();
    if (first.length !== 15) errors.push(`key 1's band is ${first.length} rows, d3 = $E counts 15`);
    if (first.length && first[14] - first[0] !== 14) errors.push("key 1's band rows are not contiguous");
    const colours = first.map((y) => at1(4, y));
    if (new Set(colours).size !== 15) errors.push(`key 1's band shows ${new Set(colours).size} distinct colours over 15 rows`);
    step();
    const second = bandRows();
    if (!second.length || second[0] - first[0] !== 1) errors.push(`key 1's split moved ${second.length ? second[0] - first[0] : "nowhere"} lines in a frame, the counter steps by 1`);
    // Stars: count, then count again 60 frames later. Every pixel that was a
    // star must still be one, and there must be more of them.
    const starPx = () => { const out = new Set(); for (let y = 23; y <= 175; y++) for (let x = 44; x <= 274; x += 2) if (at1(x, y) !== "0,0,0") out.add(y * 320 + x); return out; };
    const before = starPx();
    for (let f = 0; f < 60; f++) step();
    const after = starPx();
    const gone = [...before].filter((k) => !after.has(k)).length;
    if (gone) errors.push(`${gone} of key 1's stars vanished over 60 frames; the real demo erases none`);
    if (after.size <= before.size) errors.push(`key 1's stars went ${before.size} -> ${after.size}; the field only ever grows`);
    // The panel below the picture, in its own sixteen colours.
    const panel = new Set(); for (let x = 20; x < 360; x += 3) panel.add(at1(x, 215));
    if (panel.size < 4) errors.push(`key 1's COLORRIGHT panel at display line 215 shows ${panel.size} colours`);
    key1 = `key 1: band 15 rows sweeping 1/frame, stars ${before.size} -> ${after.size} with 0 erased`;
    demo.key(32); step(); step();
    if (hashFrame() === waitHash) errors.push("leaving key 1 did not restore the jukebox");
}

/// 10. KEY B, the B.I.G. scroller. The rainbow is STATIC and exact — 32 words,
/// two display lines each, 66..129, then the pens hold the last one. What is
/// checked is that it is static (the VBL resets its cursor every frame, so a
/// gradient that crawls means the cursor is being carried), that the band
/// really is 2 lines a colour, and that the glyphs MOVE over it.
{
    enter(66); // 'B'
    const PH = machine.hwPhysHeight(), TOPB = (PH - 200) >> 1;
    const atB = (x, y) => { const px = pixels(), o = ((TOPB + y) * PW + 2 * ((PW - 640) / 4 | 0) + 2 * x) * 4; return `${px[o]},${px[o+1]},${px[o+2]}`; };
    // Read the gradient off the glyph pixels: sample each band row's set of
    // colours and take the one that is not a cave grey.
    const bandRow = (y) => new Set([...Array(320).keys()].map((x) => atB(x, y)));
    let twoLine = 0;
    for (let y = 68; y < 130; y += 2) {
        const a = [...bandRow(y)].sort().join("|"), b = [...bandRow(y + 1)].sort().join("|");
        if (a !== b) twoLine++;
    }
    // POSITIONS, not colour sets: a horizontal shift leaves the set of colours
    // on a row untouched, so a set comparison would pass on a frozen scroller.
    const rowPx = (y) => [...Array(320).keys()].map((x) => atB(x, y)).join("|");
    const before = [100, 110, 120].map(rowPx);
    const tint = [...Array(31).keys()].map((i) => [...bandRow(68 + 2 * i)].sort().join("|"));
    for (let f = 0; f < 16; f++) step();
    if ([100, 110, 120].map(rowPx).join("#") === before.join("#")) errors.push("key B's band did not change over 16 frames: the glyphs are not scrolling");
    // But the RAINBOW must not have moved with them: the VBL resets its cursor
    // every frame, so the letters travel through a fixed gradient.
    const tint2 = [...Array(31).keys()].map((i) => [...bandRow(68 + 2 * i)].sort().join("|"));
    if (tint.filter((v, i) => v !== tint2[i]).length > 6) errors.push("key B's gradient moved with the glyphs; it is reset every frame and does not crawl");
    if (twoLine > 6) errors.push(`${twoLine} of key B's 31 colour pairs differ between their two lines; the ramp is one word per TWO scanlines`);
    keyb = `key B: 31 two-line ramp steps, glyphs moving`;
    demo.key(32); step(); step();
    if (hashFrame() === waitHash) errors.push("leaving key B did not restore the jukebox");
}
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
const hLast1 = nav(1, CURSOR[1] - CURSOR[0] - 1); // 2 -> one above the clamp
const hLast = nav(1); // ...and on to the clamp, the last cursor position
if (hLast === hLast1) errors.push(`Down from ${CURSOR[1] - 1} did not move: the clamp is one entry early`);
if (nav(1, 5) !== hLast) errors.push(`Down past ${CURSOR[1]} moved: \`if((curent++)>=mylist.length-3)\` does not clamp`);
if (nav(0) !== hLast1) errors.push(`Up from ${CURSOR[1]} did not come back one entry`);
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
    `peak ${r.peak?.toFixed(3)}; ${key3}; ${key2}; ${key1}; ${keyb}; ${perFrame.toFixed(3)} ms/frame`);
