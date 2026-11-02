// Helpers for apps/pt2_paula_headless.mjs (HW 1.14.0, the Paula channels lent to a cart): the real
// audio worklet (docs/audio-worklet-sealed.js) in node, the cart's hostPaula* imports wired to it as
// docs/sealed-loader.js wires them, and the two measures that compare a sound with another made a
// different way: the loudness envelope (does it follow the pattern) and the band spectrum (is it the
// same pitch).
import { readFile } from "node:fs/promises";

export const RATE = 44100;

// The worklet with a stand-in AudioWorkletProcessor (apps/st_replay_outputs_check.mjs does the same);
// its own messages (paulaRefused...) are kept in `said`.
export async function bootWorklet() {
    let Proc;
    globalThis.AudioWorkletProcessor = class { constructor() { this.port = { postMessage() {} }; } };
    globalThis.registerProcessor = (_name, cls) => { Proc = cls; };
    await import("../docs/audio-worklet-sealed.js");
    const p = new Proc({ processorOptions: {
        machineBytes: await readFile("docs/machine-audio.wasm"), demoBytes: await readFile("docs/demo-audio.wasm") } });
    for (let i = 0; i < 200 && !p.ready; i++) await new Promise((r) => setTimeout(r, 10));
    if (!p.ready) throw new Error("the worklet never came up");
    const said = [];
    p.port.postMessage = (m) => said.push(m);
    const send = (data) => p.port.onmessage({ data });
    const l = new Float32Array(128), r = new Float32Array(128);
    const out = [];
    const render = (blocks) => { // `blocks` of 128 frames, (L+R)/2 kept
        for (let b = 0; b < blocks; b++) {
            p.process([], [[l, r]]);
            const mono = new Float32Array(128);
            for (let i = 0; i < 128; i++) mono[i] = (l[i] + r[i]) / 2;
            out.push(mono);
        }
    };
    const samples = () => { const all = new Float32Array(out.length * 128); out.forEach((b, i) => all.set(b, i * 128)); return all; };
    return { p, d: p.demo, send, render, samples, said };
}

// The cart's env.hostPaula* as the loader serves them, posting to `w`. `tamper` (a break) may rewrite a
// write batch or drop an upload before it is posted.
export function paulaEnv(getMemory, w, tamper = {}) {
    const st = { claims: 0, uploads: 0, writes: 0, entries: 0 };
    return {
        st,
        env: {
            hostPaulaClaim: (lead) => { st.claims++; w.send({ type: "paulaClaim", lead, chip: null }); return 1; },
            hostPaulaUpload: (src, off, len) => {
                st.uploads++;
                if (tamper.dropUploads) return;
                w.send({ type: "paulaUpload", off, bytes: new Uint8Array(getMemory().buffer, src, len).slice().buffer });
            },
            hostPaulaWrite: (ptr, n) => {
                st.writes++;
                st.entries += n;
                const bytes = new Uint8Array(getMemory().buffer, ptr, 16 * n).slice();
                if (tamper.batch) tamper.batch(new DataView(bytes.buffer), n);
                w.send({ type: "paulaWrite", bytes: bytes.buffer });
            },
            hostPaulaRelease: () => w.send({ type: "paulaRelease" }),
        },
    };
}

// RMS per `win` samples.
export function envelope(x, win) {
    const n = Math.floor(x.length / win), e = new Float64Array(n);
    for (let i = 0; i < n; i++) {
        let s = 0;
        for (let j = 0; j < win; j++) { const v = x[i * win + j]; s += v * v; }
        e[i] = Math.sqrt(s / win);
    }
    return e;
}

// Pearson correlation of a and b shifted by `lag` (b[i + lag] against a[i]).
export function corr(a, b, lag = 0) {
    const pairs = [];
    for (let i = 0; i < a.length; i++) if (i + lag >= 0 && i + lag < b.length) pairs.push([a[i], b[i + lag]]);
    const n = pairs.length;
    if (n < 8) return 0;
    let ma = 0, mb = 0;
    for (const [x, y] of pairs) { ma += x; mb += y; }
    ma /= n; mb /= n;
    let sab = 0, saa = 0, sbb = 0;
    for (const [x, y] of pairs) { sab += (x - ma) * (y - mb); saa += (x - ma) ** 2; sbb += (y - mb) ** 2; }
    return saa && sbb ? sab / Math.sqrt(saa * sbb) : 0;
}

// The best correlation over lags -max..max, and its lag.
export function bestCorr(a, b, max) {
    let best = { c: -2, lag: 0 };
    for (let lag = -max; lag <= max; lag++) { const c = corr(a, b, lag); if (c > best.c) best = { c, lag }; }
    return best;
}

// Energy in semitone bands from 60 Hz to 4 kHz, summed over frames of ~0.19 s (Hann; ~5.5 Hz bins at
// either rate), unit length. A semitone apart, two pitches share no band: an octave off is far.
const BANDS = 72;
export function bandSpectrum(x, rate) {
    const N = rate > 30000 ? 8192 : 4096;
    const edges = Array.from({ length: BANDS + 1 }, (_, i) => 60 * Math.pow(2, i / 12));
    const bands = new Float64Array(BANDS), re = new Float64Array(N), im = new Float64Array(N);
    for (let at = 0; at + N <= x.length; at += N) {
        for (let i = 0; i < N; i++) { re[i] = x[at + i] * (0.5 - 0.5 * Math.cos((2 * Math.PI * i) / N)); im[i] = 0; }
        fft(re, im);
        for (let k = 1; k < N / 2; k++) {
            const b = Math.floor(12 * Math.log2((k * rate) / N / 60));
            if (b >= 0 && b < BANDS) bands[b] += re[k] * re[k] + im[k] * im[k];
        }
    }
    const len = Math.hypot(...bands) || 1;
    return bands.map((v) => v / len);
}

export const cosine = (a, b) => a.reduce((s, v, i) => s + v * b[i], 0);

function fft(re, im) { // in place, radix 2
    const n = re.length;
    for (let i = 1, j = 0; i < n; i++) {
        let bit = n >> 1;
        for (; j & bit; bit >>= 1) j ^= bit;
        j ^= bit;
        if (i < j) { [re[i], re[j]] = [re[j], re[i]]; [im[i], im[j]] = [im[j], im[i]]; }
    }
    for (let len = 2; len <= n; len <<= 1) {
        const a = (-2 * Math.PI) / len;
        for (let i = 0; i < n; i += len) {
            for (let k = 0; k < len / 2; k++) {
                const wr = Math.cos(a * k), wi = Math.sin(a * k), u = i + k, v = u + len / 2;
                const tr = re[v] * wr - im[v] * wi, ti = re[v] * wi + im[v] * wr;
                re[v] = re[u] - tr; im[v] = im[u] - ti; re[u] += tr; im[u] += ti;
            }
        }
    }
}
