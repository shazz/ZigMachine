// Turn per-frame counter deltas into op counts and estimated cycles (cost_model.mjs).
// One Profile per instrumented module; frame() is called after every host frame and
// returns that frame's cycles, accumulate=true adds the frame to the window sums.
import { CLASSES, regionCycles, fillCycles, copyCycles } from "./cost_model.mjs";
import { LOG_COUNT, LOG_BASE } from "./hooks.mjs";

const NCLS = CLASSES.length;

export class Profile {
    constructor(tag, plan, mem) {
        this.tag = tag; this.plan = plan; this.mem = mem;
        this.prev = new Uint32Array(plan.words);
        const nR = plan.regions.length, nS = plan.segFunc.length;
        this.rInstr = new Float64Array(nR); this.rStores = new Float64Array(nR); this.rExtra = new Float64Array(nR);
        this.sum = { cycles: new Float64Array(nR), iters: new Float64Array(nR), cls: new Float64Array(nR * NCLS), clsCyc: new Float64Array(nR * NCLS),
            instr: new Float64Array(nR), stores: new Float64Array(nR), seg: new Float64Array(nS),
            fill: new Float64Array(plan.fills.length), copy: new Float64Array(plan.copies.length),
            pal: new Float64Array(plan.pals.length * 2) };
        this.headSeg = new Int32Array(nR).fill(-1);
        for (let s = 0; s < nS; s++) if (this.headSeg[plan.segRegion[s]] < 0) this.headSeg[plan.segRegion[s]] = s;
        this.frames = 0;
    }

    delta() {
        const cur = new Uint32Array(this.mem.buffer, 0, this.plan.words);
        const d = new Uint32Array(this.plan.words);
        for (let i = 0; i < d.length; i++) d[i] = (cur[i] - this.prev[i]) >>> 0;
        this.prev.set(cur);
        return d;
    }

    // Big fills logged this frame, then the log is emptied: [{site, dest, len, value}]
    takeLog() {
        const w = new Uint32Array(this.mem.buffer);
        const out = [];
        for (let i = 0; i < w[LOG_COUNT]; i++) {
            const e = LOG_BASE + 4 * i;
            out.push({ site: w[e], dest: w[e + 1], len: w[e + 2], value: w[e + 3] & 0xff });
        }
        w[LOG_COUNT] = 0;
        this.prev[LOG_COUNT] = 0;
        return out;
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
        p.copies.forEach((f, i) => { const b = d[f.word]; this.rExtra[p.segRegion[f.seg]] += copyCycles(b); if (accumulate) S.copy[i] += b; });
        if (accumulate) p.pals.forEach((f, i) => { S.pal[2 * i] += d[f.word]; S.pal[2 * i + 1] += d[f.word + 1]; });
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
