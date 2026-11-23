// Dynamic waste detectors, frame by frame ("only modify what needs to be modified"):
// bytes stored into VRAM against bytes that changed, planes that never change, composed
// lines that changed, scrolled rows rewritten by the CPU, big fills undone by their
// redraw, tiny blits. before() runs ahead of each host frame, after() behind it.
import { VRAM_BYTES, BUCKET_SHIFT } from "./hooks.mjs";
import { planes, diffBuckets, sumBuckets, changedLines, shiftedRows, PFB_W, PFB_H } from "./frame_diff.mjs";

export const TINY_BLIT = 256;      // bytes: under this a blit's per-op cost (D$ flush) dominates
const CLEAR_MIN = 16000;           // a fill this big is a plane clear

export class Waste {
    constructor(run) {
        this.run = run; this.base = run.machine.hwVideoBase();
        this.vram = new Uint8Array(run.memory.buffer, run.vlo, VRAM_BYTES);
        this.snap = new Uint8Array(VRAM_BYTES);
        this.pfb = new Uint32Array(PFB_W * PFB_H);
        this.w = { frames: 0, stored: 0, changed: 0, lines: 0, planes: new Map(), fills: new Map(), clears: new Map(),
            blits: new Map(), scroll: new Map() };
    }

    before(profiles) {
        this.snap.set(this.vram);
        for (const P of profiles) P.snapshot(this.snap);
        this.run.hw.blitLog = [];
    }

    after(profiles, acc) {
        const logs = profiles.map((P) => P.takeLog()), buckets = profiles.map((P) => P.takeBuckets());
        if (!acc) { changedLines(this.run.memory, this.base, this.pfb); return; }
        const W = this.w, stored = buckets[0];
        for (let i = 0; i < stored.length; i++) stored[i] += buckets[1][i];
        logs.forEach((log, m) => log.forEach((e) => this.logged(profiles[m], e, stored)));
        const changed = diffBuckets(this.vram, this.snap);
        W.frames++;
        W.stored += stored.reduce((a, b) => a + b, 0); W.changed += changed.reduce((a, b) => a + b, 0);
        W.lines += changedLines(this.run.memory, this.base, this.pfb);
        for (const pl of planes(this.run, this.base)) this.plane(pl, stored, changed);
        for (const b of this.run.hw.blitLog) this.blit(profiles, b);
    }

    // a logged fill/copy: its VRAM bytes, how many it left as they were, a big clear's fate
    logged(P, e, stored) {
        const lo = Math.max(e.dest - this.run.vlo, 0), hi = Math.min(e.dest - this.run.vlo + e.len, VRAM_BYTES);
        if (hi > lo) {
            let same = 0;
            for (let i = lo; i < hi; i++) same += e.copy ? this.vram[i] === this.snap[i] : this.snap[i] === (e.x & 0xff);
            for (let i = lo; i < hi; i += 1 << BUCKET_SHIFT) stored[i >> BUCKET_SHIFT] += Math.min(hi - i, 1 << BUCKET_SHIFT);
            const k = `${P.tag}:${e.copy ? "c" : "f"}${e.site}`;
            const f = this.w.fills.get(k) ?? { mod: P.tag, copy: e.copy, site: e.site, bytes: 0, same: 0 };
            f.bytes += hi - lo; f.same += same;
            this.w.fills.set(k, f);
        }
        if (!e.copy && e.len >= CLEAR_MIN) this.clear(P, e, lo, hi);
    }

    clear(P, e, lo, hi) {
        const mem = new Uint8Array(this.run.memory.buffer);
        let left = 0, restored = 0;
        for (let i = e.dest; i < e.dest + e.len; i++) left += mem[i] === (e.x & 0xff);
        for (let i = lo; i < hi; i++) restored += this.vram[i] === this.snap[i];
        const k = `${P.tag}:${e.site}:${e.dest}`;
        const c = this.w.clears.get(k) ?? { mod: P.tag, site: e.site, len: e.len, frames: 0, overwritten: 0, restored: 0 };
        c.frames++; c.overwritten += 1 - left / e.len; c.restored += restored;
        this.w.clears.set(k, c);
    }

    plane(pl, stored, changed) {
        const W = this.w, len = pl.stride * pl.rows;
        const s = W.planes.get(pl.p) ?? { ...pl, frames: 0, stored: 0, changed: 0, staticFrames: 0, streak: 0, maxStreak: 0 };
        const ch = sumBuckets(changed, pl.off, len);
        s.frames++; s.stored += sumBuckets(stored, pl.off, len); s.changed += ch;
        s.streak = ch ? 0 : s.streak + 1; s.maxStreak = Math.max(s.maxStreak, s.streak); s.staticFrames += ch ? 0 : 1;
        W.planes.set(pl.p, s);
        const rows = shiftedRows(this.vram, this.snap, pl);
        const sc = W.scroll.get(pl.p) ?? { p: pl.p, width: pl.width, frames: 0, rows: 0, stored: 0, k: new Map() };
        if (rows.length) {
            sc.frames++; sc.rows += rows.length;
            const touched = new Set(); // the buckets the shifted rows sit in: CPU bytes stored there
            for (const r of rows) {
                const o = pl.off + r.y * pl.stride;
                for (let i = o >> BUCKET_SHIFT; i <= (o + pl.width - 1) >> BUCKET_SHIFT; i++) touched.add(i);
                sc.k.set(r.k, (sc.k.get(r.k) ?? 0) + 1);
            }
            for (const i of touched) sc.stored += stored[i];
        }
        W.scroll.set(pl.p, sc);
    }

    blit(profiles, b) {
        const P = profiles[b.mod], k = `${P?.tag ?? "?"}:${b.site}`;
        const s = this.w.blits.get(k) ?? { mod: P?.tag ?? "?", site: b.site, fi: P?.plan.blits[b.site]?.fi ?? -1, ops: 0, tiny: 0, bytes: 0, tinyBytes: 0, inplane: 0, inplaneExtra: 0 };
        s.ops++; s.bytes += b.bytes;
        if (b.inplane) { s.inplane++; s.inplaneExtra += b.extra; }
        if (b.bytes < TINY_BLIT) { s.tiny++; s.tinyBytes += b.bytes; }
        this.w.blits.set(k, s);
    }
}
