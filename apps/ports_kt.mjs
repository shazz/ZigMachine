// The klystrack cart's songs on the machine's .kt player (apps/ports/klystrack/kestrel_bard.c): what the
// cart asks for through the song bridge and the effects queue each frame (ports_machine.mjs step), and the
// handed-over .kt played on the real audio modules (docs/machine-audio.wasm + docs/demo-audio.wasm).
import { readFile } from "node:fs/promises";

/** The frame's song requests: a name ("none" stops) or a requestSongBytes image ({kind, row, bytes}). */
export function drainSongs(m, frame) {
    const d = m.demo;
    if (d.pollSongRequest && d.pollSongRequest()) {
        const name = new TextDecoder().decode(new Uint8Array(m.memory.buffer, d.songNamePtr(), d.songNameLen()));
        m.songs.push({ frame, name });
    }
    const n = d.pollSfx ? d.pollSfx() : 0;
    if (!n) return;
    const dv = new DataView(m.memory.buffer, d.sfxEntriesPtr(), 16 * n);
    for (let i = 0; i < n; i++) {
        if (dv.getUint8(16 * i) !== 8) continue; // only song images here
        const ptr = dv.getUint32(16 * i + 4, true), len = dv.getUint32(16 * i + 8, true);
        m.songs.push({ frame, kind: dv.getUint8(16 * i + 1), row: dv.getUint32(16 * i + 12, true),
            bytes: new Uint8Array(m.memory.buffer, ptr, len).slice() });
    }
}

/** The .kt played from `row` for `seconds` on the audio modules: refusal reason, mode and loudness. */
export async function playKt(bytes, row, seconds = 2) {
    const memory = new WebAssembly.Memory({ initial: 48, maximum: 48 });
    const mach = (await WebAssembly.instantiate(await readFile("docs/machine-audio.wasm"), { env: { memory } })).instance.exports;
    const env = { memory };
    for (const k of Object.keys(mach)) if (k.startsWith("machine")) env[k] = mach[k];
    const a = (await WebAssembly.instantiate(await readFile("docs/demo-audio.wasm"), { env })).instance.exports;
    a.audioInit();
    new Uint8Array(memory.buffer, a.audioSongPtr(), bytes.length).set(bytes);
    if (!a.audioLoadKt(bytes.length)) return { ok: false, error: a.audioKtError() };
    a.audioKtPlay(row);
    let sum = 0, peak = 0;
    const frames = Math.round(seconds * 60);
    for (let f = 0; f < frames; f++) {
        a.audioRender(735);
        for (const v of new Float32Array(memory.buffer, mach.audioLeftPtr(), 735)) { sum += v * v; peak = Math.max(peak, Math.abs(v)); }
    }
    return { ok: a.audioKtActive(), mode: a.audioMode(), rms: Math.sqrt(sum / (735 * frames)), peak };
}
