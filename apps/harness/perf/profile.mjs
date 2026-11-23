// Turn per-frame counter deltas into op counts and estimated cycles (cost_model.mjs).
// One Profile per instrumented module; frame() is called after every host frame and
// returns that frame's cycles, accumulate=true adds the frame to the window sums.
import { CLASSES, regionCycles, fillCycles, copyCycles, misCopyCycles, DMISS, MISALIGNED } from "./cost_model.mjs";
import { PROBE_COUNTERS } from "./probe_hooks.mjs";
import { LOG_COUNT, LOG_BASE, BUCKETS, FIRST_COUNTER, KIND_COPY, VRAM_BYTES, BUCKET_SHIFT } from "./hooks.mjs";
import { WATCH_WORDS } from "./watch_hook.mjs";

const NCLS = CLASSES.length;
const NBUCKETS = VRAM_BYTES >> BUCKET_SHIFT;

export class Profile {
    constructor(tag, plan, mem) {
        this.tag = tag; this.plan = plan; this.mem = mem;
        this.prev = new Uint32Array(plan.words); this.d = new Uint32Array(plan.words);
        const nR = plan.regions.length, nS = plan.segFunc.length;
        this.rInstr = new Float64Array(nR); this.rStores = new Float64Array(nR); this.rExtra = new Float64Array(nR);
        this.sum = { cycles: new Float64Array(nR), iters: new Float64Array(nR), cls: new Float64Array(nR * NCLS), clsCyc: new Float64Array(nR * NCLS),
            instr: new Float64Array(nR), stores: new Float64Array(nR), seg: new Float64Array(nS),
            fill: new Float64Array(plan.fills.length), copy: new Float64Array(plan.copies.length), copyMis: new Float64Array(plan.copies.length),
            watch: new Float64Array(plan.watch.length * WATCH_WORDS), probe: new Float64Array(plan.probes.length * 2) };
        this.headSeg = new Int32Array(nR).fill(-1);
        for (let s = 0; s < nS; s++) if (this.headSeg[plan.segRegion[s]] < 0) this.headSeg[plan.segRegion[s]] = s;
        this.frames = 0;
    }

    delta() {
        const cur = new Uint32Array(this.mem.buffer, 0, this.plan.words), d = this.d;
        for (let i = FIRST_COUNTER; i < d.length; i++) d[i] = (cur[i] - this.prev[i]) >>> 0;
        this.prev.set(cur.subarray(FIRST_COUNTER), FIRST_COUNTER);
        return d;
    }

    // The VRAM pool as it is at frame start, for the store watch to compare with.
    snapshot(vram) { new Uint8Array(this.mem.buffer, 0, vram.length).set(vram); }

    // This frame's logged fills/copies, then the log is emptied: [{copy, site, dest, len, x}]
    takeLog() {
        const w = new Uint32Array(this.mem.buffer);
        const out = [];
        for (let i = 0; i < Math.min(w[LOG_COUNT], 4096); i++) {
            const e = LOG_BASE + 4 * i;
            out.push({ copy: w[e] >>> 28 === KIND_COPY, site: w[e] & 0xfffffff, dest: w[e + 1], len: w[e + 2], x: w[e + 3] });
        }
        w[LOG_COUNT] = 0;
        return out;
    }

    // Bytes stored into VRAM this frame per 256-byte bucket, then zeroed.
    takeBuckets() {
        const b = new Uint32Array(this.mem.buffer, 4 * BUCKETS, NBUCKETS), out = b.slice();
        b.fill(0);
        return out;
    }

    // round-3 probes: their counters, and the D$ model's misses as cycles of their loop
    probeFrame(d, accumulate) {
        const p = this.plan, S = this.sum;
        let misses = 0;
        p.probes.forEach((q, i) => {
            if (q.kind === "load" && d[q.word]) { this.rExtra[p.segRegion[q.seg]] += d[q.word] * DMISS; misses += d[q.word]; }
            if (q.kind === "align" && d[q.word]) this.rExtra[p.segRegion[q.seg]] += d[q.word] * MISALIGNED;
            if (accumulate) for (let k = 0; k < PROBE_COUNTERS[q.kind]; k++) S.probe[2 * i + k] += d[q.word + k];
        });
        this.misses = misses;
    }

    frame(accumulate) {
        const p = this.plan, d = this.delta(), S = this.sum;
        this.rInstr.fill(0); this.rStores.fill(0); this.rExtra.fill(0);
        let code = 0, fetch = 0; // rv32 code bytes this frame ran (the I$ working set), instructions fetched
        for (let s = 0; s < p.segFunc.length; s++) {
            const n = d[p.segWord[s]];
            if (!n) continue;
            const r = p.segRegion[s];
            code += 4 * p.segFetch[s]; fetch += n * p.segFetch[s];
            this.rInstr[r] += n * p.segInstr[s]; this.rStores[r] += n * p.segStores[s];
            if (!accumulate) continue;
            S.seg[s] += n;
            for (let c = 0; c < NCLS; c++) {
                const k = p.cls[s * NCLS + c];
                if (k) { S.cls[r * NCLS + c] += n * k; S.clsCyc[r * NCLS + c] += n * p.clsCyc[s * NCLS + c]; }
            }
        }
        p.fills.forEach((f, i) => { const b = d[f.word]; this.rExtra[p.segRegion[f.seg]] += fillCycles(b); if (accumulate) S.fill[i] += b; });
        p.copies.forEach((f, i) => {
            const b = d[f.word], mis = d[f.word + 1];
            this.rExtra[p.segRegion[f.seg]] += copyCycles(b) + misCopyCycles(mis);
            if (accumulate) { S.copy[i] += b; S.copyMis[i] += mis; }
        });
        if (accumulate) p.watch.forEach((f, i) => { for (let k = 0; k < WATCH_WORDS; k++) S.watch[i * WATCH_WORDS + k] += d[f.word + k]; });
        this.probeFrame(d, accumulate);
        let total = 0;
        for (let r = 0; r < this.rInstr.length; r++) {
            const c = regionCycles(this.rInstr[r], this.rStores[r]) + this.rExtra[r];
            total += c;
            if (!accumulate || !c) continue;
            S.cycles[r] += c; S.instr[r] += this.rInstr[r]; S.stores[r] += this.rStores[r];
            if (this.headSeg[r] >= 0) S.iters[r] += d[p.segWord[this.headSeg[r]]];
        }
        if (accumulate) this.frames++;
        this.last = { fetch, code };
        return total;
    }
}
