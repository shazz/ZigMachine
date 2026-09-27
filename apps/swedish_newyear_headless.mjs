// Headless SWEDISH NEW YEAR DEMO driver (apps/zig/scenes/swedish_newyear.zig):
// boots the sealed machine + the cart the way docs/sealed-loader.js does and
// plays the whole key path -- menu, F1 SYNC #1, Space SYNC #2, Space menu,
// F2 TCB #1 (into its fullscreen), Space TCB #2 (then F3 F4 F5 F1 F5), Space
// menu, F3 OMEGA, Space menu. Two references:
//   * SYNC and TCB are ported from the DISK, so they are checked against the
//     REAL demo: SHA-256s of what the machine must show at fixed VBLs, from
//     prototypes/snyd_re/{sync,tcb1,tcb2}_expect.py -- models of the ripped
//     routines that reproduce Hatari's RAM of the running demo byte for byte
//     (NOTES.md, NOTES_tcb.md there; the Zig is checked against the same dumps
//     by apps/zig/scenes/swedish_newyear/{sync,tcb1,tcb2}_test.zig). Per shot:
//       win   the 320x200 window's palette indices (the part's screen) -- the
//             whole 400x280 plane for TCB #1, which opens the top and sides,
//       pal   colour registers 0..15 as the plane's HBL leaves them on each of
//             the 280 lines (the rasters ARE these: per-line register values),
//       phys  the whole physical frame, borders included (a closed border is
//             colour 0 of its line, painted by the global HBL one frame ahead).
//     TCB #2's 73-VBL set-up must be black. These parts run at the ST's 50 Hz,
//     so the tour steps them 20 ms a frame.
//   * the menu and OMEGA are still the CODEF remake's, checked against
//     screen.js REPLAYED (apps/swedish_newyear_replay.mjs): every shot's WHOLE
//     physical frame (borders included) is the replay's, pixel for pixel, and
//     colour 0 after each line's HBL is the replay's.
//   Then: every song request is the expected tune and subtune, and each SNDH
//   plays; Escape asks for the menu disk; the cart's frame cost is reported.
//
//   node apps/swedish_newyear_headless.mjs [outdir] [--break hbl|step|tune|border]
//     hbl     the plane's HBL is not called during a shot: the registers fail
//     step    the cart runs one frame the reference does not (SYNC #1, TCB #2)
//     tune    a wrong subtune is reported: the music check fails
//     border  an ST shot's frame skips hwClear: the borders' colour 0 fails
import { readFile, writeFile, mkdir } from "node:fs/promises";
import { createHash } from "node:crypto";
import { cartRam, romRam } from "../docs/wasm_hiwater.js";
import { loadAssets } from "./swedish_newyear_assets.mjs";
import { Remake, PW, PH } from "./swedish_newyear_replay.mjs";

const PAGES = 112, OFF_PAL = 0x100, REG_FB_BASE = 0x44;
const DT = 1000 / 60;
const K = { space: 32, esc: 0xe012, f: (n) => 0xe000 + n };
const SONGS = { // each tune -> what the port must request (swedish_newyear.zig)
    scout: ["scout.sndh", 1], jinx1: ["Jinks.sndh", 1], icepalace: ["beyond_the_ice_palace.sndh", 1],
    sync2: ["Swedish_New_Year_Demo_Sync.sndh", 1], tcb_digi: ["swedish_newyear_tcb_digi.sndh", 1],
    stop: ["none", 0], // zg.stopSong(): TCB #1's exit silences its sample stream
    dugger2: ["dugger.sndh", 2], dugger3: ["dugger.sndh", 3], dugger4: ["dugger.sndh", 4],
};
const RASTER_PARTS = new Set(); // remake parts with rasters: none left (the menu, OMEGA)

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
// The host polls ONE request a frame; the tour leaves a frame between keys.
const wanted = ["scout"]; // the cart's init requests it
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
    // prototypes/snyd_re/tcb1_expect.py: [PLANE, pal, phys] -- TCB #1 opens the
    // top and side borders, so the first hash is the whole 400x280 plane of
    // indices. tcb1-NNNN shows VBL NNNN+1 (603 the last intro frame, 604 the
    // first fullscreen, 677 the first with the logo).
    "tcb1-0000": ["477b5f6431fb93ac", "a67487cee3c07b81", "2fb6c8a8d635cbdf"],
    "tcb1-0001": ["088959c9f27aa354", "a67487cee3c07b81", "bf669a0b6ac93b39"],
    "tcb1-0074": ["821b8896ff737e20", "a67487cee3c07b81", "201050c17ac50a76"],
    "tcb1-0603": ["23a0b2389964d350", "a67487cee3c07b81", "dd0bbbe764ef1c29"],
    "tcb1-0604": ["348f72a74921f869", "a67487cee3c07b81", "468ccb6e4b2f685a"],
    "tcb1-0677": ["ad7af58934fc88ec", "a67487cee3c07b81", "fd9c2e1bcbb336bc"],
    "tcb1-0699": ["3f7a9572beaeb318", "a67487cee3c07b81", "a58427ddab3f1df0"],
    "tcb1-0999": ["4ba3943c1a5e0490", "a67487cee3c07b81", "55dececfcdfd7b4d"],
    // prototypes/snyd_re/tcb2_expect.py: [win, pal, phys]. Space starts TCB #2's
    // set-up, 73 black VBLs; tcb2-NNNN then shows its frame NNNN-73 (the fade
    // of the UNION logo at 100 and 112).
    "tcb2-0000": "black",
    "tcb2-0073": "black",
    "tcb2-0074": ["a00d54643c2275d7", "e8c612031a88791c", "6c6ae064595d9b32"],
    "tcb2-0075": ["aa6b8d1834efc1bd", "74998932d8be19f9", "5883100dfa8fe2f3"],
    "tcb2-0076": ["c44b6b5bee21656f", "e000dddd0f7f4e5b", "6492420734c04c25"],
    "tcb2-0083": ["130ec0066c37f03f", "2cb9043385a185fa", "20843a08922e00bc"],
    "tcb2-0173": ["ddb4a7dfd31c04d2", "6a852db5a7479bd3", "a77ac8dc6267e437"],
    "tcb2-0185": ["776a125ab8c55645", "1b0f3af63210151d", "7ff01e6f05f660a8"],
    "tcb2-0547": ["f82bc5908a3b65af", "24fd801ce5069ac8", "ed7f73ca41f28d50"],
    "tcb2-0548": ["63cc71ce5464d354", "5d7595f3a11e3a9e", "90d6b6cde4f092d5"],
    "tcb2-1073": ["0ee3dc96c1f8e40b", "66ff917f7aace45b", "a65381897cc26872"],
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
    if (ST_EXPECT[name] === "black") {
        if (rgb.some((v) => v !== 0)) fail(`${name}: the set-up is not black`);
        else console.log(`  ${name}: frame ${n - 1} -- black, as the set-up is`);
        return;
    }
    const first = name.startsWith("tcb1") ? plane.slice(0, PW * PH) : win;
    const got = [sha(first), sha(new Uint8Array(pal.buffer)), sha(rgb)];
    const what = [name.startsWith("tcb1") ? "the plane (indices)" : "the screen (window indices)", "the colour registers per line (rasters)", "the physical frame (borders)"];
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
    { key: [K.f(1), 112], song: "jinx1" },
    { run: 1501, dt: 20, st: true, shots: [0, 1, 2, 100, 400, 1500], prefix: "sync1" },
    { key: [K.space, 32], song: "sync2" },
    { run: 26, dt: 20, st: true, shots: [0, 1, 12, 13, 24, 25], prefix: "sync2" },
    { key: [K.space, 32], song: "scout" },
    { run: 5, shots: [4], prefix: "menu_back" },
    { key: [K.f(2), 113], song: "tcb_digi" },
    { run: 1000, dt: 20, st: true, shots: [0, 1, 74, 603, 604, 677, 699, 999], prefix: "tcb1" },
    { key: [K.space, 32], song: "stop" },
    // after the last shot: F3 F4 F5 restart Dugger at 2 3 4, F5 again does nothing, F1 is a speed
    {
        run: 1100, dt: 20, st: true, shots: [0, 73, 74, 75, 76, 83, 173, 185, 547, 548, 1073], prefix: "tcb2",
        keysAt: { 1075: [K.f(3), 114], 1080: [K.f(4), 115], 1085: [K.f(5), 116], 1090: [K.f(5), 116], 1095: [K.f(1), 112] },
        songAt: { 73: "dugger4", 1075: "dugger2", 1080: "dugger3", 1085: "dugger4" },
    },
    { key: [K.space, 32], song: "scout" },
    { run: 3 },
    { key: [K.f(3), 114], song: "icepalace" },
    { run: 500, shots: [0, 1, 7, 62, 250, 499], prefix: "omega" },
    { key: [K.space, 32], song: "scout" },
    { run: 3 },
];
const t0 = performance.now();
for (const s of script) {
    if (s.key) press(s.key[0], s.key[1]);
    if (s.song) wanted.push(s.song);
    for (let i = 0; i < (s.run || 0); i++) {
        if (s.songAt && s.songAt[i]) wanted.push(s.songAt[i]);
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
else console.log(`  music: ${got.length} requests, each the expected tune: ${[...new Set(got.map((g) => g.join("#")))].join(", ")}`);
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
        if (file === "none") continue; // the stop request, not a tune
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
