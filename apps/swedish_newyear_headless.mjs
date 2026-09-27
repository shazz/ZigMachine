// Headless SWEDISH NEW YEAR DEMO driver (apps/zig/scenes/swedish_newyear.zig):
// boots the sealed machine + the cart the way docs/sealed-loader.js does and
// plays the whole key path -- menu, F1 SYNC #1, Space SYNC #2, Space menu,
// F2 TCB #1 (through the intro's end), Space TCB #2 (F1..F5), Space menu,
// F3 OMEGA, Space menu. Two references:
//   * SYNC #1 and #2 are ported from the DISK, so they are checked against the
//     REAL demo: SHA-256s of what the machine must show at fixed iterations,
//     produced by prototypes/snyd_re/sync_expect.py from the Python models of
//     the ripped routines -- models that reproduce Hatari's RAM of the running
//     demo byte for byte (NOTES.md there; the Zig is checked against the same
//     dumps by apps/zig/scenes/swedish_newyear/sync_test.zig). Per checkpoint:
//       win   the 320x200 window's palette indices (the part's screen),
//       pal   colour registers 0..15 as the plane's HBL leaves them on each of
//             the 280 lines (the rasters ARE these: per-line register values),
//       phys  the whole physical frame, borders included (a closed border is
//             colour 0 of its line, painted by the global HBL one frame ahead).
//     These parts run at the ST's 50 Hz, so the tour steps them 20 ms a frame.
//   * the menu, TCB and OMEGA are still the CODEF remake's, checked against
//     screen.js REPLAYED (apps/swedish_newyear_replay.mjs):
//       1. every shot: the WHOLE physical frame (borders included) is the
//          replay's, pixel for pixel;
//       2. the rasters are REGISTER writes: colour 0 (entry 0) after each line's
//          HBL is the replay's raster colour on that line, the bars' pixels are
//          index 0, and the per-line palette stays within 255 entries.
//   3. the music: every request is the expected tune, mapped to its SNDH and
//      subtune (or the one dump / the two TCB samples), and each SNDH plays;
//   4. Escape asks for the menu disk; the cart's frame cost is reported.
//
//   node apps/swedish_newyear_headless.mjs [outdir] [--break hbl|step|tune|border]
//     hbl     the plane's HBL is not called during a shot: the palettes/rasters fail
//     step    the cart runs one frame the reference does not: the frames fail
//     tune    a wrong subtune is reported: the music check fails
//     border  the frame before an ST shot skips hwClear: the borders' colour 0 fails
import { readFile, writeFile, mkdir } from "node:fs/promises";
import { createHash } from "node:crypto";
import { cartRam, romRam } from "../docs/wasm_hiwater.js";
import { loadAssets } from "./swedish_newyear_assets.mjs";
import { Remake, PW, PH } from "./swedish_newyear_replay.mjs";

const PAGES = 112, OFF_PAL = 0x100, REG_FB_BASE = 0x44;
const DT = 1000 / 60;
const K = { space: 32, esc: 0xe012, f: (n) => 0xe000 + n };
const SONGS = { // the remake's tune -> what the port must request (swedish_newyear.zig)
    scout: ["scout.sndh", 1], jinx1: ["Jinks.sndh", 1], icepalace: ["beyond_the_ice_palace.sndh", 1],
    sync2: ["Swedish_New_Year_Demo_Sync.sndh", 1],
    tcb_intro: ["swedish_newyear_tcb_intro.raw", 0], tcb_music: ["swedish_newyear_tcb_music.raw", 0],
    dugger1: ["dugger.sndh", 2], dugger2: ["dugger.sndh", 3], dugger3: ["dugger.sndh", 4],
    dugger4: ["swedish_newyear_dugger4.ymraw", 0], dugger5: ["dugger.sndh", 1],
};
const RASTER_PARTS = new Set([4]); // remake parts with rasters (TCB #2)

const argv = process.argv.slice(2);
const bi = argv.indexOf("--break");
const brk = bi < 0 ? null : argv.splice(bi, 2)[1];
if (brk && !["hbl", "step", "tune", "border"].includes(brk)) throw new Error(`--break takes hbl, step, tune or border, not ${brk}`);
const outdir = argv[0] || "/tmp/swedish_newyear";
await mkdir(outdir, { recursive: true });
const errors = [];
const fail = (m) => { errors.push(m); console.log(`  FAIL ${m}`); };

// ------------------------------------------------------------------ machine
async function boot() {
    const memory = new WebAssembly.Memory({ initial: PAGES, maximum: PAGES });
    let demo, rec = null;
    const machine = (await WebAssembly.instantiate(await readFile("docs/machine-video.wasm"), {
        env: {
            memory, hblDispatch: (id, p, l, x) => {
                if (!(brk === "hbl" && rec)) demo.hblDispatch(id, p, l, x);
                if (rec) rec(l);
            },
        },
    })).instance.exports;
    const romBytes = await readFile("docs/rom.wasm");
    const rom = (await WebAssembly.instantiate(romBytes, { env: { memory, hwVideoBase: machine.hwVideoBase, hwBlit: machine.hwBlit } })).instance.exports;
    machine.hwSetRomHigh(romRam(romBytes).high ?? 0);
    const noop = () => {};
    const cartBytes = await readFile("docs/demo-swedish_newyear.wasm");
    demo = (await WebAssembly.instantiate(cartBytes, {
        env: {
            memory, jsConsoleLogWrite: noop, jsConsoleLogFlush: noop, jsThrowError: noop, consoleLogJS: noop,
            hwVideoBase: machine.hwVideoBase, hwBlit: machine.hwBlit,
            hwRamBase: machine.hwRamBase, hwRamTop: machine.hwRamTop, hwRamSize: machine.hwRamSize,
            hwRamUsed: machine.hwRamUsed, hwRamFree: machine.hwRamFree,
            hwRamAlloc: machine.hwRamAlloc, hwRamMark: machine.hwRamMark,
            hwRamRelease: machine.hwRamRelease, hwRamAllocFailures: machine.hwRamAllocFailures,
            hwRomRamBase: machine.hwRomRamBase, hwRomRamTop: machine.hwRomRamTop, hwRomRamSize: machine.hwRomRamSize,
            hwRomRamUsed: machine.hwRomRamUsed, hwRomRamFree: machine.hwRomRamFree,
            ...rom,
            audioPlay: noop, audioStop: noop, loadSample: noop, beep: noop, diskReadBlock: noop,
            hostAudioStreamStart: noop, hostAudioFeed: noop, hostAudioStreamStop: noop,
        },
    })).instance.exports;
    machine.hwSetCartHigh(cartRam(cartBytes).high ?? 0);
    machine.hwInit();
    demo.boot();
    demo.skipBoot();
    const base = machine.hwVideoBase();
    return {
        memory, machine, demo,
        setRec: (f) => { rec = f; },
        palette: () => new Uint32Array(memory.buffer, base + OFF_PAL, 256),
        plane: () => new Uint8Array(memory.buffer, base + new DataView(memory.buffer, base).getUint32(REG_FB_BASE, true), PW * PH),
        regs: () => new Uint8Array(memory.buffer, demo.getYmRegsPointer(), 16),
    };
}

const A = await loadAssets();
const m = await boot();
const remake = new Remake(A);
const dec = new TextDecoder();
let n = 0, last = null;
const cost = [];
const got = [];
// The host polls ONE request a frame, so two keys between frames (Space then F3)
// leave only the last: the remake starts scout and replaces it at once.
const wanted = [];
let songsSeen = 0; // the constructor's scout is polled on the first frame
const want = () => wanted.map((t) => SONGS[t]);

/// Volumes that change in a known rhythm, so SYNC #2 flashes and OMEGA's
/// meters light and decay on both sides (the replay is fed the same bytes).
function regsAt(f) {
    const r = new Uint8Array(16);
    r[8] = (f % 23) < 3 ? (f % 7) + 8 : 12;
    r[9] = (f % 31) < 2 ? 15 - (f % 5) : 9;
    r[10] = (f % 5) === 0 ? (f % 16) : 3;
    return r;
}

function press(cart, js) {
    m.demo.key(cart);
    if (js !== null) remake.key(js);
}

function frame(paint, dt = DT, clear = true) {
    const regs = regsAt(n);
    m.regs().set(regs);
    const tc = performance.now();
    if (clear) m.machine.hwClear();
    m.demo.frame(dt);
    m.machine.hwRenderPlane(0);
    const part = remake.whichpart;
    cost[part] = cost[part] || [0, 0];
    cost[part][0] += performance.now() - tc; cost[part][1]++;
    if (m.demo.pollSongRequest()) {
        const name = dec.decode(new Uint8Array(m.memory.buffer, m.demo.songNamePtr(), m.demo.songNameLen()));
        got.push([name, m.demo.songTune()]);
    }
    remake.paint = paint;
    last = remake.frame(dt, regs);
    if (remake.songs.length > songsSeen) wanted.push(remake.songs[remake.songs.length - 1]);
    songsSeen = remake.songs.length;
    n++;
}

async function shot(name) {
    const lines = new Map();
    m.setRec((l) => { lines.set(l, Uint32Array.from(m.palette())); });
    m.machine.hwRenderPlane(0);
    m.setRec(null);
    const pw = m.machine.hwPhysWidth();
    const pfb = new Uint8Array(m.memory.buffer, m.machine.hwPhysicalPtr(), pw * m.machine.hwPhysHeight() * 4);
    const open = (x, y) => last.part === 3 || (x >= 40 && x < 360 && y >= 40 && y < 240) || ((last.part === 0 || last.part === 4) && y >= 240);
    const ppm = Buffer.alloc(PW * PH * 3);
    let bad = 0, first = null;
    for (let y = 0; y < PH; y++) for (let x = 0; x < PW; x++) {
        const o = (y * pw + 2 * x) * 4;
        const c = (pfb[o] << 16) | (pfb[o + 1] << 8) | pfb[o + 2];
        const g = open(x, y) ? last.g[y * PW + x] : 0;
        const v = g === 0 ? last.c0[y] : A.colours[g]; // 0xAABBGGRR
        const ew = ((v & 255) << 16) | (v & 0xff00) | ((v >> 16) & 255);
        ppm[(y * PW + x) * 3] = c >> 16; ppm[(y * PW + x) * 3 + 1] = (c >> 8) & 255; ppm[(y * PW + x) * 3 + 2] = c & 255;
        if (c !== ew) { bad++; first ??= `(${x},${y}) got ${c.toString(16)} want ${ew.toString(16)} gid ${g}`; }
    }
    if (bad) fail(`${name}: ${bad} physical pixels differ from screen.js, first ${first}`);
    await writeFile(`${outdir}/${name}.ppm`, Buffer.concat([Buffer.from(`P6\n${PW} ${PH}\n255\n`), ppm]));
    checkRasters(name, lines);
    console.log(`  ${name}: frame ${n - 1}, part ${last.part}${bad ? "" : " -- matches screen.js"}`);
}

/// Colour 0 is a register: after each line's HBL, entry 0 holds the replay's
/// raster colour; the bars' pixels are index 0; at most 255 entries a line.
function checkRasters(name, lines) {
    const plane = m.plane();
    let wrong = 0, maxUsed = 0, maxChanged = 0;
    for (let y = 0; y < PH; y++) {
        const p = lines.get(y);
        if (!p) { wrong++; continue; }
        if (p[0] !== last.c0[y]) wrong++;
        let used = 0;
        for (let x = 0; x < PW; x++) {
            if (last.g[y * PW + x] === 0 && plane[y * PW + x] !== 0) wrong++;
            used = Math.max(used, plane[y * PW + x]);
        }
        maxUsed = Math.max(maxUsed, used);
        const prev = lines.get(y - 1);
        if (prev) { let ch = 0; for (let e = 0; e <= used; e++) if (p[e] !== prev[e]) ch++; maxChanged = Math.max(maxChanged, ch); }
    }
    if (wrong) fail(`${name}: ${wrong} line/pixel faults in the colour-0 raster registers`);
    if (RASTER_PARTS.has(last.part)) console.log(`    rasters: colour 0 per line from the HBL; ${maxUsed} entries a line at most, ${maxChanged} register changes a line at most`);
}

// ------------------------------------------------------------------ ST parts
// prototypes/snyd_re/sync_expect.py: [win, pal, phys], SHA-256 prefixes.
// sync1-NNNN shows the part's iteration NNNN+1 (entering runs the first);
// sync2-NNNN shows SYNC #2 after NNNN VBLs (VBL 13 flashes blue, 25 red).
const ST_EXPECT = {
    "sync1-0000": ["5915875cd4db5db0", "7e41ee93d715dd31", "5cc2e36971c658fb"],
    "sync1-0001": ["40ca22c98fdf56da", "d4cb57c7b3b9e93a", "c21a4bda8300784e"],
    "sync1-0002": ["28740adb5673ba88", "8b59a4731e4f2e14", "0beb534b79014779"],
    "sync1-0100": ["74953bac67af1a71", "93469b781a7ae6b7", "5b6e3a4e5ee7be62"],
    "sync1-0400": ["0756f9481532ac99", "e5a19218278b1e32", "76600c1e82ba387a"],
    "sync1-1500": ["bc914a5935b24a67", "5adba000debb9c2b", "2788d50052d3ba69"],
    "sync2-0000": ["c7835f2424702f11", "cdbe2e9a6e59e081", "b65c67e2349fc40d"],
    "sync2-0001": ["c7835f2424702f11", "cdbe2e9a6e59e081", "b65c67e2349fc40d"],
    "sync2-0012": ["c7835f2424702f11", "cdbe2e9a6e59e081", "b65c67e2349fc40d"],
    "sync2-0013": ["c7835f2424702f11", "6983bcc0ef6e0763", "b9f3593e290b548e"],
    "sync2-0024": ["c7835f2424702f11", "cdbe2e9a6e59e081", "b65c67e2349fc40d"],
    "sync2-0025": ["c7835f2424702f11", "fbe65b78dd623e31", "afded05b29f87ef9"],
};
const sha = (b) => createHash("sha256").update(b).digest("hex").slice(0, 16);

/// An ST part's frame against the original's: window, registers, borders.
async function stShot(name) {
    const lines = new Map();
    m.setRec((l) => { lines.set(l, Uint32Array.from(m.palette().subarray(0, 16))); });
    m.machine.hwRenderPlane(0);
    m.setRec(null);
    const plane = m.plane();
    const win = new Uint8Array(320 * 200);
    for (let y = 0; y < 200; y++) win.set(plane.subarray((y + 40) * PW + 40, (y + 40) * PW + 360), y * 320);
    const pal = new Uint32Array(PH * 16);
    for (let y = 0; y < PH; y++) if (lines.has(y)) pal.set(lines.get(y), y * 16);
    const pw = m.machine.hwPhysWidth();
    const pfb = new Uint8Array(m.memory.buffer, m.machine.hwPhysicalPtr(), pw * m.machine.hwPhysHeight() * 4);
    const rgb = Buffer.alloc(PW * PH * 3);
    for (let y = 0; y < PH; y++) for (let x = 0; x < PW; x++) {
        const o = (y * pw + 2 * x) * 4;
        rgb.set(pfb.subarray(o, o + 3), (y * PW + x) * 3);
    }
    await writeFile(`${outdir}/${name}.ppm`, Buffer.concat([Buffer.from(`P6\n${PW} ${PH}\n255\n`), rgb]));
    const got = [sha(win), sha(new Uint8Array(pal.buffer)), sha(rgb)];
    const what = ["the screen (window indices)", "the colour registers per line (rasters)", "the physical frame (borders)"];
    let ok = true;
    for (let k = 0; k < 3; k++) {
        if (got[k] === ST_EXPECT[name][k]) continue;
        ok = false;
        fail(`${name}: ${what[k]} ${got[k]}, the original's ${ST_EXPECT[name][k]}`);
    }
    console.log(`  ${name}: frame ${n - 1}${ok ? " -- the original's screen, rasters and borders" : ""}`);
}

// ------------------------------------------------------------------ the tour
const script = [
    { run: 400, shots: [0, 1, 150, 399], prefix: "menu" },
    { key: [K.f(1), 112] },
    { run: 1501, dt: 20, st: true, shots: [0, 1, 2, 100, 400, 1500], prefix: "sync1" },
    { key: [K.space, 32], song: "sync2" },
    { run: 26, dt: 20, st: true, shots: [0, 1, 12, 13, 24, 25], prefix: "sync2" },
    { key: [K.space, 32] },
    { run: 5, shots: [4], prefix: "menu_back" },
    { key: [K.f(2), 113] },
    { run: 1000, shots: [0, 1, 400, 788, 789, 790, 999], prefix: "tcb1" },
    { key: [K.space, 32] },
    { run: 700, shots: [0, 1, 10, 25, 60, 300, 699], prefix: "tcb2", keysAt: { 100: [K.f(1), 112], 200: [K.f(2), 113], 300: [K.f(3), 114], 400: [K.f(4), 115], 500: [K.f(5), 116] } },
    { key: [K.space, 32] },
    { key: [K.f(3), 114] },
    { run: 500, shots: [0, 1, 7, 62, 250, 499], prefix: "omega" },
    { key: [K.space, 32] },
    { run: 3 },
];
const t0 = performance.now();
for (const s of script) {
    if (s.key) press(s.key[0], s.key[1]);
    if (s.song) wanted.push(s.song); // a tune the remake does not play
    for (let i = 0; i < (s.run || 0); i++) {
        if (s.keysAt && s.keysAt[i]) press(...s.keysAt[i]);
        const isShot = s.shots && s.shots.includes(i);
        const dt = s.dt || DT;
        // the cart runs a frame the reference does not
        if (isShot && brk === "step" && (s.prefix === "tcb2" || s.prefix === "sync1")) m.demo.frame(dt);
        frame(isShot, dt, !(isShot && s.st && brk === "border")); // border: last frame's colour 0 left in
        if (!isShot) continue;
        const name = `${s.prefix}-${String(i).padStart(4, "0")}`;
        await (s.st ? stShot(name) : shot(name));
    }
}
const ms = (performance.now() - t0) / n;

// ------------------------------------------------------------------ music
const w = want();
if (brk === "tune") got[3] = ["dugger.sndh", 3];
if (JSON.stringify(got) !== JSON.stringify(w)) fail(`song requests ${JSON.stringify(got)}\n       want ${JSON.stringify(w)}`);
else console.log(`  music: ${got.length} requests, each the remake's tune: ${[...new Set(got.map((g) => g.join("#")))].join(", ")}`);
await checkTunes(new Set(got.map((g) => g.join("#"))));

// ------------------------------------------------------------------ leaving + cost
if (m.machine.hwRamAllocFailures()) fail(`${m.machine.hwRamAllocFailures()} zg.mem allocation(s) refused`);
m.demo.key(K.esc);
if (m.demo.pollCartRequest() !== -1) fail("Escape does not ask for the menu disk");
{
    const t1 = performance.now();
    for (let i = 0; i < 300; i++) { m.machine.hwClear(); m.demo.frame(DT); m.machine.hwRenderPlane(0); }
    console.log("  cart frame cost (update + render + composite), per part: " + cost.map((c, i) => `${["menu", "sync1", "sync2", "tcb1", "tcb2", "omega"][i]} ${(c[0] / c[1]).toFixed(2)} ms`).join(", "));
    console.log(`  ${n} frames replayed (${ms.toFixed(2)} ms/frame with the replay); the cart alone on the menu: ${((performance.now() - t1) / 300).toFixed(3)} ms/frame (update + render + composite)`);
}

async function checkTunes(set) {
    for (const k of set) {
        const [file, sub] = k.split("#");
        const bytes = new Uint8Array(await readFile(`docs/music/${file}`));
        if (!file.endsWith(".sndh")) {
            const ok = file.endsWith(".ymraw") ? dec.decode(bytes.subarray(0, 4)) === "YM5!" : bytes.length > 100000;
            if (!ok) fail(`${file} is not the expected dump/sample`);
            continue;
        }
        const mem = new WebAssembly.Memory({ initial: 48, maximum: 48 });
        const ma = (await WebAssembly.instantiate(await readFile("docs/machine-audio.wasm"), { env: { memory: mem } })).instance.exports;
        const env = { memory: mem };
        for (const x of Object.keys(ma)) if (x.startsWith("machine")) env[x] = ma[x];
        const au = (await WebAssembly.instantiate(await readFile("docs/demo-audio.wasm"), { env })).instance.exports;
        au.audioInit();
        new Uint8Array(mem.buffer, au.audioSongPtr(), bytes.length).set(bytes);
        if (!au.audioLoadSndh(bytes.length)) { fail(`${file} is not an SNDH image`); continue; }
        au.audioSndhPlay(Number(sub));
        const left = new Float32Array(mem.buffer, ma.audioLeftPtr(), 1024);
        let peak = 0;
        for (let d = 0; d < 2 * 44100; d += 1024) { au.audioRender(1024); for (const v of left) peak = Math.max(peak, Math.abs(v)); }
        if (au.audioMode() !== 4 || peak < 0.05 || au.audioSndhStuckPc()) fail(`${file} #${sub} does not play (mode ${au.audioMode()}, peak ${peak.toFixed(3)})`);
        else console.log(`    ${file} #${sub} plays through the sealed YM (peak ${peak.toFixed(3)})`);
    }
}

if (brk) {
    console.log(errors.length ? `swedish_newyear: PASS (--break ${brk} caught: ${errors.length} failures)` : `swedish_newyear: FAILED -- --break ${brk} was not caught`);
    process.exit(errors.length ? 0 : 1);
}
console.log(errors.length ? `swedish_newyear: FAILED (${errors.length})` : "swedish_newyear: all pass");
process.exit(errors.length ? 1 : 0);
