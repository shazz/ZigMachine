// Headless SUPPLEX FS2 music check: the screen (apps/zig/scenes/supplex_fs2.zig) plays
// Jochen Hippel's Amiga "Chambers of Shaolin" title module, on its OWN 68000 replay
// (libs/zig/players/hip_player.zig) driving the emulated Paula (paula.zig).
//
//   node apps/supplex_fs2_headless.mjs [--break silent|latch|song]
//
// Checked:
//   1. the cart requests shaolin_title.hip, song 1, when it starts;
//   2. the file is in docs/music/ and is modland's, byte for byte (md5);
//   3. docs/demo-audio.wasm loads it as a Hippel module and plays it for 20 s:
//      the replay never runs away, both sides are loud, at least three of Paula's
//      voices are started by DMACON (drums, bass and the synth lines), pointers
//      written while a voice plays are re-latched at its wrap (the double-buffered
//      AUDxLC the synth sounds need), no voice points outside the 68000's RAM, no
//      audio interrupt is asked for and no write reaches hardware nothing answers.
//
// --break silent: Paula ignores DMACON's switch-on edge (paula.zig mutant 1).
// --break latch:  a pointer written to a playing voice takes effect at once (mutant 2).
// --break song:   the request's name is read with the old space ("shaolin title.hip").
// Each must fail.
import { readFile } from "node:fs/promises";
import { createHash } from "node:crypto";
import { cartRam, romRam } from "../docs/wasm_hiwater.js";

const argv = process.argv.slice(2);
const BREAK = argv.includes("--break") ? argv[argv.indexOf("--break") + 1] : null;
if (BREAK !== null && !["silent", "latch", "song"].includes(BREAK)) { console.error(`supplex_fs2: unknown --break ${BREAK}`); process.exit(1); }

const PAGES = 112; // SHARED_PAGES in machine/sdk/memmap.zig
const MUSIC = "shaolin_title.hip";
const MD5 = "48e2ebc6c7588bee78796281b677facc"; // modland's "shaolin title.hip"
const SECONDS = 20;
const errors = [];
const fail = (m) => errors.push(m);

// --- 1: the request ------------------------------------------------------------
async function bootCart() {
    const memory = new WebAssembly.Memory({ initial: PAGES, maximum: PAGES });
    let demo;
    const machine = (await WebAssembly.instantiate(await readFile("docs/machine-video.wasm"),
        { env: { memory, hblDispatch: (id, p, l, x) => demo.hblDispatch(id, p, l, x) } })).instance.exports;
    const romBytes = await readFile("docs/rom.wasm");
    const rom = (await WebAssembly.instantiate(romBytes, { env: { memory, hwVideoBase: machine.hwVideoBase, hwBlit: machine.hwBlit } })).instance.exports;
    machine.hwSetRomHigh(romRam(romBytes).high ?? 0);
    const cartBytes = await readFile("docs/demo-supplex_fs2.wasm"), env = { memory, ...rom };
    for (const k of Object.keys(machine)) if (k.startsWith("hw")) env[k] = machine[k];
    for (const imp of WebAssembly.Module.imports(new WebAssembly.Module(cartBytes)))
        if (imp.module === "env" && !(imp.name in env)) env[imp.name] = () => {};
    demo = (await WebAssembly.instantiate(cartBytes, { env })).instance.exports;
    machine.hwSetCartHigh(cartRam(cartBytes).high ?? 0);
    machine.hwInit();
    demo.boot();
    demo.skipBoot();
    return { memory, machine, demo };
}

const S = await bootCart();
S.machine.hwClear();
S.demo.frame(1000 / 60);
let requested = null;
if (!S.demo.pollSongRequest()) fail("no song request when the screen starts");
else {
    requested = new TextDecoder().decode(new Uint8Array(S.memory.buffer, S.demo.songNamePtr(), S.demo.songNameLen()));
    if (BREAK === "song") requested = "shaolin title.hip";
    const tune = S.demo.songTune();
    if (requested !== MUSIC || tune !== 1) fail(`requested ${requested} song ${tune}, want ${MUSIC} song 1`);
}

// --- 2: the file ----------------------------------------------------------------
const bytes = await readFile(`docs/music/${requested ?? MUSIC}`).catch(() => null);
if (!bytes) fail(`docs/music/${requested ?? MUSIC} is missing: the site would 404`);
else if (createHash("md5").update(bytes).digest("hex") !== MD5) fail(`${MUSIC} is not modland's file (md5)`);

// --- 3: it plays ----------------------------------------------------------------
if (bytes) await play(bytes);

async function play(file) {
    const memory = new WebAssembly.Memory({ initial: 48, maximum: 48 }); // machine/sdk/audio.zig
    const machine = (await WebAssembly.instantiate(await readFile("docs/machine-audio.wasm"), { env: { memory } })).instance.exports;
    const env = { memory };
    for (const n of Object.keys(machine)) if (n.startsWith("machine")) env[n] = machine[n];
    const a = (await WebAssembly.instantiate(await readFile("docs/demo-audio.wasm"), { env })).instance.exports;
    a.audioInit();
    if (BREAK === "silent") a.audioHipMutant(1);
    if (BREAK === "latch") a.audioHipMutant(2);
    new Uint8Array(memory.buffer, a.audioSongPtr(), file.length).set(file);
    if (!a.audioLoadHip(file.length)) { fail(`${MUSIC}: the Hippel player refused it`); return; }
    a.audioHipPlay(1);
    if (!a.audioHipActive()) { fail(`${MUSIC}: INIT never returned (stuck at $${a.audioSndhStuckPc().toString(16)})`); return; }
    const peak = { l: [Infinity, -Infinity], r: [Infinity, -Infinity] };
    for (let done = 0; done < SECONDS * 44100; done += 1024) {
        a.audioRender(1024);
        for (const [side, ptr] of [["l", machine.audioLeftPtr()], ["r", machine.audioRightPtr()]])
            for (const s of new Float32Array(memory.buffer, ptr, 1024)) {
                peak[side][0] = Math.min(peak[side][0], s);
                peak[side][1] = Math.max(peak[side][1], s);
            }
    }
    if (!a.audioHipActive()) fail(`${MUSIC}: the replay ran away (stuck at $${a.audioSndhStuckPc().toString(16)})`);
    if (a.audioMode() !== 1) fail(`audio mode ${a.audioMode()}, want 1 (the Paula channels' scope view)`);
    for (const side of ["l", "r"]) {
        const span = peak[side][1] - peak[side][0];
        if (!(span > 0.2)) fail(`${MUSIC}: the ${side === "l" ? "left" : "right"} side is near silent over ${SECONDS} s (peak to peak ${span.toFixed(3)})`);
    }
    const starts = [0, 1, 2, 3].map((ch) => a.audioHipStarts(ch));
    if (starts.filter((n) => n > 0).length < 3) fail(`Paula voices started by DMACON: [${starts}], want at least three voices`);
    if (a.audioHipLatches() < 100) fail(`${a.audioHipLatches()} pointers re-latched at a voice's wrap in ${SECONDS} s, want the synth's per-frame waveforms (100+)`);
    if (a.audioHipBadPointers()) fail(`${a.audioHipBadPointers()} voices pointed outside the 68000's RAM`);
    if (a.audioHipIrqWanted()) fail(`the replay enabled ${a.audioHipIrqWanted()} audio interrupts, which are never raised`);
    const n = a.audioUnhandledCount();
    if (n) fail(`${n} writes to hardware nothing answers, first at $${a.audioUnhandled(0).toString(16)}`);
    console.log(`supplex_fs2 music: ${MUSIC} ${SECONDS} s, voice starts [${starts}], latches ${a.audioHipLatches()}, ` +
        `peak to peak L ${(peak.l[1] - peak.l[0]).toFixed(2)} R ${(peak.r[1] - peak.r[0]).toFixed(2)}`);
}

if (BREAK) {
    const caught = errors.length > 0;
    console.log(caught ? `supplex_fs2: PASS (--break ${BREAK} caught: ${errors.length} errors, first: ${errors[0]})`
        : `supplex_fs2: FAIL, --break ${BREAK} was NOT caught`);
    process.exit(caught ? 0 : 1);
}
if (errors.length) {
    console.log("supplex_fs2: WRONG");
    for (const e of errors) console.log("  " + e);
    process.exit(1);
}
console.log("supplex_fs2: OK");
