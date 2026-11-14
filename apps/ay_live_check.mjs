// The BARD queue's AY device (libs/c/ayumi zm_ay_bank.h; libs/zig/players/ay_live.zig plays it, sid_live.zig picks it):
//   parity   machine-audio.wasm's AY engine = the same C built natively (fpga/tools/ay_render.c, what BARD runs): a script
//            of random writes to three chips (configure, pans, gains, every register, envelope re-triggers, a reconfigure)
//            at random samples, 0.1 s block for block, both sides
//   player   demo-audio.wasm's BARD queue (audioBardOpen, the stage, audioBardQueue: what the loader and BARD's pump do)
//            playing the same writes stamped with their samples, a frame's worth before each frame: each side is the
//            engine's own output, the writes at their stamp + the lead, >> 1 (the hi/lo Paula path, which holds the
//            top 64 values at 16319: mp3_out.zig), sample for sample;
//            every write applied, none refused, dropped or re-anchored; heard
//   refused  a register of a chip never configured, and a SID reset and write on the AY open: refused and counted, silent
//   node apps/ay_live_check.mjs [--break drop|late]
//     drop: one write of the script is never staged (a write lost on the way); late: every write but the first (which
//     anchors the two clocks) staged a sample late:
//     both fail `player`
import { execFileSync } from "node:child_process";
import { mkdtemp, readFile, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";

const AY = 0xa000, FRAME = 735, LEAD = 2048, BLOCK = 4410, SECONDS = 4, FRAMES = Math.ceil(SECONDS * 44100 / FRAME);
const BREAKS = ["drop", "late"];
const bi = process.argv.indexOf("--break");
const broke = bi > 0 ? process.argv[bi + 1] : null;
if (bi > 0 && !BREAKS.includes(broke)) throw new Error(`--break ${BREAKS.join(" | ")}`);

async function modules() {
    const memory = new WebAssembly.Memory({ initial: 48, maximum: 48 });
    const m = (await WebAssembly.instantiate(await readFile("docs/machine-audio.wasm"), { env: { memory } })).instance.exports;
    const env = { memory };
    for (const n of Object.keys(m)) if (n.startsWith("machine")) env[n] = m[n];
    const a = (await WebAssembly.instantiate(await readFile("docs/demo-audio.wasm"), { env })).instance.exports;
    a.audioInit();
    return { memory, m, a };
}

/** The writes [t, offset, value], t ascending: three chips set up at 0, then ~40 writes a frame. */
function script() {
    let s = 1;
    const rnd = (n) => { s = (Math.imul(s, 1103515245) + 12345) >>> 0; return (s >>> 8) % n; };
    const w = [[0, 0x0e, 1773400], [0, 0x0f, 30 | 100 << 8 | 170 << 16 | 1 << 24], [0, 0x1e, 2000000 | 1 << 24],
        [0, 0x1f, 100 | 100 << 8 | 100 << 16 | 1 << 24], [0, 0x2e, 1750000], [0, 0x2f, 0 | 100 << 8 | 200 << 16],
        [0, 0x80, 19661], [0, 0x81, 19661], [0, 0x82, 16384]]; // ChipNomad's 0.6 a chip, and a half
    const val = [256, 16, 256, 16, 256, 16, 32, 64, 32, 32, 32, 256, 8, 16];
    for (let t = 1; t < SECONDS * 44100; t += 1 + rnd(36)) {
        const chip = rnd(3), reg = rnd(14);
        w.push([t, chip * 16 + reg, rnd(val[reg])]);
        if (rnd(3000) === 0) w.push([t, chip * 16 + 0x0f, rnd(201) | rnd(201) << 8 | rnd(201) << 16 | rnd(2) << 24]);
        if (rnd(20000) === 0) w.push([t, chip * 16 + 0x0e, 1000000 + rnd(1000000) | rnd(2) << 24]);
    }
    return w;
}

/** The engine on its own (machine-audio.wasm): each write before the sample `t + shift`; L and R, and 0.1 s hashes. */
async function engine(w, shift, frames) {
    const { memory, m, a } = await modules();
    const dst = a.audioSongPtr() + 0x20000, L = new Int16Array(frames), R = new Int16Array(frames), hashes = [];
    m.machineAyReset();
    let at = 0;
    for (let t = 0; t < frames;) {
        while (at < w.length && w[at][0] + shift <= t) { m.machineAyWrite(w[at][1], w[at][2]); at++; }
        const end = Math.min(frames, at < w.length ? w[at][0] + shift : frames, (Math.floor(t / BLOCK) + 1) * BLOCK);
        m.machineAyRender(dst, end - t);
        const p = new Int16Array(memory.buffer, dst, 2 * (end - t));
        for (let i = 0; i < end - t; i++) { L[t + i] = p[2 * i]; R[t + i] = p[2 * i + 1]; }
        t = end;
    }
    for (let b = 0; b * BLOCK < frames; b++) {
        let h = 2166136261;
        for (let i = b * BLOCK; i < Math.min(frames, (b + 1) * BLOCK); i++) for (const v of [L[i], R[i]]) h = Math.imul(h ^ (v & 0xffff), 16777619) >>> 0;
        hashes.push(h.toString(16).padStart(8, "0"));
    }
    return { L, R, hashes };
}

async function parity(w, errors, notes) {
    const dir = await mkdtemp(join(tmpdir(), "ay_live_check-"));
    execFileSync("cc", ["-std=c99", "-O2", "-Wall", "-Werror", "-Ilibs/c/ayumi", "-o", `${dir}/ay_render`, "fpga/tools/ay_render.c",
        "libs/c/ayumi/zm_ay.c", "libs/c/ayumi/zm_ay_cfg.c", "libs/c/ayumi/zm_ay_bank.c"]);
    await writeFile(`${dir}/script.bin`, new Uint8Array(Uint32Array.from(w.flat()).buffer));
    const frames = SECONDS * 44100;
    const native = execFileSync(`${dir}/ay_render`, [`${dir}/script.bin`, String(frames)], { encoding: "utf8" })
        .split("\n").filter((l) => l.startsWith("H ")).map((l) => l.split(" ")[2]);
    const wasm = (await engine(w, 0, frames)).hashes;
    const bad = wasm.findIndex((h, i) => h !== native[i]);
    if (native.length !== wasm.length || bad >= 0) errors.push(`parity: block ${bad} of ${wasm.length} (wasm ${wasm[bad]}, native ${native[bad]})`);
    else notes.push(`parity: ${w.length} writes, ${wasm.length} x 0.1 s stereo blocks: machine-audio.wasm = the native C`);
}

/** The queue player: open, a frame's writes staged before each frame, 128-frame renders as the worklet does. */
async function queued(entries, frames) {
    const { memory, m, a } = await modules();
    a.audioBardOpen(LEAD);
    const L = new Int16Array(frames * FRAME), R = new Int16Array(frames * FRAME);
    let at = 0, done = 0;
    for (let f = 0; f < frames; f++) {
        const st = new Uint32Array(memory.buffer, a.audioBardStagePtr(), 4 * a.audioBardStageCap());
        let n = 0;
        for (; at < entries.length && entries[at][0] < (f + 1) * FRAME; at++, n++) st.set([entries[at][0], AY + entries[at][1], entries[at][2], 0], 4 * n);
        if (n) a.audioBardQueue(n);
        for (; done < (f + 1) * FRAME; done += 128) {
            a.audioRender(128);
            const l = new Float32Array(memory.buffer, m.audioLeftPtr(), 128), r = new Float32Array(memory.buffer, m.audioRightPtr(), 128);
            for (let i = 0; i < 128 && done + i < L.length; i++) { L[done + i] = Math.round(l[i] * 32768); R[done + i] = Math.round(r[i] * 32768); }
        }
    }
    const stats = { mode: a.audioMode(), applied: a.audioBardApplied(), refused: a.audioBardRefused(), dropped: a.audioBardDropped(), resyncs: a.audioBardResyncs() };
    return { L, R, stats };
}

async function player(w, errors, notes) {
    let staged = w.map((x) => x.slice());
    if (broke === "drop") staged.splice(Math.floor(staged.length / 2), 1);
    if (broke === "late") staged = staged.map(([t, o, v], i) => [i ? t + 1 : t, o, v]); // the first anchors the clocks
    const q = await queued(staged, FRAMES), ref = await engine(w, LEAD, FRAMES * FRAME);
    const rendered = Math.ceil(FRAMES * FRAME / 128) * 128, due = w.filter(([t]) => t + LEAD < rendered).length;
    const half = (x) => Math.min(x >> 1, 16319);
    const bad = q.L.findIndex((v, i) => v !== half(ref.L[i]) || q.R[i] !== half(ref.R[i]));
    if (bad >= 0) errors.push(`player: differs at sample ${bad} (L ${q.L[bad]} R ${q.R[bad]}, want ${half(ref.L[bad])} ${half(ref.R[bad])})`);
    const heard = q.L.some((v) => v !== 0) && q.R.some((v, i) => v !== q.L[i]), s = q.stats;
    if (!heard) errors.push("player: silent, or no stereo");
    if (!broke && (s.mode !== 1 || s.applied !== due || s.refused || s.dropped || s.resyncs)) errors.push(`player: ${JSON.stringify(s)} for ${due} writes due`);
    else notes.push(`player: ${FRAMES} frames (${(FRAMES * FRAME / 44100).toFixed(1)} s), each side = the engine >> 1 with the writes a lead (${LEAD}) late; ${s.applied} applied, none refused, dropped or re-anchored; stereo`);
}

async function refused(errors, notes) {
    const q = await queued([[0, 5 * 16 + 8, 15], [0, 0x0e, 1773400], [10, 0x08, 15], [20, 0x07, 0x3e]], 8);
    const { memory, a } = await modules();
    a.audioBardOpen(LEAD);
    const st = new Uint32Array(memory.buffer, a.audioBardStagePtr(), 16);
    st.set([0, AY + 0x0e, 1773400, 0, 1, 1, 6581, 0, 2, 0xd418, 15, 0, 3, AY + 0x08, 15, 0]);
    a.audioBardQueue(4);
    for (let i = 0; i < 40; i++) a.audioRender(128);
    const sid = { applied: a.audioBardApplied(), refused: a.audioBardRefused() };
    if (q.stats.refused !== 1 || q.stats.applied !== 3 || sid.refused !== 2 || sid.applied !== 2) errors.push(`refused: ${JSON.stringify(q.stats)}, SID on AY ${JSON.stringify(sid)}`);
    else notes.push("refused: a chip's register before its configure, a SID reset and write on an AY open: refused and counted");
}

const errors = [], notes = [], w = script();
if (!broke) await parity(w, errors, notes);
await player(w, errors, notes);
if (!broke) await refused(errors, notes);
for (const n of notes) console.log(`  ${n}`);
if (broke) {
    const hit = errors.find((e) => e.startsWith("player:"));
    console.log(hit ? `ay_live_check: PASS (--break ${broke} caught: ${hit})` : `ay_live_check: FAILED -- --break ${broke} not caught`);
    process.exitCode = hit ? 0 : 1;
} else {
    console.log(errors.length ? `ay_live_check: FAILED -- ${errors.join("; ")}` : "ay_live_check: all pass");
    process.exitCode = errors.length ? 1 : 0;
}
