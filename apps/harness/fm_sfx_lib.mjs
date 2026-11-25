// The FM device harnesses' common parts (fm_sfx_check.mjs, racer_audio_check.mjs): the effects script, the audio
// modules, the engine and output-stage renders on machine-audio.wasm.
import { readFile } from "node:fs/promises";

export const TUNE = "site/music/kr_race.vgm", FULL = "site/music/kestrel_fm.vgm", SECS = 4, LEAD = 3072, FRAME = 735;
export const OWN = 0x0c30; // FM 5-6, PSG tone 3, the noise


/** A patch's writes (port 1, slot r): carriers loud, held (AR 31, SL 0, RR 15), `tl` the modulators'. */
export function patch(r, alg, tl, t) {
    const w = [];
    for (let i = 0; i < 4; i++) for (const [reg, v] of [[0x30, 1 + i], [0x40, i === 3 ? 24 : tl], [0x50, 31], [0x60, 0], [0x70, 0], [0x80, 0x0f], [0x90, 0]]) w.push([t, 0x100 + reg + i * 4 + r, v]);
    w.push([t, 0x1b0 + r, alg], [t, 0x1b4 + r, 0xc0]);
    return w;
}

/** The effects: [stamp, addr, value] on the output clock, ascending: an engine sweep, impacts, beeps, noise, some refused. */
export function script(secs = SECS) {
    const w = [[0, 0x300, OWN], ...patch(2, 4, 28, 0), ...patch(1, 0, 20, 0), [0, 0x028, 0xf6]];
    let s = 7;
    const rnd = (n) => { s = (Math.imul(s, 1103515245) + 12345) >>> 0; return (s >>> 8) % n; };
    for (let t = FRAME, k = 0; t < secs * 44100; t += FRAME, k++) {
        const f = 300 + ((k * 37) % 900);
        w.push([t, 0x1a6, 3 << 3 | f >> 8], [t, 0x1a2, f & 255]);
        if (rnd(12) === 0) w.push([t, 0x028, 0x05], [t, 0x1a5, 2 << 3 | 2], [t, 0x1a1, 0xbc], [t, 0x028, 0xf5]);
        if (k % 20 === 0) w.push([t, 0x200, 0xc0 | rnd(16)], [t, 0x200, 4 + rnd(20)], [t, 0x200, 0xd3]);
        if (k % 20 === 8) w.push([t, 0x200, 0xdf]);
        if (k % 30 === 3) w.push([t, 0x200, 0xe5], [t, 0x200, 0xf6]);
        if (k % 30 === 9) w.push([t, 0x200, 0xff]);
        if (k % 45 === 5) w.push([t, 0x030, 0x71], [t, 0x200, 0x90], [t, 0x3ff, 1]); // FM 1, PSG tone 1, nothing: refused
    }
    return w;
}

export async function modules() {
    const memory = new WebAssembly.Memory({ initial: 48, maximum: 48 });
    const m = (await WebAssembly.instantiate(await readFile("site/machine-audio.wasm"), { env: { memory } })).instance.exports;
    const env = { memory };
    for (const n of Object.keys(m)) if (n.startsWith("machine")) env[n] = m[n];
    const a = (await WebAssembly.instantiate(await readFile("site/demo-audio.wasm"), { env })).instance.exports;
    a.audioInit();
    return { memory, m, a };
}

export const fnv = (h, bytes) => { for (const v of bytes) h = Math.imul(h ^ v, 16777619) >>> 0; return h; };

/** machine-audio.wasm: the device on, the tune loaded, the script fed `feed` early, the stage in `block`-frame calls. */
export async function wasmStage(w, block, feed, tune = TUNE) {
    const { memory, m, a } = await modules();
    const at = a.audioSongPtr(), total = SECS * 44100, ch = [0, 1, 2, 3].map((c) => at + 0xe0000 + c * 4096), out = [0, 1, 2, 3].map(() => new Uint8Array(total));
    m.machineVgmSfxOn(1);
    if (tune) { const b = await readFile(tune); new Uint8Array(memory.buffer, at, b.length).set(b); m.machineVgmLoad(at, b.length, 0xe0000); }
    let i = 0;
    for (let done = 0; done < total;) {
        while (i < w.length && w[i][0] < done + block + feed && m.machineVgmSfxPush(...w[i])) i++;
        const k = Math.min(block, total - done);
        m.machineVgmRenderPaula(ch[0], ch[1], ch[2], ch[3], k);
        for (let c = 0; c < 4; c++) out[c].set(new Uint8Array(memory.buffer, ch[c], k), done);
        done += k;
    }
    const hashes = [];
    for (let b = 0; b < SECS * 10; b++) hashes.push(out.reduce((h, o) => fnv(h, o.subarray(b * 4410, (b + 1) * 4410)), 2166136261).toString(16).padStart(8, "0"));
    const stats = `applied ${m.machineVgmSfxStat(0)} refused ${m.machineVgmSfxStat(1)} late ${m.machineVgmSfxStat(3)} pending ${m.machineVgmSfxStat(2)} pushed ${i}`;
    return { hashes, stats, out };
}



/** The engine's s16 (machineVgmRender: no output stage, so stamp s maps to engine frame 2 + s x rate / 44,100). */
export async function engine(w, frames, tune = null) {
    const { memory, m, a } = await modules();
    const at = a.audioSongPtr(), dst = at + 0xe0000;
    m.machineVgmSfxOn(1);
    if (tune) { const b = await readFile(tune); new Uint8Array(memory.buffer, at, b.length).set(b); m.machineVgmLoad(at, b.length, 0xe0000); }
    for (const x of w) if (!m.machineVgmSfxPush(...x)) throw new Error("engine: the ring refused a write");
    const pcm = new Int16Array(2 * frames);
    for (let done = 0; done < frames; done += 1024) {
        const k = Math.min(1024, frames - done);
        m.machineVgmRender(dst, k);
        pcm.set(new Int16Array(memory.buffer, dst, 2 * k), 2 * done);
    }
    return { pcm, rate: m.machineVgmRate(), m };
}

export const onset = (pcm) => { for (let i = 0; i < pcm.length; i++) if (pcm[i]) return i >> 1; return -1; };
