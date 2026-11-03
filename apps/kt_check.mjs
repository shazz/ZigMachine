// klystrack (.kt) player, on the real audio modules (docs/machine-audio.wasm + docs/demo-audio.wasm):
// the build the browser and BARD both run (BARD runs demo-audio through wasm2c).
//   pinned    each bundled song's core output (cyd's s16 stereo at 22050 Hz, audioKtRenderCore) for
//             45 s is upstream klystron's own render byte for byte: the sha256 below is
//             apps/ports/klystrack/kt_ref's (upstream cyd + music.c as the klystrack cart builds them),
//             the same pins as libs/zig/players/kt_core_test.zig
//   paula     through the Paula channels (two a side: high byte at 511/256, low byte at 2/256), each
//             44.1 kHz output frame is the core sample it holds, x 511/512, to within 1/32768, over
//             renders of 735 frames (odd: the held half-sample crosses every call)
//   plays     mode 1, never over full scale, both sides loud
//   refused   a non-.kt, a version from the future and a truncated file are refused with their
//             reasons (audioKtError) and counted (audioKtRejected)
//   node apps/kt_check.mjs [--break pin|lowbyte]
//     pin: a wrong pin fails; lowbyte: the low-byte channels silenced (8-bit sides) fail the paula check
import { readFile } from "node:fs/promises";
import { createHash } from "node:crypto";

const CORE_RATE = 22050, SECONDS = 45, BLOCK = 2000;
const PINS = { // kt_ref docs/music/<song>.kt 45 --raw out; sha256 out
    "starport2.kt": "fd83a9089664f7b902619bce63c063231f2dc0e6dd15f9237c5854b1ea2d4efe",
    "castlevania.kt": "c6dda9a8abc38ecc3156580a0d778067c7e5d4a8ad4596a301725083fabdb126",
    "oceanloader3.kt": "cb18d471add90a3369ae100250a1292a2bf065792ffdd0ebb5290bdf781a3cf0",
    "dpintro.kt": "ee798b13a10508a5c73ec8b98a808f7102580be43dccb5730b84c8b73dea95f5",
};
const BREAKS = ["pin", "lowbyte"];
const bi = process.argv.indexOf("--break");
const broke = bi > 0 ? process.argv[bi + 1] : null;
if (bi > 0 && !BREAKS.includes(broke)) throw new Error(`--break ${BREAKS.join(" | ")}`);

/** The audio modules with `bytes` staged and loaded (and started when it loads). */
async function machine(bytes) {
    const memory = new WebAssembly.Memory({ initial: 48, maximum: 48 });
    const m = (await WebAssembly.instantiate(await readFile("docs/machine-audio.wasm"), { env: { memory } })).instance.exports;
    const env = { memory };
    for (const n of Object.keys(m)) if (n.startsWith("machine")) env[n] = m[n];
    const a = (await WebAssembly.instantiate(await readFile("docs/demo-audio.wasm"), { env })).instance.exports;
    a.audioInit();
    new Uint8Array(memory.buffer, a.audioSongPtr(), bytes.length).set(bytes);
    const ok = a.audioLoadKt(bytes.length);
    if (ok) a.audioKtPlay(0);
    return { memory, m, a, ok };
}

/** sha256 of SECONDS of the core's s16 stereo, and the first `keep` samples of it. */
function corePin(x, keep) {
    const h = createHash("sha256");
    const kept = new Int16Array(2 * keep);
    for (let at = 0; at < SECONDS * CORE_RATE; at += BLOCK) {
        const n = Math.min(BLOCK, SECONDS * CORE_RATE - at);
        const p = x.a.audioKtRenderCore(n);
        if (!p) throw new Error("audioKtRenderCore refused");
        const blk = new Int16Array(x.memory.buffer, p, 2 * n);
        if (at < keep) kept.set(blk.subarray(0, Math.min(2 * n, 2 * (keep - at))), 2 * at);
        h.update(Buffer.from(blk.buffer, blk.byteOffset, blk.byteLength));
    }
    return { hash: h.digest("hex"), kept };
}

/** `frames` of machine output, rendered in 735-frame calls. */
function output(x, frames) {
    const left = new Float32Array(frames), right = new Float32Array(frames);
    for (let i = 0; i < frames; i += 735) {
        const n = Math.min(735, frames - i);
        x.a.audioRender(n);
        left.set(new Float32Array(x.memory.buffer, x.m.audioLeftPtr(), n), i);
        right.set(new Float32Array(x.memory.buffer, x.m.audioRightPtr(), n), i);
    }
    return { left, right };
}

async function song(name, errors, notes) {
    const bytes = new Uint8Array(await readFile(`docs/music/${name}`));
    const ref = await machine(bytes);
    if (!ref.ok || !ref.a.audioKtActive()) return errors.push(`plays: ${name} refused (error ${ref.a.audioKtError()})`);
    const FRAMES = 4 * 44100;
    const { hash, kept } = corePin(ref, FRAMES / 2 + 1);
    const pin = broke === "pin" ? "0".repeat(64) : PINS[name];
    if (hash !== pin) errors.push(`pinned: ${name} core sha256 ${hash} is not upstream's`);
    const x = await machine(bytes);
    if (x.a.audioMode() !== 1) errors.push(`plays: ${name} audioMode ${x.a.audioMode()}, not 1`);
    if (broke === "lowbyte") for (const ch of [2, 3]) x.m.machinePaulaSetVolume(ch, 0);
    const out = output(x, FRAMES);
    let worst = 0, peak = 0, sum = 0;
    for (let f = 0; f < FRAMES; f++) {
        for (const [side, buf] of [[0, out.left], [1, out.right]]) {
            const want = kept[2 * (f >> 1) + side] * (511 / 512) / 32768;
            worst = Math.max(worst, Math.abs(buf[f] - want) * 32768);
            peak = Math.max(peak, Math.abs(buf[f]));
            sum += buf[f] * buf[f];
        }
    }
    const rms = Math.sqrt(sum / (2 * FRAMES));
    if (worst > 1.0) errors.push(`paula: ${name} output off the core by ${worst.toFixed(2)}/32768`);
    if (peak > 1.0) errors.push(`plays: ${name} peak ${peak.toFixed(3)} over full scale`);
    if (!(rms > 0.01)) errors.push(`plays: ${name} silent (rms ${rms.toFixed(4)})`);
    notes.push(`${name}: core = upstream (${hash.slice(0, 12)}...), Paula within ${worst.toFixed(2)}/32768, peak ${peak.toFixed(3)}, rms ${rms.toFixed(3)}`);
}

async function refusals(errors, notes) {
    const good = new Uint8Array(await readFile("docs/music/castlevania.kt"));
    const future = Uint8Array.from(good);
    future[8] = 28;
    const cases = [[new TextEncoder().encode("not a klystrack song"), 1, "not a .kt"], [future, 2, "version 28"],
        [good.slice(0, good.length >> 1), 3, "truncated"]];
    const memory = new WebAssembly.Memory({ initial: 48, maximum: 48 });
    const m = (await WebAssembly.instantiate(await readFile("docs/machine-audio.wasm"), { env: { memory } })).instance.exports;
    const env = { memory };
    for (const n of Object.keys(m)) if (n.startsWith("machine")) env[n] = m[n];
    const a = (await WebAssembly.instantiate(await readFile("docs/demo-audio.wasm"), { env })).instance.exports;
    a.audioInit();
    for (const [bytes, want, what] of cases) {
        new Uint8Array(memory.buffer, a.audioSongPtr(), bytes.length).set(bytes);
        if (a.audioLoadKt(bytes.length)) errors.push(`refused: ${what} loaded`);
        else if (a.audioKtError() !== want) errors.push(`refused: ${what} gave reason ${a.audioKtError()}, not ${want}`);
    }
    if (a.audioKtRejected() !== cases.length) errors.push(`refused: ${a.audioKtRejected()} counted, not ${cases.length}`);
    notes.push(`refused: ${cases.map((c) => c[2]).join(", ")}, each with its reason`);
}

const errors = [], notes = [];
await refusals(errors, notes);
for (const name of Object.keys(PINS)) await song(name, errors, notes);
for (const n of notes) console.log(`  ${n}`);
// exitCode, never process.exit() (see apps/mod_sfx_check.mjs: node 24 deadlocks at exit).
if (broke) {
    const hit = errors.find((e) => e.startsWith(broke === "pin" ? "pinned:" : "paula:"));
    console.log(hit ? `kt_check: PASS (--break ${broke} caught: ${hit})` : `kt_check: FAILED -- --break ${broke} not caught (${errors.length} other errors)`);
    process.exitCode = hit ? 0 : 1;
} else {
    console.log(errors.length ? `kt_check: FAILED -- ${errors.join("; ")}` : "kt_check: all pass");
    process.exitCode = errors.length ? 1 : 0;
}
