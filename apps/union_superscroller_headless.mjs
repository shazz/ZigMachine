// Headless Union Demo TCB2 WOW!-SCROLLER check (apps/zig/scenes/union_superscroller.zig).
//
// 1. Loader. The cart starts on the TEX loader panel (depack fx = tex_loader):
//    every depack frame shows only the panel's ink #C0A000 on black, the panel
//    really shows, and the depack takes the ceil(140601 / (5 * 280)) = 101 frames
//    its pacing gives. The screen starts on the frame it ends (its song request).
// 2. Screen. Booted with the hub's return note for this door (scroll 5000), frame
//    for frame against apps/union_superscroller_replay.mjs started at that
//    offset. The replay follows screen.js + codef_scrolltext.js with Chrome's
//    fractional-y filtering, and matches the remake in Chrome at 0 px on 29
//    frames (1..20, 60, 61, 119..121, 200, 500, 1234, 3000). Every pixel equal.
// 3. Music. The request is union/wow_scroller.sndh tune 1, and the real audio
//    modules play it: SNDH mode, no stuck PC, every second audible.
// 4. Escape asks for the hub (tag union_demo); a warm frame fits 60 fps.
// 5. The note. Escape rewrites this door's note: same door, x, y, and scroll =
//    the replay's scroffset. Another door's note, or none, starts the text at 0
//    (frame 200, where letters are on screen, equals the replay at offset 0 and
//    not at 5000), and Escape leaves the scratch as it was. The scrolltext copy
//    must equal the end of the hub's menu_assets.bin, where the hub keeps it.
//
//   node apps/union_superscroller_headless.mjs [outdir] [cart.wasm] [--break speed|snap|music|note]
// --break must make it FAIL: letters at 8 (speed), whole-row back and overlay
// instead of Chrome's filtering (snap), another tune (music), or the replay
// ignoring the note (note).
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { performance } from "node:perf_hooks";
import { makeReplay } from "./union_superscroller_replay.mjs";
import { boot, capture, png, sndhPlay } from "./union_superscroller_machine.mjs";

const ASSETS = "apps/zig/assets/screens/union_superscroller";
const DEPACK_FRAMES = Math.ceil(140601 / (5 * 280)); // DEPACK_BYTES_PER_LINE = 5
const SHOTS = [1, 2, 3, 20, 60, 61, 119, 120, 121, 200, 500, 1234, 3000];
const NOTE_SHOT = 200;
const DOOR = 3; // SUPERSCROLLER_LOADER: TMX door object 3 in union3.tmx (doors.zig DOORS)
const NOTE = { door: DOOR, x: 1824, y: 127, scroll: 5000 }; // teleport '4' puts Charly at x 1824
const TEX_INK = [0xc0, 0xa0, 0x00];
const K_ESC = 0xe012;
const MODE_SNDH = 4, SECONDS = 10;

const argv = process.argv.slice(2);
const at = argv.indexOf("--break");
const brk = at >= 0 ? argv.splice(at, 2)[1] : null;
if (brk !== null && !["speed", "snap", "music", "note"].includes(brk)) throw new Error(`--break takes speed, snap, music or note, not ${brk}`);
const outDir = argv[0] || "/tmp/union_superscroller";
const cartPath = argv[1] || "docs/demo-union_superscroller.wasm";
const MUSIC = brk === "music" ? "union/thundercats.sndh" : "union/wow_scroller.sndh";

const errors = [];
await mkdir(outDir, { recursive: true });
const bin = new Uint8Array(await readFile(`${ASSETS}/superscroller.bin`));
const textBytes = await readFile(`${ASSETS}/scrolltext.txt`), text = textBytes.toString("latin1");
const hubBlob = await readFile("apps/zig/assets/screens/union_demo/menu_assets.bin"); // assets.zig bind order: the text is last
if (!hubBlob.subarray(hubBlob.length - textBytes.length).equals(textBytes)) errors.push("scrolltext.txt differs from the hub's (the end of union_demo/menu_assets.bin)");
const dec = new TextDecoder();

/// Boot with `note`, run the depack; returns the machine with `step` and the song seen.
async function start(note, label) {
    const m = await boot(cartPath, note);
    m.song = null;
    m.step = () => {
        const t0 = performance.now();
        m.demo.frame(1000 / 60);
        const ms = performance.now() - t0;
        if (m.demo.pollSongRequest()) m.song = { name: dec.decode(new Uint8Array(m.memory.buffer, m.demo.songNamePtr(), m.demo.songNameLen())), tune: m.demo.songTune() };
        return ms;
    };
    m.depackFrames = 0;
    m.maxInk = 0;
    while (!m.song && m.depackFrames <= 400) {
        m.step();
        m.depackFrames++;
        m.shot = capture(m);
        if (m.song) break;
        let ink = 0;
        for (let i = 0; i < m.shot.img.length; i += 3) {
            const c = m.shot.img.subarray(i, i + 3);
            if (c[0] === TEX_INK[0] && c[1] === TEX_INK[1] && c[2] === TEX_INK[2]) ink++;
            else if (c[0] || c[1] || c[2]) { errors.push(`${label}: depack frame ${m.depackFrames}: colour ${[...c]} is not the loader ink`); break; }
        }
        if (ink > m.maxInk) { m.maxInk = ink; if (label === "own note") await writeFile(`${outDir}/union_superscroller-loader.png`, png(320, 200, m.shot.img)); }
    }
    if (!m.song) errors.push(`${label}: the screen never started (no song request)`);
    return m;
}
const differ = (got, want, label) => {
    let wrong = 0, first = null;
    for (let i = 0; i < want.length; i += 3) if (want[i] !== got[i] || want[i + 1] !== got[i + 1] || want[i + 2] !== got[i + 2]) {
        wrong++;
        first ??= `(${(i / 3) % 320},${Math.floor(i / 3 / 320)}) got ${[...got.subarray(i, i + 3)]} want ${[...want.subarray(i, i + 3)]}`;
    }
    if (wrong) errors.push(`${label}: ${wrong} px differ from the screen.js replay, first ${first}`);
};
const scratchKept = (m, label) => { if (m.scratch().some((v, i) => v !== m.planted[i])) errors.push(`${label}: the cart wrote the ROM scratch`); };

// ---- 1. the depack behind the TEX loader panel -------------------------------
const m = await start(NOTE, "own note");
if (m.song && Math.abs(m.depackFrames - DEPACK_FRAMES) > 1) errors.push(`the screen started at frame ${m.depackFrames}, the depack pacing says ${DEPACK_FRAMES}`);
if (m.maxInk < 2000) errors.push(`the TEX loader panel barely showed: at most ${m.maxInk} ink px`);

// ---- 2. the screen against the screen.js replay, from the note's offset ----------
// The frame the depack ends is the screen's first update+draw: replay frame 1.
const replay = makeReplay(bin, text, { offset: brk === "note" ? 0 : NOTE.scroll, ...(brk === "speed" ? { speed: 8 } : brk === "snap" ? { snap: true } : {}) });
const warm = [];
let noteFrame = null;
for (let f = 1; f <= SHOTS[SHOTS.length - 1]; f++) {
    if (f > 1) { const ms = m.step(); if (f > 200) warm.push(ms); m.shot = capture(m); }
    replay.step();
    if (m.shot.planes !== 1) errors.push(`frame ${f}: ${m.shot.planes} planes enabled, the screen uses one`);
    if (!SHOTS.includes(f)) continue;
    const want = replay.draw();
    if (f === NOTE_SHOT) noteFrame = want;
    differ(m.shot.img, want, `frame ${f}`);
    if ([1, 61, 1234].includes(f)) await writeFile(`${outDir}/union_superscroller-${String(f).padStart(4, "0")}.png`, png(320, 200, m.shot.img));
}
scratchKept(m, "own note, before Escape");

// ---- 3. the music ----------------------------------------------------------------
const song = m.song;
if (!song || song.name !== MUSIC || song.tune !== 1) errors.push(`song request ${JSON.stringify(song)}, wanted "${MUSIC}" tune 1`);
else {
    const r = await sndhPlay(song.name, song.tune, SECONDS);
    if (!r.loaded) errors.push(`${song.name} not loaded: ${r.why}`);
    else if (r.mode !== MODE_SNDH || r.stuckPc || r.silent || !(r.peak > 0.01))
        errors.push(`${song.name}: mode ${r.mode}, stuck PC $${r.stuckPc.toString(16)}, ${r.silent}/${SECONDS} silent seconds, peak ${r.peak.toFixed(4)}`);
    else song.proof = `mode ${r.mode}, peak ${r.peak.toFixed(4)}, ${SECONDS} s audible, no stuck PC`;
}

// ---- 4. leaving, cost ----------------------------------------------------------
if (m.demo.pollCartRequest() !== 0) errors.push("the screen asks for a cart before being told to leave");
m.demo.key(K_ESC);
const req = m.demo.pollCartRequest();
const tag = dec.decode(new Uint8Array(m.memory.buffer, m.demo.getCartTagPtr(), m.demo.getCartTagLen()));
if (req !== 1 || tag !== "union_demo") errors.push(`Escape asks for request ${req} tag "${tag}", not 1 "union_demo"`);
const back = new DataView(m.scratch().buffer, m.scratch().byteOffset, 20), raw = m.scratch().subarray(0, 20);
const noteOk = dec.decode(raw.subarray(0, 4)) === "UNI1" && raw[4] === 14 && raw[5] === raw.subarray(6).reduce((c, v) => c ^ v, 0);
const wantScroll = replay.offset();
if (!noteOk || raw[6] !== NOTE.door || back.getFloat32(8, true) !== NOTE.x || back.getFloat32(12, true) !== NOTE.y || back.getUint32(16, true) !== wantScroll)
    errors.push(`after Escape the note is ${noteOk ? `door ${raw[6]} x ${back.getFloat32(8, true)} y ${back.getFloat32(12, true)} scroll ${back.getUint32(16, true)}` : "not a valid UNI1 record"}, want door ${NOTE.door} x ${NOTE.x} y ${NOTE.y} scroll ${wantScroll}`);
if (wantScroll === NOTE.scroll) errors.push("the scroller never moved past the note's offset: the rewrite check cannot tell");
warm.sort((a, b) => a - b);
const median = warm[warm.length >> 1], p95 = warm[Math.floor(warm.length * 0.95)];
if (!(median < 4)) errors.push(`cart update+render takes ${median?.toFixed(3)} ms a frame (median)`);

// ---- 5. another door's note, or none, starts the text at 0 ----------------------
const first = makeReplay(bin, text, {});
for (let f = 1; f <= NOTE_SHOT; f++) first.step();
const fromZero = first.draw();
if (noteFrame && fromZero.every((v, i) => v === noteFrame[i])) errors.push(`frame ${NOTE_SHOT} is the same at offset 0 and ${NOTE.scroll}: the note check cannot tell`);
for (const [label, note] of [["door 8's note", { ...NOTE, door: 8 }], ["no note", null]]) {
    const o = await start(note, label);
    for (let f = 2; f <= NOTE_SHOT; f++) o.step();
    differ(capture(o).img, fromZero, `${label}, frame ${NOTE_SHOT} (offset 0)`);
    o.demo.key(K_ESC);
    if (o.demo.pollCartRequest() !== 1) errors.push(`${label}: Escape does not leave`);
    scratchKept(o, `${label}, after Escape`);
}

if (errors.length) {
    console.error(`union_superscroller: WRONG${brk ? ` (--break ${brk})` : ""}\n  ${errors.slice(0, 12).join("\n  ")}`);
    process.exit(1);
}
console.log(`union_superscroller: TEX loader panel over ${m.depackFrames} depack frames (up to ${m.maxInk} ink px); ` +
    `screen.js replay from the door-${DOOR} note's offset ${NOTE.scroll} exact at frames ${SHOTS.join(",")}; Escape rewrites the note to scroll ${wantScroll}; door 8's note and no note start at 0 and write nothing; text = the hub's; ` +
    `${song.name} tune ${song.tune}: ${song.proof}; Escape -> union_demo; warm cart ${median.toFixed(3)} ms median, ${p95.toFixed(3)} ms p95 a frame; shots in ${outDir}`);
