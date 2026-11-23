// The .vgm player (libs/zig/players/vgm.zig) and its engine (our YM2612 + SN76489, libs/c/vgm) on the real
// audio modules (docs/machine-audio.wasm + docs/demo-audio.wasm: the page's build):
//   parity    the engine in machine-audio.wasm renders each tune to the same samples, 0.1 s block for
//             block, as the same C built natively (fpga/tools/vgm_render.c: what BARD runs, host/audio_vgm.c):
//             KESTREL FM (.vgm and .vgz), the single-feature VGMs (libs/c/vgm/test_vgms.py), local tunes when
//             prototypes/gens_fm/dl/s1/x/ holds them (never committed)
//   pinned    the native render of each feature VGM hashes as apps/harness/vgm_expected.json says (our core's own
//             output, pinned: a change to the chips' behaviour shows here and must be re-pinned on purpose)
//   player    the player's output, a side, is the engine's stereo resampled to 44.1 kHz (mp3_resample.zig's
//             linear, in integers) and >> 1 (the hi/lo Paula path), sample for sample; mode 1 while it plays;
//             and that stage (libs/c/vgm/zm_vgm_out.c) in machine-audio.wasm = natively, its four byte streams
//             block for block
//   hangs     a loop that waits nothing and a DAC stream at a wild rate end / render in bounded time
//   refused   garbage, a header with no chip, a truncated file, a corrupt .vgz and one too big for the song RAM
//   node apps/harness/vgm_check.mjs [--break envelope|lfo|feedback|dac|noise] [--pin]
//     each break mutates the native build's C (one feature's rule) and must fail that feature's pinned hash
import { readFile, mkdtemp, writeFile, readdir, mkdir, cp } from "node:fs/promises";
import { execFileSync } from "node:child_process";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { gzipSync } from "node:zlib";

const TUNE = "docs/music/kestrel_fm.vgm", TUNE_Z = "docs/music/kestrel_fm.vgz", SECS = 6, OUT = 735;
const LOCAL = process.env.VGM_LOCAL || "prototypes/gens_fm/dl/s1/x"; // Sonic 1's VGMs, the Gens study's local set
const PIN = "apps/harness/vgm_expected.json";
const SRC = ["vgm/zm_vgm.c", "vgm/vgm_seq.c", "vgm/vgm_stream.c", "vgm/zm_inflate.c", "vgm/zm_vgm_out.c", "ym2612/ym2612.c",
    "ym2612/ym2612_eg.c", "ym2612/ym2612_render.c", "sn76489/sn76489.c"];
// --break <feature>: [file, the rule, its mutant, the feature VGM whose pinned hash must then fail]
const BREAKS = {
    envelope: ["ym2612/ym2612_eg.c", "(~o->att * inc) >> 4;", "(~o->att * inc) >> 3;", "envelope"],
    lfo: ["ym2612/ym2612_render.c", "(int32_t)YM_PM_DEPTH[c->pms] * pm_step", "(int32_t)YM_PM_DEPTH[c->pms] / 2 * pm_step", "lfo"],
    feedback: ["ym2612/ym2612_render.c", ">> (10 - c->fb)", ">> (11 - c->fb)", "feedback"],
    dac: ["ym2612/ym2612.c", "- 128) * 64;", "- 128) * 32;", "dac"],
    noise: ["sn76489/sn76489.c", "(lfsr ^ lfsr >> 3) & 1u", "(lfsr ^ lfsr >> 2) & 1u", "psg"],
};
const bi = process.argv.indexOf("--break");
const broke = bi > 0 ? process.argv[bi + 1] : null;
if (bi > 0 && !BREAKS[broke]) throw new Error(`--break ${Object.keys(BREAKS).join(" | ")}`);
const pin = process.argv.includes("--pin");

async function modules() {
    const memory = new WebAssembly.Memory({ initial: 48, maximum: 48 });
    const m = (await WebAssembly.instantiate(await readFile("docs/machine-audio.wasm"), { env: { memory } })).instance.exports;
    const env = { memory };
    for (const n of Object.keys(m)) if (n.startsWith("machine")) env[n] = m[n];
    const a = (await WebAssembly.instantiate(await readFile("docs/demo-audio.wasm"), { env })).instance.exports;
    a.audioInit();
    return { memory, m, a };
}

function fnv(pcm) {
    let h = 2166136261;
    for (const v of pcm) h = Math.imul(h ^ (v & 0xffff), 16777619) >>> 0;
    return h.toString(16).padStart(8, "0");
}

/** The native build of libs/c (a --break mutating one rule in a copy), with the host's C compiler. */
async function nativeRenderer(dir) {
    await cp("libs/c", `${dir}/c`, { recursive: true });
    if (broke) {
        const [file, from, to] = BREAKS[broke];
        const text = await readFile(`${dir}/c/${file}`, "utf8");
        if (!text.includes(from)) throw new Error(`--break ${broke}: "${from}" is not in ${file}`);
        await writeFile(`${dir}/c/${file}`, text.replace(from, to));
    }
    execFileSync("cc", ["-std=c99", "-O2", "-Wall", "-Werror", "-o", `${dir}/vgm_render`, "fpga/tools/vgm_render.c",
        ...SRC.map((s) => `${dir}/c/${s}`), `-I${dir}/c/vgm`]);
    const run = (file, ...args) => execFileSync(`${dir}/vgm_render`, [file, String(SECS), ...args], { encoding: "utf8", timeout: 60000 });
    const render = (file) => run(file).split("\n").filter((l) => l.startsWith("H ")).map((l) => l.split(" ")[2]);
    render.paula = (file) => run(file, "-p").split("\n").filter((l) => l.startsWith("P ")).map((l) => l.split(" ")[2]);
    return render;
}

/** The output stage in machine-audio.wasm: 0.1 s blocks of 4410 frames, the four byte streams hashed as vgm_render -p does. */
async function wasmPaula(bytes) {
    const { memory, m, a } = await modules();
    const at = a.audioSongPtr(), ch = [0, 1, 2, 3].map((c) => at + 0xF0000 + c * 4410);
    new Uint8Array(memory.buffer, at, bytes.length).set(bytes);
    m.machineVgmLoad(at, bytes.length, 0xF0000);
    const hashes = [];
    for (let b = 0; b < SECS * 10; b++) {
        m.machineVgmRenderPaula(ch[0], ch[1], ch[2], ch[3], 4410);
        let h = 2166136261;
        for (const c of ch) for (const v of new Uint8Array(memory.buffer, c, 4410)) h = Math.imul(h ^ v, 16777619) >>> 0;
        hashes.push(h.toString(16).padStart(8, "0"));
    }
    return hashes;
}

async function stage(native, errors, notes) {
    for (const file of [TUNE, TUNE_Z]) {
        const w = await wasmPaula(new Uint8Array(await readFile(file))), n = native.paula(file);
        const bad = w.findIndex((h, i) => h !== n[i]);
        if (n.length !== w.length || bad >= 0) errors.push(`stage: ${file}: the Paula bytes differ from block ${bad} (wasm ${w[bad]}, native ${n[bad]})`);
    }
    notes.push(`stage: the output stage's four byte streams, ${SECS} s of KESTREL FM (.vgm, .vgz): wasm = native`);
}

/** A file that would spin: the render must come back, then stay silent (a dead loop) or play (a clamped stream). */
async function hangs(errors, notes) {
    const dead = header(7670453, 0);
    new DataView(dead.buffer).setUint32(0x1c, 0x40 - 0x1c, true); // the loop at the 0x66 itself
    const st = header(7670453, 0, 0x40);
    const cmds = [0x67, 0x66, 0x00, 4, 0, 0, 0, 0x10, 0xf0, 0x10, 0xf0, 0x52, 0x2b, 0x80, 0x90, 0, 2, 0, 0x2a,
        0x91, 0, 0, 1, 0, 0x92, 0, 0xff, 0xff, 0xff, 0xff, 0x95, 0, 0, 0, 1, 0x61, 0x44, 0xac, 0x66];
    const stream = new Uint8Array(0x40 + cmds.length);
    stream.set(st.subarray(0, 0x40)), stream.set(cmds, 0x40);
    new DataView(stream.buffer).setUint32(4, stream.length - 4, true);
    for (const [what, bytes] of [["a loop that waits nothing", dead], ["a stream at 4 GHz", stream]]) {
        const t0 = Date.now(), w = await wasmRender(bytes, 2), ms = Date.now() - t0;
        if (w.st !== 0 || ms > 20000) errors.push(`hangs: ${what}: status ${w.st}, ${ms} ms for 2 s`);
    }
    notes.push("hangs: a loop that waits nothing ends, a stream at a wild rate is clamped: both render in bounded time");
}

/** The engine in machine-audio.wasm: the same blocks' hashes (0.1 s of stereo frames each), and the samples. */
async function wasmRender(bytes, secs = SECS) {
    const { memory, m, a } = await modules();
    const at = a.audioSongPtr(), cap = 0xF0000, dst = at + cap; // the player's room (vgm.zig FILE_MAX), the chunk past it
    new Uint8Array(memory.buffer, at, bytes.length).set(bytes);
    const st = m.machineVgmLoad(at, bytes.length, cap), rate = m.machineVgmRate(), block = Math.floor(rate / 10);
    const hashes = [], all = [];
    for (let b = 0, done = 0, total = Math.floor(secs * rate); done < total; b++) {
        const k = Math.min(block, total - done);
        m.machineVgmRender(dst, k);
        const blk = new Int16Array(memory.buffer, dst, 2 * k).slice();
        hashes.push(fnv(blk));
        for (const v of blk) all.push(v);
        done += k;
    }
    return { st, rate, hashes, all };
}

async function tunes(dir) {
    execFileSync("python3", ["libs/c/vgm/test_vgms.py", `${dir}/t`]);
    const list = [[TUNE, "kestrel_fm.vgm"], [TUNE_Z, "kestrel_fm.vgz"]];
    for (const f of (await readdir(`${dir}/t`)).sort()) list.push([`${dir}/t/${f}`, f]);
    const local = (await readdir(LOCAL).catch(() => [])).filter((f) => f.endsWith(".vgm")).sort();
    for (const f of local) list.push([`${LOCAL}/${f}`, `local ${f}`]);
    return { list, local: local.length };
}

async function parity(native, list, nlocal, errors, notes) {
    for (const [file, name] of list) {
        const bytes = new Uint8Array(await readFile(file));
        if (bytes.length > 0xF0000) { notes.push(`parity: ${name}: ${bytes.length} bytes, past the song RAM's room, skipped`); continue; }
        const w = await wasmRender(bytes), n = native(file);
        const bad = w.hashes.findIndex((h, i) => h !== n[i]);
        if (w.st !== 0) errors.push(`parity: ${name}: the engine refused it (${w.st})`);
        else if (n.length !== w.hashes.length) errors.push(`parity: ${name}: native ${n.length} blocks, wasm ${w.hashes.length}`);
        else if (bad >= 0) errors.push(`parity: ${name} differs from block ${bad} (wasm ${w.hashes[bad]}, native ${n[bad]})`);
    }
    notes.push(`parity: ${list.length} tunes x ${SECS} s at the engine's rate: wasm = native${nlocal ? ` (${nlocal} local)` : " (no local tunes)"}`);
}

async function pinned(native, list, errors, notes) {
    const want = JSON.parse(await readFile(PIN, "utf8").catch(() => "{}"));
    const got = {};
    for (const [file, name] of list.filter(([, n]) => !n.startsWith("local "))) {
        got[name] = fnv(native(file).map((h) => parseInt(h, 16)));
        if (!pin && want[name] !== got[name]) errors.push(`pinned: ${name} hashes ${got[name]}, ${PIN} says ${want[name]}`);
    }
    if (pin) await writeFile(PIN, JSON.stringify(got, null, 1) + "\n");
    notes.push(pin ? `pinned: wrote ${PIN}` : `pinned: ${Object.keys(got).length} tunes as ${PIN}`);
}

/** mp3_resample.zig's Linear, then mp3_out's x >> 1 (held at its top), per side. */
function expected(src, rate, n) {
    const RECIP = 48696, Y_MAX = 127 * 128 + 63, out = [];
    let at = 0, pos = 0, a = [0, 0], b = [0, 0];
    const push = () => { a = b; b = [src[2 * at], src[2 * at + 1]]; at++; };
    push(), push();
    while (out.length < n) {
        const w = Math.min(Math.floor((pos * RECIP) / 65536), 32767);
        out.push([0, 1].map((s) => Math.min((a[s] + (((b[s] - a[s]) * w) >> 15)) >> 1, Y_MAX)));
        pos += rate;
        while (pos >= 44100) pos -= 44100, push();
    }
    return out;
}

async function player(errors, notes) {
    const { memory, m, a } = await modules();
    const bytes = new Uint8Array(await readFile(TUNE));
    new Uint8Array(memory.buffer, a.audioSongPtr(), bytes.length).set(bytes);
    if (!a.audioLoadVgm(bytes.length)) errors.push(`player: kestrel_fm.vgm refused (status ${a.audioVgmStatus()})`);
    const L = [], R = [];
    for (let f = 0; f < 120; f++) {
        a.audioRender(OUT);
        const l = new Float32Array(memory.buffer, m.audioLeftPtr(), OUT), r = new Float32Array(memory.buffer, m.audioRightPtr(), OUT);
        for (let i = 0; i < OUT; i++) L.push(Math.round(l[i] * 32768)), R.push(Math.round(r[i] * 32768));
    }
    const mode = a.audioMode(), status = a.audioVgmStatus();
    const e = await wasmRender(bytes, L.length / 44100 + 0.1);
    const ref = expected(e.all, e.rate, L.length);
    const bad = L.findIndex((v, i) => v !== ref[i][0] || R[i] !== ref[i][1]);
    if (bad >= 0) errors.push(`player: output differs at sample ${bad} (L ${L[bad]} R ${R[bad]}, want ${ref[bad]})`);
    if (L.every((v) => v === 0) || R.every((v) => v === 0)) errors.push("player: a side is silent");
    if (mode !== 1 || status !== 1) errors.push(`player: mode ${mode}, status ${status}`);
    notes.push(`player: kestrel_fm.vgm ${L.length} frames = the engine at ${e.rate} Hz resampled >> 1, both sides heard, mode ${mode}`);
}

function header(ym, psg, data = 0x40) {
    const h = new Uint8Array(0x100), v = new DataView(h.buffer);
    h.set([0x56, 0x67, 0x6d, 0x20]);
    v.setUint32(4, 0xfc, true), v.setUint32(8, 0x150, true), v.setUint32(0x0c, psg, true), v.setUint32(0x2c, ym, true);
    v.setUint32(0x34, data - 0x34, true), h[0x40] = 0x66;
    return h;
}

async function refused(errors, notes) {
    const tune = new Uint8Array(await readFile(TUNE));
    const badz = gzipSync(tune).slice(), big = new Uint8Array(0xF0001);
    badz.fill(0xAB, 20, 60); // a corrupt deflate stream
    big.set(tune);
    const cases = [["garbage", new Uint8Array(400).fill(7), 1], ["no chip", header(0, 0), 2],
        ["data past its end", header(7670453, 0, 0x2000), 3], ["a corrupt .vgz", badz, 4], ["too big", big, 5]];
    for (const [what, bytes, want] of cases) {
        const { memory, m, a } = await modules();
        new Uint8Array(memory.buffer, a.audioSongPtr(), bytes.length).set(bytes);
        const ok = a.audioLoadVgm(bytes.length);
        a.audioRender(OUT);
        const heard = new Float32Array(memory.buffer, m.audioLeftPtr(), OUT).some((v) => v !== 0);
        const st = (a.audioVgmStatus() >> 8) & 0xff;
        if (ok || st !== want || heard || a.audioMode() !== 0) errors.push(`refused: ${what} loaded ${ok}, status ${st} (want ${want}), heard ${heard}`);
    }
    notes.push(`refused: ${cases.map(([w, , s]) => `${w} (${s})`).join(", ")}: silent, mode 0`);
}

const errors = [], notes = [];
const dir = await mkdtemp(join(tmpdir(), "vgm_check-"));
await mkdir(`${dir}/t`);
const native = await nativeRenderer(dir);
const { list, local } = await tunes(dir);
if (!broke) await parity(native, list, local, errors, notes);
await pinned(native, list, errors, notes);
if (!broke) await player(errors, notes);
if (!broke) await refused(errors, notes);
if (!broke) await stage(native, errors, notes);
if (!broke) await hangs(errors, notes);
for (const n of notes) console.log(`  ${n}`);
// exitCode, never process.exit() (see apps/harness/mod_sfx_check.mjs: node 24 deadlocks at exit).
if (broke) {
    const want = `pinned: ${BREAKS[broke][3]}.vgm`;
    const hit = errors.find((e) => e.startsWith(want));
    console.log(hit ? `vgm_check: PASS (--break ${broke} caught: ${hit})` : `vgm_check: FAILED -- --break ${broke} not caught (${errors.length} other errors)`);
    process.exitCode = hit ? 0 : 1;
} else {
    console.log(errors.length ? `vgm_check: FAILED -- ${errors.join("; ")}` : "vgm_check: all pass");
    process.exitCode = errors.length ? 1 : 0;
}
