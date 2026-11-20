// The MPEG-2 / 2.5 (LSF) half of apps/mp3_check.mjs: 576-sample frames, rates under 32 kHz, mono.
// Each stream (apps/zig/assets/mp3/LSF*, a 1000 Hz sine, 1500 Hz on the right when stereo) is played as a
// cart plays it and held to:
//   rate     the status word's rate code and channel bit
//   length   frames x 576 x 44100 / rate output samples, ended in the block after, then silence
//   decode   pvmp3's output = the host decode (fpga/tools/mp3_ref.sh): at an exact ratio (22.05 = x2,
//            11.025 = x4) every Nth output sample IS a source sample >> 1, so the pinned host-decode hash
//            must match it; the samples between are the linear midpoints (no drift over the whole file)
//   output   the converted output hashed (integer code: the same on every host)
//   pitch    the tone read back from the 44.1 kHz output (Goertzel peak), within 10 Hz
//   mono     both sides the same
// --break lsfpitch: every other output sample dropped (a player running at the wrong rate) fails pitch+length;
// --break lsfmono: the right side silenced fails mono.
import { readFile } from "node:fs/promises";

export const LSF = {
    "LSF22M.MP3": { rate: 22050, code: 5, ch: 1, frames: 117, ref: "44892751b7c08639765b8a053346728d6ac556823397760b3cb5a05194612379", out: "211fc8cfa84f04451f8611c2470d8ec550d82aeda46f52b8a5e67f05ad805460" },
    "LSF22S.MP3": { rate: 22050, code: 5, ch: 2, frames: 117, ref: "afaca746836b493b16a16cec06ea71eddb8432f34738c40fe06982a60b55bbaa", out: "29d2a80b0d8a892d2592b59394a09abbe5c30202cc223fde9b64ed1e649d39ca" },
    "LSF24M.MP3": { rate: 24000, code: 6, ch: 1, frames: 127, ref: "fe9969b63729b05a0933993f7078ac7b1fbbdaff4203c071ab2721053103838e", out: "4500b25c5405fd68952262185d2422da19fc49282b896a7b3d2f9da51cc149cb" },
    "LSF16M.MP3": { rate: 16000, code: 7, ch: 1, frames: 86, ref: "a3aade775dd8b76063824d10da6c418d2d35d56c3aef28cfedea0e7758368ddd", out: "2c672baedf956b847df0bbf733aac03e8caafc9fcd972c53f7b65b97006f7298" },
    "LSF11M.MP3": { rate: 11025, code: 9, ch: 1, frames: 60, ref: "34ca6c55bdf7871fc84a0f244d67d07148d3ef2a006adf3da923265b4452b8be", out: "1ad2ff13ac624d6d648be7e8a01afa7af107a9e07a85addadc756a7b3839845b" },
};
const OUT = 44100;

/** Goertzel power of `x` at `hz`. */
function power(x, hz) {
    const k = 2 * Math.cos((2 * Math.PI * hz) / OUT);
    let s1 = 0, s2 = 0;
    for (const v of x) { const s = v + k * s1 - s2; s2 = s1; s1 = s; }
    return s1 * s1 + s2 * s2 - k * s1 * s2;
}

/** The strongest frequency in 500..2500 Hz of x[from .. from + 22050) (the file is 3 s of a steady tone). */
export function peak(x, from = 22050) {
    const w = x.slice(from, from + 22050);
    let best = 0, at = 0;
    for (let hz = 500; hz <= 2500; hz += 2) { const p = power(w, hz); if (p > best) { best = p; at = hz; } }
    return at;
}

export async function lsf(name, ctx, errors, notes) {
    const p = LSF[name], { play, modules, sha, DIR, BLOCK, broke } = ctx;
    const bytes = new Uint8Array(await readFile(`${DIR}/${name}`));
    const o = play(await modules(), bytes);
    const want = Math.floor((p.frames * 576 * OUT) / p.rate);
    let L = o.L.slice(0, want), R = o.R.slice(0, want);
    if (broke === "lsfpitch") { L = L.filter((_, i) => i % 2 === 0); R = R.filter((_, i) => i % 2 === 0); }
    if (broke === "lsfmono") R = R.map(() => 0);
    const tag = `lsf: ${name}`;
    if (((o.word >> 4) & 15) !== p.code) errors.push(`${tag} rate code ${(o.word >> 4) & 15}, not ${p.code}`);
    if (((o.word >> 8) & 1) !== (p.ch === 2 ? 1 : 0)) errors.push(`${tag} channel bit ${(o.word >> 8) & 1}`);
    if (!o.ended || o.frames !== p.frames) errors.push(`${tag} ended ${o.ended}, ${o.frames} frames, not ${p.frames}`);
    if (o.endAt < want || o.endAt - want > BLOCK + 2) errors.push(`${tag} ended after ${o.endAt} output samples, not in the block after ${want}`);
    if (L.length !== want) errors.push(`${tag} ${L.length} output samples, not ${want}`);
    if (o.word >>> 24 || o.dropped) errors.push(`${tag} ${o.word >>> 24} underruns, ${o.dropped} bytes dropped`);
    if (!o.L.slice(want + BLOCK + 2).every((v) => v === 0)) errors.push(`${tag} not silent after the end`);
    if (p.ch === 1 && !L.every((v, i) => v === R[i])) errors.push(`${tag} mono sides differ`);
    const hz = peak(L), hzR = p.ch === 2 ? peak(R) : 0;
    if (Math.abs(hz - 1000) > 10) errors.push(`${tag} pitch ${hz} Hz, not 1000`);
    if (p.ch === 2 && Math.abs(hzR - 1500) > 10) errors.push(`${tag} right pitch ${hzR} Hz, not 1500`);
    const amp = Math.max(...L.slice(22050, 44100).map(Math.abs)); // 0.5 full scale, >> 1: 8192
    if (Math.abs(amp - 8192) > 800) errors.push(`${tag} tone amplitude ${amp}, not 8192 +-800`);
    const step = OUT / p.rate;
    let exactNote = "not an exact ratio: output pinned";
    if (Number.isInteger(step)) exactNote = exactRatio(p, o, step, want, sha, errors, tag);
    const conv = [];
    for (let i = 0; i < want; i++) p.ch === 2 ? conv.push(o.L[i], o.R[i]) : conv.push(o.L[i]);
    const got = sha(conv);
    if (!broke && got !== p.out) errors.push(`${tag} converted output ${got} is not the pin`);
    notes.push(`${name}: rate code ${p.code}, ${p.frames} frames x 576 = ${want} samples at 44.1, tone ${hz} Hz${p.ch === 2 ? ` / ${hzR} Hz` : ""}, ${exactNote}, out ${got.slice(0, 12)}...`);
}

/** At an integer ratio every `step`th output sample is a source sample >> 1 (the host decode's, pinned),
 *  and the ones between are the linear midpoints, to a sample or two: no drift against the stream. */
function exactRatio(p, o, step, want, sha, errors, tag) {
    const n = want / step - 1, src = []; // the last source sample is not played: the player ends as the converter asks for the one after it
    for (let k = 0; k < n; k++) for (let c = 0; c < p.ch; c++) src.push((c ? o.R : o.L)[k * step]);
    if (sha(src) !== p.ref) errors.push(`${tag} every ${step}th output sample is not the host decode >> 1 (${sha(src).slice(0, 12)})`);
    let worst = 0;
    for (let k = 0; k < n - 1; k++) for (let j = 1; j < step; j++) {
        const a = o.L[k * step], b = o.L[(k + 1) * step], v = o.L[k * step + j];
        worst = Math.max(worst, Math.abs(v - (a + ((b - a) * j) / step)));
    }
    if (worst > 2) errors.push(`${tag} interpolated samples drift ${worst} from the linear midpoints`);
    return `exact x${step} (= host decode >> 1, midpoints within ${worst.toFixed(1)})`;
}
