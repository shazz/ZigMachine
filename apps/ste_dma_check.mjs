// The STE DMA sound chip (libs/zig/players/ste_dma.zig) as DMA replays use it, on three
// hand-assembled SNDHs. Why: 9 of the archive's FLAG-e tunes programmed the chip and
// played SILENCE (2026-10-23 sweep of prototypes/sndh_lf). They loop a double buffer and
// rely on what the real chip does at the END of every frame:
//   latch  -- the chip latches the start/end the tune wrote DURING the frame (Crazy Q,
//             505, Excellence in Art write the next half from `play`). Latched only at
//             the go bit, they looped their first, still-empty buffer for ever.
//   event  -- the frame end clocks MFP Timer A in event-count mode (TACR = 8, TADR = 1),
//             whose interrupt refills the buffer (SpaSTiba).
//   volume -- the LMC1992 master volume sent over the Microwire is applied.
// Each tune starts on a SILENT frame and only the mechanism under test can reach the
// loud one, so a chip without it plays nothing.
//
//   node apps/ste_dma_check.mjs [--break latch|event|volume]
// --break swaps the mechanism out of the TUNE (no next frame written, a clock timer, no
// Microwire command) and passes only if the checks catch it.
import { readFile } from "node:fs/promises";

const LOUD = 1000, QUIET = 1000;           // frame lengths, bytes
const MASTER = 34;                         // LMC1992 master volume step: (34 - 40) x 2 = -12 dB
const BREAK = process.argv.includes("--break") ? process.argv[process.argv.indexOf("--break") + 1] : null;

// --- a tiny 68000 assembler, just the instructions these tunes need -------
function tune(kind) {
    const b = [], fix = [];
    const w = (v) => b.push((v >> 8) & 0xff, v & 0xff);
    const lea = (reg, label) => { w(0x41fa | (reg << 9)); fix.push([b.length, label]); w(0); }; // lea d16(pc),aN
    const poke = (addr, v) => { w(0x11fc); w(v & 0xff); w(addr); };                         // move.b #v,addr.w
    const pokeW = (addr, v) => { w(0x31fc); w(v); w(addr); };                               // move.w #v,addr.w
    // start (a0) and end (a1) into their three byte registers each, high byte first
    const frame = () => {
        for (const [src, hi] of [[0x2008, 0x8903], [0x2009, 0x890f]]) {                    // move.l aN,d0
            w(src);
            w(0x11c0); w(hi + 4); w(0xe088);                                                // move.b d0,lo / lsr.l #8,d0
            w(0x11c0); w(hi + 2); w(0xe088);
            w(0x11c0); w(hi);
        }
    };
    const RTS = 0x4e75, RTE = 0x4e73;
    w(0x6000); fix.push([b.length, "init"]); w(0);
    w(0x6000); fix.push([b.length, "exit"]); w(0);
    w(0x6000); fix.push([b.length, "play"]); w(0);
    for (const c of "SNDHTC50") b.push(c.charCodeAt(0));
    b.push(0, 0);
    for (const c of "HDNS") b.push(c.charCodeAt(0));
    const at = {};
    at.init = b.length;
    lea(0, "quiet"); lea(1, "quietEnd"); frame();
    poke(0x8921, 0x81);                    // mono, 12517 Hz
    if (kind === "volume" && BREAK !== "volume") { pokeW(0x8924, 0x07ff); pokeW(0x8922, (2 << 9) | (3 << 6) | MASTER); }
    if (kind === "event") {
        lea(0, "handler"); w(0x21c8); w(0x0134);           // move.l a0,$134.w: Timer A's vector
        poke(0xfa1f, 1);                                    // TADR = 1: every frame end
        poke(0xfa19, BREAK === "event" ? 0 : 8);            // TACR = 8: event count
        poke(0xfa07, 0x20); poke(0xfa13, 0x20);             // Timer A enabled + unmasked
    }
    poke(0x8901, 3);                        // play, loop
    w(RTS);
    at.exit = b.length;
    poke(0x8901, 0); w(RTS);
    at.play = b.length;
    // latch/volume: the next frame is the loud one, written while the quiet one plays
    if (kind !== "event" && !(kind === "latch" && BREAK === "latch")) { lea(0, "loud"); lea(1, "loudEnd"); frame(); }
    w(RTS);
    at.handler = b.length;
    w(0x48e7); w(0x80c0);                   // movem.l d0/a0-a1,-(sp)
    lea(0, "loud"); lea(1, "loudEnd"); frame();
    w(0x4cdf); w(0x0301);                   // movem.l (sp)+,d0/a0-a1
    w(RTE);
    at.quiet = b.length; for (let i = 0; i < QUIET; i++) b.push(0);
    at.quietEnd = b.length;
    at.loud = b.length; for (let i = 0; i < LOUD; i++) b.push((i >> 3) & 1 ? 100 : 256 - 100); // a square wave
    at.loudEnd = b.length;
    for (const [pos, label] of fix) { const d = at[label] - pos; b[pos] = (d >> 8) & 0xff; b[pos + 1] = d & 0xff; }
    return new Uint8Array(b);
}

async function play(bytes, seconds = 1) {
    const memory = new WebAssembly.Memory({ initial: 48, maximum: 48 }); // AUDIO_PAGES
    const machine = (await WebAssembly.instantiate(await readFile("docs/machine-audio.wasm"), { env: { memory } })).instance.exports;
    const env = { memory };
    for (const n of Object.keys(machine)) if (n.startsWith("machine")) env[n] = machine[n];
    const d = (await WebAssembly.instantiate(await readFile("docs/demo-audio.wasm"), { env })).instance.exports;
    d.audioInit();
    new Uint8Array(memory.buffer, d.audioSongPtr(), bytes.length).set(bytes);
    if (!d.audioLoadSndh(bytes.length)) return { error: "not loaded" };
    d.audioSndhPlay(0);
    const BLOCK = 1024, left = new Float32Array(memory.buffer, machine.audioLeftPtr(), BLOCK);
    let peak = 0;
    for (let n = 0; n < seconds * 44100; n += BLOCK) { d.audioRender(BLOCK); for (const v of left) peak = Math.max(peak, Math.abs(v)); }
    const unhandled = Array.from({ length: d.audioUnhandledCount() }, (_, i) => `$${d.audioUnhandled(i).toString(16)}`);
    return { peak, ends: d.audioDmaFrameEnds(), writes: d.audioDmaWrites(), mode: d.audioMode(), stuck: d.audioSndhStuckPc(), unhandled };
}

const checks = [];
const check = (name, ok, detail) => { checks.push(ok); console.log(`  ${ok ? "ok  " : "FAIL"} ${name}: ${detail}`); };
const r = {};
for (const kind of ["latch", "event", "volume"]) r[kind] = await play(tune(kind));
// ~12.5 frame ends a second: 12517 Hz over the 1000-byte frames
const fair = (x) => x.ends >= 10 && x.ends <= 14 && x.mode === 4 && !x.stuck && x.unhandled.length === 0;
check("latch", fair(r.latch) && r.latch.peak > 0.2,
    `peak ${r.latch.peak.toFixed(3)}, ${r.latch.ends} frame ends in 1 s, mode ${r.latch.mode}, unhandled [${r.latch.unhandled}]`);
check("event", fair(r.event) && r.event.peak > 0.2,
    `peak ${r.event.peak.toFixed(3)}, ${r.event.ends} frame ends (Timer A event count, TADR 1)`);
const want = 10 ** (((MASTER - 40) * 2) / 20), ratio = r.volume.peak / r.latch.peak;
check("volume", fair(r.volume) && Math.abs(ratio - want) < 0.02,
    `peak ${r.volume.peak.toFixed(3)} = x${ratio.toFixed(3)} of the latch tune's (want x${want.toFixed(3)}: master -12 dB)`);
const pass = checks.every(Boolean);
if (BREAK) {
    console.log(pass ? `ste_dma_check: --break ${BREAK} NOT caught ❌` : `ste_dma_check: PASS (--break ${BREAK} caught)`);
    process.exit(pass ? 1 : 0);
}
console.log(pass ? "ste_dma_check: PASS ✅ the DMA chip latches at the frame end, clocks Timer A, applies the LMC volume" : "ste_dma_check: FAIL ❌");
process.exit(pass ? 0 : 1);
