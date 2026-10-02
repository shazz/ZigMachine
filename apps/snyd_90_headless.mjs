// Headless SWEDISH NEW YEAR DEMO 89-90 driver (apps/zig/scenes/snyd_90.zig):
// boots the sealed machine + the cart as docs/sealed-loader.js does and plays
// the key path -- intro, Space, the menu for 1200 VBLs (through a full slide
// and the swap to the SYNC letters; F3..F6 ignored: not ported), F2 for 1500
// VBLs, Space back to a fresh menu, the same for F1, Escape.
// Every shot is checked against the REAL demo: SHA-256 prefixes from
// prototypes/snyd90_re/snyd90_expect.py --
//   intro    the Spectrum 512 picture as decoded by spu.py, which matches a
//            Hatari capture of the running intro pixel for pixel;
//   menu-J   the screen the menu's J-th iteration drew, from menu_model.py,
//            which reproduces Hatari's RAM byte for byte (and so does the Zig:
//            apps/zig/scenes/snyd_90/menu_test.zig);
//   f2-J,    what F2 / F1 show during VBL J: the original code run on the
//   f1-J     Musashi oracle (prototypes/snyd90_re/m68run), which matches
//            Hatari's RAM of the real parts (f2_test.zig / f1_test.zig check
//            the Zig on it).
// Per shot: the window's palette indices, and the whole physical 400x280 frame
// in RGB (the colours come from the plane's HBL, line by line: 48 registers a
// line in the intro; the borders are colour 0 from the global HBL).
// Then: the song requests (snyd90.sndh #4 in the intro, #1 in the menu,
// snyd90_f2.sndh #1 in F2, the archive's Overlander.sndh #1 in F1), each
// tune plays on the sealed YM, Escape asks for the menu disk, the frame cost.
//
//   node apps/snyd_90_headless.mjs [outdir] [--break hbl|step|tune]
//     hbl   the plane's HBL is not called during a shot: the colours fail
//     step  the cart runs one VBL the reference does not: the menu/F2 shots fail
//     tune  a wrong subtune is reported: the music check fails
import { readFile, writeFile, mkdir } from "node:fs/promises";
import { createHash } from "node:crypto";
import { cartRam, romRam } from "../docs/wasm_hiwater.js";

const PAGES = 112, OFF_PAL = 0x100, REG_FB_BASE = 0x44, PW = 400, PH = 280;
const VBL = 20; // the parts run at the ST's 50 Hz: one VBL a 20 ms frame
const K = { space: 32, esc: 0xe012, f: (n) => 0xe000 + n };
const EXPECT = {
    "intro": ["491f7e0b7fa2f5ac", "833eeee91e8a18bf"],
    "menu-0001": ["792a1d0862a639f1", "c66600dfa2f7a4a7"],
    "menu-0002": ["792a1d0862a639f1", "c66600dfa2f7a4a7"],
    "menu-0100": ["b14e0f30fe3069af", "a4b092fe624c2e15"],
    "menu-0531": ["09277ce9f3bd8cdf", "fd48138284fe5bf2"],
    "menu-1000": ["3c9e6217de121a7d", "30bdf62e7ba8091e"],
    "menu-1200": ["85602e678e35975c", "fec34b17c640ad39"],
    "f2-0001": ["4f7988030a00d082", "3c521e0946b9f8fe"],
    "f2-0002": ["d4003559a510ccbd", "7b501fb9a7fd2da4"],
    "f2-0003": ["0f4451f5b4a40379", "d92e7800b3aa1bdd"],
    "f2-0051": ["f0091c48c5d1acb0", "31cceb75611334dd"],
    "f2-0194": ["3286d611dec36d3e", "f1622b0f9425c720"],
    "f2-0701": ["dd9de0599b3e0d4c", "6804ef867346f165"],
    "f2-1501": ["0970034ffc352cac", "02604d403f75a633"],
    "f1-0001": ["180825ebbd018edd", "c4cd4e0d2aa06bc0"],
    "f1-0002": ["180825ebbd018edd", "c4cd4e0d2aa06bc0"],
    "f1-0300": ["180825ebbd018edd", "c4cd4e0d2aa06bc0"],
    "f1-0701": ["dda8ff95761e8d75", "1ce77cf633c91c9e"],
    "f1-1501": ["c9d4a915200dad7f", "a10acb0cb93ea0e7"],
};
const SONGS = [["snyd90.sndh", 4], ["snyd90.sndh", 1], ["snyd90_f2.sndh", 1], ["snyd90.sndh", 1],
    ["Overlander.sndh", 1], ["snyd90.sndh", 1]];

const argv = process.argv.slice(2);
const bi = argv.indexOf("--break");
const brk = bi < 0 ? null : argv.splice(bi, 2)[1];
const BREAKS = ["hbl", "step", "tune"];
if (brk && !BREAKS.includes(brk)) throw new Error(`--break takes ${BREAKS.join(", ")}, not ${brk}`);
const outdir = argv[0] || "/tmp/snyd_90";
await mkdir(outdir, { recursive: true });
const errors = [];
const fail = (msg) => { errors.push(msg); console.log(`  FAIL ${msg}`); };
const sha = (b) => createHash("sha256").update(b).digest("hex").slice(0, 16);
const dec = new TextDecoder();

async function boot() {
    const memory = new WebAssembly.Memory({ initial: PAGES, maximum: PAGES });
    let demo, mute = false;
    const machine = (await WebAssembly.instantiate(await readFile("docs/machine-video.wasm"), {
        env: { memory, hblDispatch: (id, p, l, x) => { if (!mute) demo.hblDispatch(id, p, l, x); } },
    })).instance.exports;
    const romBytes = await readFile("docs/rom.wasm");
    const rom = (await WebAssembly.instantiate(romBytes, { env: { memory, hwVideoBase: machine.hwVideoBase, hwBlit: machine.hwBlit } })).instance.exports;
    machine.hwSetRomHigh(romRam(romBytes).high ?? 0);
    const noop = () => {};
    const cartBytes = await readFile("docs/demo-snyd_90.wasm");
    const env = { memory, jsConsoleLogWrite: noop, jsConsoleLogFlush: noop, jsThrowError: noop, consoleLogJS: noop, ...rom };
    for (const k of Object.keys(machine)) if (/^hw(Video|Blit|Ram|RomRam)/.test(k)) env[k] = machine[k];
    for (const k of ["audioPlay", "audioStop", "loadSample", "beep", "diskReadBlock", "hostAudioStreamStart", "hostAudioFeed", "hostAudioStreamStop"]) env[k] = noop;
    demo = (await WebAssembly.instantiate(cartBytes, { env })).instance.exports;
    machine.hwSetCartHigh(cartRam(cartBytes).high ?? 0);
    machine.hwInit();
    demo.boot();
    demo.skipBoot();
    const base = machine.hwVideoBase();
    return {
        memory, machine, demo, setMute: (v) => { mute = v; },
        plane: () => new Uint8Array(memory.buffer, base + new DataView(memory.buffer, base).getUint32(REG_FB_BASE, true), PW * PH),
    };
}

const m = await boot();
const got = [];
let frames = 0;
const cost = { intro: [0, 0], menu: [0, 0], f1: [0, 0], f2: [0, 0] };

function frame(part, dt = VBL) {
    const t = performance.now();
    m.machine.hwClear();
    m.demo.frame(dt);
    m.machine.hwRenderPlane(0);
    cost[part][0] += performance.now() - t;
    cost[part][1]++;
    if (m.demo.pollSongRequest()) {
        got.push([dec.decode(new Uint8Array(m.memory.buffer, m.demo.songNamePtr(), m.demo.songNameLen())), m.demo.songTune()]);
    }
    frames++;
}

/// The shot just rendered against the original: window indices, physical frame.
async function shot(name) {
    m.setMute(brk === "hbl");
    m.machine.hwRenderPlane(0);
    m.setMute(false);
    const plane = m.plane();
    const win = new Uint8Array(320 * 200);
    for (let y = 0; y < 200; y++) win.set(plane.subarray((y + 40) * PW + 40, (y + 40) * PW + 360), y * 320);
    const pw = m.machine.hwPhysWidth();
    const pfb = new Uint8Array(m.memory.buffer, m.machine.hwPhysicalPtr(), pw * m.machine.hwPhysHeight() * 4);
    const rgb = Buffer.alloc(PW * PH * 3);
    for (let y = 0; y < PH; y++) for (let x = 0; x < PW; x++) rgb.set(pfb.subarray((y * pw + 2 * x) * 4, (y * pw + 2 * x) * 4 + 3), (y * PW + x) * 3);
    await writeFile(`${outdir}/${name}.ppm`, Buffer.concat([Buffer.from(`P6\n${PW} ${PH}\n255\n`), rgb]));
    const have = [sha(win), sha(rgb)];
    const what = ["the screen (window indices)", "the physical frame (colours per line, borders)"];
    let ok = true;
    for (let k = 0; k < 2; k++) {
        if (have[k] === EXPECT[name][k]) continue;
        ok = false;
        fail(`${name}: ${what[k]} ${have[k]}, the original's ${EXPECT[name][k]}`);
    }
    console.log(`  ${name}: frame ${frames}${ok ? " -- the original's screen and colours" : ""}`);
}

// ------------------------------------------------------------------ the tour
const t0 = performance.now();
frame("intro");
await shot("intro");
for (let i = 0; i < 49; i++) frame("intro");
await shot("intro"); // a still picture: unchanged 50 VBLs on
m.demo.key(K.space);
const MENU_SHOTS = [1, 2, 100, 531, 1000, 1200];
for (let j = 1; j <= 1200; j++) {
    if (j === 700) for (const f of [3, 4, 5, 6]) m.demo.key(K.f(f)); // parts not ported: no effect
    const isShot = MENU_SHOTS.includes(j);
    if (isShot && brk === "step") m.demo.frame(VBL);
    frame("menu");
    if (isShot) await shot(`menu-${String(j).padStart(4, "0")}`);
}
// A part from the menu: the shot after its VBL J shows (one host frame later:
// a capture is presented at the start of the next frame) what the original
// shows during VBL J. Then Space: back to the menu, read afresh.
async function part(fkey, name, shots) {
    m.demo.key(K.f(fkey));
    const last = Math.max(...shots);
    for (let j = 1; j <= last + 1; j++) {
        const isShot = shots.includes(j - 1);
        if (isShot && brk === "step") m.demo.frame(VBL);
        frame(name);
        if (isShot) await shot(`${name}-${String(j - 1).padStart(4, "0")}`);
    }
    m.demo.key(K.space);
    frame("menu");
    await shot("menu-0001"); // its first iteration again
}
await part(2, "f2", [1, 2, 3, 51, 194, 701, 1501]);
await part(1, "f1", [1, 2, 300, 701, 1501]);
const ms = (performance.now() - t0) / frames;

// ------------------------------------------------------------------ music
if (brk === "tune") got[1] = ["snyd90.sndh", 2];
if (JSON.stringify(got) !== JSON.stringify(SONGS)) fail(`song requests ${JSON.stringify(got)}, want ${JSON.stringify(SONGS)}`);
else console.log(`  music: ${got.map((g) => g.join(" #")).join(", then ")}`);
for (const [file, sub] of SONGS) await checkTune(file, sub);

async function checkTune(file, sub) {
    const bytes = new Uint8Array(await readFile(`docs/music/${file}`));
    const mem = new WebAssembly.Memory({ initial: 48, maximum: 48 });
    const ma = (await WebAssembly.instantiate(await readFile("docs/machine-audio.wasm"), { env: { memory: mem } })).instance.exports;
    const env = { memory: mem };
    for (const x of Object.keys(ma)) if (x.startsWith("machine")) env[x] = ma[x];
    const au = (await WebAssembly.instantiate(await readFile("docs/demo-audio.wasm"), { env })).instance.exports;
    au.audioInit();
    new Uint8Array(mem.buffer, au.audioSongPtr(), bytes.length).set(bytes);
    if (!au.audioLoadSndh(bytes.length)) return fail(`${file} is not an SNDH image`);
    au.audioSndhPlay(sub);
    const left = new Float32Array(mem.buffer, ma.audioLeftPtr(), 1024);
    let peak = 0;
    for (let d = 0; d < 2 * 44100; d += 1024) { au.audioRender(1024); for (const v of left) peak = Math.max(peak, Math.abs(v)); }
    if (au.audioMode() !== 4 || peak < 0.05 || au.audioSndhStuckPc()) fail(`${file} #${sub} does not play (mode ${au.audioMode()}, peak ${peak.toFixed(3)})`);
    else console.log(`    ${file} #${sub} plays through the sealed YM (peak ${peak.toFixed(3)})`);
}

// ------------------------------------------------------------------ leaving + cost
if (m.machine.hwRamAllocFailures()) fail(`${m.machine.hwRamAllocFailures()} zg.mem allocation(s) refused`);
m.demo.key(K.esc);
if (m.demo.pollCartRequest() !== -1) fail("Escape does not ask for the menu disk");
console.log(`  cart frame cost (update + render + composite): intro ${(cost.intro[0] / cost.intro[1]).toFixed(3)} ms, menu ${(cost.menu[0] / cost.menu[1]).toFixed(3)} ms, F1 ${(cost.f1[0] / cost.f1[1]).toFixed(3)} ms, F2 ${(cost.f2[0] / cost.f2[1]).toFixed(3)} ms; ${frames} frames, ${ms.toFixed(2)} ms/frame with the checks`);

if (brk) {
    console.log(errors.length ? `snyd_90: PASS (--break ${brk} caught: ${errors.length} failures)` : `snyd_90: FAILED -- --break ${brk} was not caught`);
    process.exit(errors.length ? 0 : 1);
}
console.log(errors.length ? `snyd_90: FAILED (${errors.length})` : "snyd_90: all pass");
process.exit(errors.length ? 1 : 0);
