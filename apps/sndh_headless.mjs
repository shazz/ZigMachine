// Headless SNDH driver — boots the sealed machine-audio.wasm + demo-audio.wasm
// the way docs/audio-worklet-sealed.js does, stages a tune in song RAM, and
// renders a block.
//
// Why this exists: the SNDH player runs the tune's OWN 68000 code on Musashi,
// so "does it work?" means "did an emulated CPU execute, did its PSG writes land
// on the sealed YM, and did the chip then make a sound?". None of that is
// visible from the browser except as audio. Here it is three assertions.
//
//   node apps/sndh_headless.mjs [tune.sndh]   # no argument: the built-in tune
import { readFile } from "node:fs/promises";

const AUDIO_PAGES = 48; // must match AUDIO_PAGES in machine/sdk/audio.zig

// --- a minimal SNDH, hand-assembled --------------------------------------
// Three entry points, the magic, a 50 Hz timer tag, and 68000 code that does
// the one thing every ST replay routine does: poke the PSG.
function tinySndh() {
    const b = [];
    const w = (v) => { b.push((v >> 8) & 0xff, v & 0xff); };
    // move.b #imm,$ffff8800 / $ffff8802 — the classic 11FC idiom, absolute short
    const psg = (port, value) => { w(0x11fc); w(value & 0xff); w(port); };
    const RTS = 0x4e75;

    w(0x6000); w(0);           // 0: bra.w init   (displacement patched below)
    w(0x6000); w(0);           // 4: bra.w exit
    w(0x6000); w(0);           // 8: bra.w play
    for (const c of "SNDHTC50") b.push(c.charCodeAt(0));
    b.push(0, 0);              // NUL after "50", then the word-align pad
    for (const c of "HDNS") b.push(c.charCodeAt(0));

    const init = b.length;
    psg(0x8800, 7); psg(0x8802, 0x3e);   // mixer: tone A on, everything else off
    psg(0x8800, 8); psg(0x8802, 15);     // channel A at full volume
    w(RTS);
    const exit = b.length;
    psg(0x8800, 8); psg(0x8802, 0);      // channel A silent
    w(RTS);
    const play = b.length;
    psg(0x8800, 0); psg(0x8802, 0xd2);   // period A low byte  -> an audible note
    psg(0x8800, 1); psg(0x8802, 0x00);   // period A high byte
    w(RTS);

    // bra.w displacements are relative to the word AFTER the opcode.
    const patch = (at, target) => { const d = target - (at + 2); b[at + 2] = (d >> 8) & 0xff; b[at + 3] = d & 0xff; };
    patch(0, init); patch(4, exit); patch(8, play);
    return new Uint8Array(b);
}

async function boot() {
    const memory = new WebAssembly.Memory({ initial: AUDIO_PAGES, maximum: AUDIO_PAGES });
    const machine = (await WebAssembly.instantiate(
        await readFile("docs/machine-audio.wasm"), { env: { memory } })).instance.exports;

    const env = { memory };
    for (const name of Object.keys(machine)) if (name.startsWith("machine")) env[name] = machine[name];
    const demo = (await WebAssembly.instantiate(
        await readFile("docs/demo-audio.wasm"), { env })).instance.exports;

    demo.audioInit();
    return { memory, machine, demo };
}

const path = process.argv[2];
const tune = path ? new Uint8Array(await readFile(path)) : tinySndh();
const { memory, machine, demo } = await boot();

new Uint8Array(memory.buffer, demo.audioSongPtr(), tune.length).set(tune);
console.log(`tune: ${path || "built-in"} (${tune.length} bytes)`);

if (!demo.audioLoadSndh(tune.length)) {
    console.log("=> REJECTED: not an SNDH image (ICE-packed tunes must be depacked first) ❌");
    process.exit(1);
}
console.log(`  subtunes      : ${demo.audioSndhSubtunes()}`);

demo.audioSndhPlay(1);
console.log(`  mode after play: ${demo.audioMode()} (4 == SNDH)`);
if (demo.audioSndhStuckPc()) {
    console.log(`  STUCK at 68k PC $${demo.audioSndhStuckPc().toString(16)}`);
}
const trap = demo.audioSndhUnhandledTrap();
if (trap) console.log(`  unanswered TRAP #${trap >> 16}, function $${(trap & 0xffff).toString(16)}`);
// A second of audio, a block at a time, the way the worklet asks for it.
const BLOCK = 1024, SECOND = 44100;
const left = new Float32Array(memory.buffer, machine.audioLeftPtr(), BLOCK);
const ymRegs = new Uint8Array(memory.buffer, machine.audioYmRegsPtr(), 16);
let peak = 0;
const seen = [new Set(), new Set(), new Set()]; // volumes reached per channel
for (let done = 0; done < SECOND; done += BLOCK) {
    demo.audioRender(BLOCK);
    for (const v of left) peak = Math.max(peak, Math.abs(v));
    for (let ch = 0; ch < 3; ch++) seen[ch].add(ymRegs[8 + ch]);
}
console.log(`  volumes seen  : A=${[...seen[0]].join(",")}  B=${[...seen[1]].join(",")}  C=${[...seen[2]].join(",")}`);

// Did the 68000's writes reach the sealed chip?
const regs = new Uint8Array(memory.buffer, machine.audioYmRegsPtr(), 16);
console.log(`  YM registers  : ${[...regs].map((r) => r.toString(16).padStart(2, "0")).join(" ")}`);

console.log(`  output peak   : ${peak.toFixed(4)} (over one second)`);

// The built-in tune programs registers we can name; a real tune just has to
// play. Either way the point is that its OWN 68000 code did the programming.
const ok = demo.audioMode() === 4 && peak > 0.01 &&
    (path !== undefined || (regs[7] === 0x3e && regs[0] === 0xd2));
console.log(ok ? "=> PASS ✅ the tune's own 68000 code is driving the sealed YM" : "=> FAIL ❌");
process.exit(ok ? 0 : 1);
