// FastTracker 2 (.XM) player, on the real audio modules (docs/machine-audio.wasm +
// docs/demo-audio.wasm), playing apps/xm_song.mjs's test song through the sealed
// Paula channels the eight voices are mixed onto.
//   loads     the song is staged, checked and played (mode 1, the MOD's scope view)
//   refused   a 9-channel file, a non-XM, and a file cut short are refused, each
//             with its reason (audioXmError) and counted (audioXmRejected)
//   plays     four seconds: never over full scale, not silent, both channels
//   pinned    the same song rendered twice is byte-identical, and matches the
//             sha256 pinned below (any change to the mixer, the sequencer or the
//             tables moves it: re-pin only with a reason)
//   node apps/xm_check.mjs [--break refuse|pin]
//     refuse: a 9-channel file expected to load fails; pin: a wrong pin fails
import { readFile } from "node:fs/promises";
import { createHash } from "node:crypto";
import { testSong } from "./xm_song.mjs";

const SR = 44100, SECONDS = 4, FRAMES = SR * SECONDS;
// Re-pinned 2026-10-15 for the 32-bit mixer (BARD has no 64-bit ALU): the linear
// pitch table is Q16 (not Q24), and a 9xx past the sample's end is silent, as FT2
// has it, where it used to wrap. Both move the output; the render stays identical run to run.
// Re-pinned 2026-10-17 for FT2 behaviour checked against libopenmpt: the envelope
// moves on every tick and holds at its sustain point, the fadeout runs at FT2's
// rate, key-off cuts an envelope-less note, an instrument number resets the
// volume (a bare note keeps it), vibrato is FT2's depth, and the volume column
// slides. (Amiga pitch was fixed too; this song is linear.)
const PINNED = "b2ccec0f0e35b96a32bee8e7f4f38eb8fc3c8472afd6449728dc2e51d9185fe3";
const BREAKS = ["refuse", "pin"];
const bi = process.argv.indexOf("--break");
const broke = bi > 0 ? process.argv[bi + 1] : null;
if (bi > 0 && !BREAKS.includes(broke)) throw new Error(`--break ${BREAKS.join(" | ")}`);

/** The audio modules: the sealed chip (machine-audio) and the players (demo-audio). */
async function machine() {
    const memory = new WebAssembly.Memory({ initial: 48, maximum: 48 });
    const m = (await WebAssembly.instantiate(await readFile("docs/machine-audio.wasm"), { env: { memory } })).instance.exports;
    const env = { memory };
    for (const n of Object.keys(m)) if (n.startsWith("machine")) env[n] = m[n];
    const a = (await WebAssembly.instantiate(await readFile("docs/demo-audio.wasm"), { env })).instance.exports;
    a.audioInit();
    const stage = (bytes) => {
        new Uint8Array(memory.buffer, a.audioSongPtr(), bytes.length).set(bytes);
        return bytes.length;
    };
    const render = (n) => {
        const left = new Float32Array(n), right = new Float32Array(n);
        for (let i = 0; i < n; i += 128) {
            a.audioRender(128);
            left.set(new Float32Array(memory.buffer, m.audioLeftPtr(), 128).subarray(0, Math.min(128, n - i)), i);
            right.set(new Float32Array(memory.buffer, m.audioRightPtr(), 128).subarray(0, Math.min(128, n - i)), i);
        }
        return { left, right };
    };
    return { a, stage, render };
}

/** One full run: load the song, play it, render FRAMES; the output and its pin. */
async function play(bytes) {
    const x = await machine();
    if (!x.a.audioLoadXm(x.stage(bytes))) throw new Error(`audioLoadXm refused: error ${x.a.audioXmError()}`);
    x.a.audioXmPlay(0);
    const out = x.render(FRAMES);
    const hash = createHash("sha256").update(Buffer.from(out.left.buffer)).update(Buffer.from(out.right.buffer)).digest("hex");
    return { x, out, hash };
}

/** Refused, with a reason, and counted: each of the three bad files. */
async function refusals(errors, notes) {
    const good = testSong();
    const nine = Uint8Array.from(good);
    nine[68] = 9; // channels
    const notXm = Uint8Array.from(good);
    notXm[0] = 0x58; // 'X'
    const cut = good.slice(0, 400); // the second pattern runs past the end
    const cases = [[nine, 5, "9 channels"], [notXm, 2, "not an XM"], [cut, 11, "truncated"]];
    if (broke === "refuse") cases[0] = [good, 5, "9 channels (--break refuse: the 8-channel song sent as 9)"];
    const x = await machine();
    for (const [bytes, want, what] of cases) {
        const ok = x.a.audioLoadXm(x.stage(bytes));
        if (ok) errors.push(`refuse: ${what} loaded`);
        else if (x.a.audioXmError() !== want) errors.push(`refuse: ${what} gave reason ${x.a.audioXmError()}, not ${want}`);
    }
    if (x.a.audioXmRejected() !== cases.length) errors.push(`refuse: ${x.a.audioXmRejected()} rejections counted, not ${cases.length}`);
    notes.push(`${cases.length} bad files refused with their reasons and counted (9 channels, not an XM, truncated)`);
}

const errors = [], notes = [];
const song = testSong();
await refusals(errors, notes);
const first = await play(song);
if (first.x.a.audioMode() !== 1) errors.push(`loads: audioMode ${first.x.a.audioMode()}, not 1`);
let peak = 0, sum = 0;
for (let i = 0; i < FRAMES; i++) {
    for (const v of [first.out.left[i], first.out.right[i]]) {
        peak = Math.max(peak, Math.abs(v));
        sum += v * v;
    }
}
const rms = Math.sqrt(sum / (2 * FRAMES));
if (peak > 1.0) errors.push(`plays: peak ${peak.toFixed(3)} over full scale`);
if (!(rms > 0.01)) errors.push(`plays: silent (rms ${rms.toFixed(4)})`);
notes.push(`plays: ${SECONDS} s, peak ${peak.toFixed(3)}, rms ${rms.toFixed(3)}`);
const second = await play(song);
if (second.hash !== first.hash) errors.push("pinned: a second render of the same song differs");
const pin = broke === "pin" ? "0".repeat(64) : PINNED;
if (pin === PINNED && PINNED === "PIN_PENDING") errors.push(`pinned: no pin yet (rendered sha256 ${first.hash})`);
else if (first.hash !== pin) errors.push(`pinned: sha256 ${first.hash} is not the pin`);
notes.push(`pinned: sha256 ${first.hash.slice(0, 16)}...`);

for (const n of notes) console.log(`  ${n}`);
// exitCode, never process.exit() (see apps/mod_sfx_check.mjs: node 24 deadlocks at exit).
if (broke) {
    const hit = errors.find((e) => e.startsWith(`${broke === "pin" ? "pinned" : broke}:`));
    console.log(hit ? `xm_check: PASS (--break ${broke} caught: ${hit})` : `xm_check: FAILED -- --break ${broke} not caught (${errors.length} other errors)`);
    process.exitCode = hit ? 0 : 1;
} else {
    console.log(errors.length ? `xm_check: FAILED -- ${errors.join("; ")}` : "xm_check: all pass");
    process.exitCode = errors.length ? 1 : 0;
}
