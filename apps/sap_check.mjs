// Headless SAP check: the browser's audio path (docs/machine-audio.wasm's POKEY driven by
// docs/demo-audio.wasm's 6502 SAP player, wired as docs/audio-worklet-sealed.js wires them).
//
// A synthetic TYPE B tune, assembled here: INIT sets SKCTL = 3, AUDCTL = 0 and a pure tone on
// channel 1 (AUDF1 = $40, AUDC1 = $A8: volume 8, 64 kHz base); PLAYER writes CONSOL ($D01F),
// a register nothing answers. Checked:
//   1. it loads and plays (mode 5, status 0), and the output is not silence;
//   2. the tone's pitch is the PAL POKEY's: 1773447.5 / 28 / (2 x 65) = 487.2 Hz, to 0.2 %
//      (NTSC would be 491.7 Hz, 0.9 % sharp: what an un-clocked POKEY plays a PAL tune at);
//   3. every PLAYER call's CONSOL write is counted (audioSapUnknownWrites), none lost;
//   4. a STEREO file is refused, with its reason, and plays nothing.
//
//   node apps/sap_check.mjs
//   node apps/sap_check.mjs --break ntsc   the fail proof: the POKEY clocked NTSC whatever the
//                                          player asks; the pitch check must catch it
import { readFile } from "node:fs/promises";

const AUDIO_PAGES = 48; // machine/sdk/audio.zig
const SR = 44100, BLOCK = 882, SECONDS = 2;
const BREAK = process.argv.includes("--break") ? process.argv[process.argv.indexOf("--break") + 1] : null;
if (BREAK !== null && BREAK !== "ntsc") { console.error(`sap_check: --break ${BREAK}: only "ntsc"`); process.exit(1); }

const hex = (s) => Uint8Array.from(s.match(/../g).map((b) => parseInt(b, 16)));
const INIT = hex("A9038D0FD2" + "A9008D08D2" + "A9408D00D2" + "A9A88D01D2" + "60");
const PLAYER = hex("8D1FD0" + "60");
function block(at, data) {
    const b = new Uint8Array(4 + data.length);
    new DataView(b.buffer).setUint16(0, at, true);
    new DataView(b.buffer).setUint16(2, at + data.length - 1, true);
    b.set(data, 4);
    return b;
}
function sap(tags) {
    const head = new TextEncoder().encode(`SAP\r\nNAME "tone"\r\n${tags}`);
    return new Uint8Array([...head, 0xff, 0xff, ...block(0x3000, INIT), ...block(0x3020, PLAYER)]);
}

async function boot() {
    const memory = new WebAssembly.Memory({ initial: AUDIO_PAGES, maximum: AUDIO_PAGES });
    const machine = (await WebAssembly.instantiate(await readFile("docs/machine-audio.wasm"), { env: { memory } })).instance.exports;
    const env = { memory };
    for (const n of Object.keys(machine)) if (n.startsWith("machine")) env[n] = machine[n];
    if (BREAK === "ntsc") env.machinePokeyClock = () => machine.machinePokeyClock(0);
    const audio = (await WebAssembly.instantiate(await readFile("docs/demo-audio.wasm"), { env })).instance.exports;
    audio.audioInit();
    return { memory, machine, audio };
}

function load(m, bytes) {
    new Uint8Array(m.memory.buffer, m.audio.audioSongPtr(), bytes.length).set(bytes);
    if (!m.audio.audioLoadSap(bytes.length)) return false;
    m.audio.audioSapPlay(0);
    return true;
}

/** Zero crossings of the left channel, rising, over `seconds`: the tone's frequency. */
function pitch(m, seconds) {
    let prev = 0, rises = 0, first = -1, last = -1, peak = 0, n = 0;
    const mean = 8 / 60 / 2; // a 50 % square at volume 8 of 60 averages this: remove the DC
    for (let done = 0; done < seconds * SR; done += BLOCK) {
        m.audio.audioRender(BLOCK);
        for (const s of new Float32Array(m.memory.buffer, m.machine.audioLeftPtr(), BLOCK)) {
            const x = s - mean;
            peak = Math.max(peak, Math.abs(x));
            if (prev < 0 && x >= 0) { rises++; if (first < 0) first = n; last = n; }
            prev = x;
            n++;
        }
    }
    return { hz: rises > 1 ? (rises - 1) * SR / (last - first) : 0, peak };
}

const errors = [];
const m = await boot();
if (!load(m, sap("TYPE B\r\nINIT 3000\r\nPLAYER 3020\r\n"))) errors.push(`the tone refused: status ${m.audio.audioSapStatus()}`);
if (m.audio.audioMode() !== 5 || m.audio.audioSapStatus() !== 0) errors.push(`mode ${m.audio.audioMode()}, status ${m.audio.audioSapStatus()}`);
const { hz, peak } = pitch(m, SECONDS);
const want = 1773447.5 / 28 / (2 * 65);
if (peak < 0.01) errors.push("silence");
if (Math.abs(hz / want - 1) > 0.002) errors.push(`the tone is ${hz.toFixed(1)} Hz, the PAL POKEY's is ${want.toFixed(1)} Hz`);
const calls = Math.floor(SECONDS * SR / (312 * 114 * SR / 1773447.5));
const unknown = m.audio.audioSapUnknownWrites();
if (Math.abs(unknown - calls) > 1 || m.audio.audioSapLostWrites() !== 0) errors.push(`${unknown} CONSOL writes counted for ${calls} PLAYER calls`);
const s = await boot();
if (load(s, sap("STEREO\r\nTYPE B\r\nINIT 3000\r\nPLAYER 3020\r\n")) || (s.audio.audioSapStatus() & 0xff) !== 5) errors.push(`a STEREO SAP was not refused as one: status ${s.audio.audioSapStatus()}`);

const report = `tone ${hz.toFixed(1)} Hz (PAL ${want.toFixed(1)}), peak ${peak.toFixed(3)}, ${unknown} unknown writes for ${calls} calls, STEREO refused`;
if (BREAK === "ntsc") {
    const caught = errors.some((e) => e.startsWith("the tone is"));
    console.log(caught ? `=> PASS ✅ fail proof: an NTSC-clocked POKEY is caught (${errors.join("; ")})`
        : `=> FAIL ❌ fail proof: an NTSC-clocked POKEY went unnoticed (${report})`);
    process.exit(caught ? 0 : 1);
}
if (errors.length) {
    console.log(`=> FAIL ❌ sap: ${errors.join("; ")}`);
    process.exit(1);
}
console.log(`=> PASS ✅ sap: ${report}`);
