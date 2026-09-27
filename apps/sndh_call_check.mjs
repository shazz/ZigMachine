// zg.sndhCall on the sealed audio machine: INIT again on the RUNNING SNDH
// (demo-audio.wasm audioSndhCall) must leave everything it does not touch
// playing -- where a reload (the song request) silences and restarts it.
//
// The tune is hand-assembled so every register it drives is known:
//   INIT d0 >= 0       tones A + B on, A at volume 15, B silent, the play
//                      counter ($800) cleared, Timer A at 6400 Hz counting its
//                      interrupts at $801 (vector $134, IERA/IMRA bit 5 set)
//   INIT d0 bit 15 set "resident": channel B only (period $40, volume 12)
//   PLAY (50 Hz)       $800 += 1, and channel A's period low byte = $800
// A control run plays it untouched. The call run sndhCalls $8001 at block 10:
// channel A's period, A's volume, the Timer A count and the replay position
// must equal the control's at EVERY block after it (nothing restarted, no
// timer re-phased), and B must hold the call's values at once (the call runs
// before the next tick, not after it).
//   node apps/sndh_call_check.mjs            the check
//   node apps/sndh_call_check.mjs --break    a reload instead of a call: caught
import { readFile } from "node:fs/promises";

const AUDIO_PAGES = 48; // machine/sdk/audio.zig
const IMAGE_BASE = 0x10002; // sndh_player.zig: where the image runs
const BLOCK = 882, BLOCKS = 60, CALL_AT = 10;
const broke = process.argv.includes("--break");

function tune() {
    const b = [];
    const w = (v) => { b.push((v >> 8) & 0xff, v & 0xff); };
    const psg = (reg, v) => { w(0x11fc); w(reg); w(0x8800); w(0x11fc); w(v); w(0x8802); }; // move.b #,abs.w
    w(0x6000); w(0); w(0x6000); w(0); w(0x6000); w(0); // bra.w init / exit / play
    for (const c of "SNDHTC50") b.push(c.charCodeAt(0));
    b.push(0, 0);
    for (const c of "HDNS") b.push(c.charCodeAt(0));
    const init = b.length;
    w(0x4a40); // tst.w d0
    const bmi = b.length; w(0x6b00); // bmi.s resident (patched)
    psg(7, 0x3c); psg(8, 15); psg(9, 0);
    w(0x4238); w(0x0800); // clr.b $800.w
    w(0x11fc); w(0x60); w(0xfa1f); // move.b #$60,$fffa1f.w   TADR
    const vec = b.length; w(0x21fc); w(0); w(0); w(0x0134); // move.l #handler,$134.w (patched)
    w(0x11fc); w(0x01); w(0xfa19); // move.b #1,$fffa19.w     TACR: /4 -> 6400 Hz
    // TOS leaves Timer A's interrupt off, and the player's MFP honours that
    // (libs/zig/players/mfp.zig): enable and unmask it, as a real tune must.
    w(0x0038); w(0x20); w(0xfa07); // ori.b #$20,$fffa07.w    IERA
    w(0x0038); w(0x20); w(0xfa13); // ori.b #$20,$fffa13.w    IMRA
    w(0x4e75);
    const resident = b.length;
    psg(2, 0x40); psg(3, 0); psg(9, 12);
    w(0x4e75);
    const exit = b.length;
    psg(8, 0); w(0x4e75);
    const play = b.length;
    w(0x5238); w(0x0800); // addq.b #1,$800.w
    w(0x11fc); w(0); w(0x8800); // select register 0
    w(0x11f8); w(0x0800); w(0x8802); // move.b $800.w,$ffff8802.w
    w(0x4e75);
    const handler = b.length;
    w(0x5238); w(0x0801); w(0x4e73); // addq.b #1,$801.w ; rte
    const patch = (at, target) => { const d = target - (at + 2); b[at + 2] = (d >> 8) & 0xff; b[at + 3] = d & 0xff; };
    patch(0, init); patch(4, exit); patch(8, play);
    b[bmi + 1] = resident - (bmi + 2);
    const h = IMAGE_BASE + handler;
    b[vec + 2] = h >>> 24; b[vec + 3] = (h >> 16) & 0xff; b[vec + 4] = (h >> 8) & 0xff; b[vec + 5] = h & 0xff;
    return new Uint8Array(b);
}

async function machine() {
    const memory = new WebAssembly.Memory({ initial: AUDIO_PAGES, maximum: AUDIO_PAGES });
    const m = (await WebAssembly.instantiate(await readFile("docs/machine-audio.wasm"), { env: { memory } })).instance.exports;
    const env = { memory };
    for (const n of Object.keys(m)) if (n.startsWith("machine")) env[n] = m[n];
    const a = (await WebAssembly.instantiate(await readFile("docs/demo-audio.wasm"), { env })).instance.exports;
    a.audioInit();
    const regs = new Uint8Array(memory.buffer, m.audioYmRegsPtr(), 16);
    const ram = new Uint8Array(memory.buffer, a.audioSongPtr(), 0x1000);
    const load = (bytes) => {
        new Uint8Array(memory.buffer, a.audioSongPtr(), bytes.length).set(bytes);
        return a.audioLoadSndh(bytes.length);
    };
    return { a, regs, ram, load };
}

// One run: the per-block state [period A, volume A, Timer A count, position, B period, B volume].
async function run(bytes, call) {
    const M = await machine();
    if (!M.load(bytes)) throw new Error("the test SNDH was refused");
    M.a.audioSndhPlay(1);
    const rows = [];
    let atCall = null;
    for (let i = 0; i < BLOCKS; i++) {
        if (call && i === CALL_AT) {
            if (broke) { M.load(bytes); M.a.audioSndhPlay(1); } // the old host: a reload
            else if (!M.a.audioSndhCall(0x8001)) throw new Error("audioSndhCall found no SNDH playing");
            atCall = [M.regs[2], M.regs[9]];
        }
        M.a.audioRender(BLOCK);
        rows.push([M.regs[0], M.regs[8], M.ram[0x801], M.a.audioSndhPositionMs(), M.regs[2], M.regs[9]]);
    }
    return { rows, atCall, timer: M.a.audioSndhTimerRate(0) };
}

const bytes = tune();
const control = await run(bytes, false);
const called = await run(bytes, true);
const errors = [];
let kept = 0;
for (let i = CALL_AT; i < BLOCKS; i++) {
    const c = control.rows[i], k = called.rows[i];
    if (c.slice(0, 4).join() === k.slice(0, 4).join()) kept++;
    else if (errors.length < 3) errors.push(`block ${i}: channel A period/volume, Timer A count, position ` +
        `[${k.slice(0, 4)}], the untouched run [${c.slice(0, 4)}]`);
}
const moving = new Set(control.rows.map((r) => r[0])).size > 20 && control.rows[BLOCKS - 1][2] > 100;
if (!moving) errors.push("the control run is not playing (period A or Timer A standing still)");
if (!called.atCall || called.atCall.join() !== "64,12")
    errors.push(`right after the call channel B is [${called.atCall}], not [64,12]: the call did not run before the next tick`);
if (called.timer !== control.timer || !control.timer) errors.push(`Timer A ${called.timer} Hz after the call, ${control.timer} Hz untouched`);

// A call with nothing playing is refused, not run on stale RAM.
const idle = await machine();
if (idle.a.audioSndhCall(0x8001)) errors.push("audioSndhCall ran with no SNDH loaded");
// The host's fallback: a call on an image that is not playing loads it, and
// its d0 is the first INIT unclamped (audioSndhPlay would clamp $8001 to 1).
const fresh = await machine();
fresh.load(bytes);
fresh.a.audioSndhPlayRaw(0x8001);
if (fresh.regs[9] !== 12) errors.push(`audioSndhPlayRaw($8001): B volume ${fresh.regs[9]}, INIT did not get d0 unclamped`);

console.log(`sndh_call: channel A, Timer A (${control.timer} Hz) and the position unchanged for ${kept}/${BLOCKS - CALL_AT} ` +
    `blocks after an sndhCall; B took the call's values before the next tick; an idle call refused; the raw start unclamped`);
if (broke) {
    const hit = errors.find((e) => e.startsWith("block"));
    console.log(hit ? `sndh_call: PASS (--break caught: ${hit})` : `sndh_call: FAILED -- --break (a reload) was not caught`);
    process.exit(hit ? 0 : 1);
}
console.log(errors.length ? `sndh_call: FAILED -- ${errors.join("; ")}` : "sndh_call: all pass");
process.exit(errors.length ? 1 : 0);
