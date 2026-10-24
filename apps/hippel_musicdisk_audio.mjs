// Plays a .hip song on the machine's Hippel player (demo-audio.wasm: its own 68000
// replay + the emulated Paula, libs/zig/players/hip_player.zig) for `seconds` and
// returns what it did. Used by apps/hippel_musicdisk_headless.mjs.
//
// null when that demo-audio.wasm has no .hip player (built before it landed): the
// caller must say so out loud, never pass silently.
import { readFile } from "node:fs/promises";

export async function playHip(dir, file, song, seconds) {
    const memory = new WebAssembly.Memory({ initial: 48, maximum: 48 }); // machine/sdk/audio.zig
    const machine = (await WebAssembly.instantiate(await readFile(`${dir}/machine-audio.wasm`), { env: { memory } })).instance.exports;
    const env = { memory };
    for (const n of Object.keys(machine)) if (n.startsWith("machine")) env[n] = machine[n];
    const a = (await WebAssembly.instantiate(await readFile(`${dir}/demo-audio.wasm`), { env })).instance.exports;
    if (!a.audioLoadHip) return null;
    a.audioInit();
    new Uint8Array(memory.buffer, a.audioSongPtr(), file.length).set(file);
    if (!a.audioLoadHip(file.length)) return { error: "the Hippel player refused it" };
    a.audioHipPlay(song);
    if (!a.audioHipActive()) return { error: `INIT never returned (stuck at $${a.audioSndhStuckPc().toString(16)})` };
    let lo = Infinity, hi = -Infinity, sig = 0;
    for (let done = 0; done < seconds * 44100; done += 1024) {
        a.audioRender(1024);
        for (const ptr of [machine.audioLeftPtr(), machine.audioRightPtr()])
            for (const s of new Float32Array(memory.buffer, ptr, 1024)) {
                lo = Math.min(lo, s); hi = Math.max(hi, s);
                sig = (Math.imul(sig, 31) + Math.round(s * 4096)) | 0; // tells two songs apart
            }
    }
    if (!a.audioHipActive()) return { error: `the replay ran away (stuck at $${a.audioSndhStuckPc().toString(16)})` };
    return {
        span: hi - lo,
        sig,
        voices: [0, 1, 2, 3].filter((ch) => a.audioHipStarts(ch) > 0).length,
        bad: a.audioHipBadPointers() + a.audioUnhandledCount(),
    };
}
