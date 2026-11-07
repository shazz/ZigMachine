// The .sid player (libs/zig/players/sid.zig) and its engine (cRSID, libs/c/crsid) on the real audio
// modules (docs/machine-audio.wasm + docs/demo-audio.wasm: the page's build):
//   parity    the engine in machine-audio.wasm renders hermini.sid's first 10 s to the same samples,
//             0.1 s block for block, as the same C built natively (fpga/tools/sid_render.c on
//             libs/c/crsid/patch.sh's tree: what BARD runs, host/crsid.c). Local study tunes too, when
//             prototypes/sid_re/tunes/ holds them (never committed).
//   player    the player's output, a side, is the engine's 22.05 kHz upsampled (every other sample the
//             midpoint) and >> 1 (the hi/lo Paula path), sample for sample; mode 1 while it plays
//   refused   an RSID (a C64 program) is refused with status 2, garbage with 1; the player stays silent
//   node apps/sid_check.mjs [--break seed|rsid]
//     seed: the native build's dither LFSR seeded one off must fail parity;
//     rsid: an RSID let through as a PSID (its magic rewritten by the harness) must fail refused
import { readFile, mkdtemp, writeFile, readdir } from "node:fs/promises";
import { execFileSync } from "node:child_process";
import { tmpdir } from "node:os";
import { join } from "node:path";

const TUNE = "docs/music/hermini.sid", BLOCK = 2205, BLOCKS = 100, OUT = 735;
const LOCAL = "prototypes/sid_re/tunes"; // the study's HVSC tunes, local only
const BREAKS = ["seed", "rsid"];
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

function fnv(pcm) {
    let h = 2166136261;
    for (const v of pcm) h = Math.imul(h ^ (v & 0xffff), 16777619) >>> 0;
    return h.toString(16).padStart(8, "0");
}

/** The native build: patch.sh's tree + zm_sid.c + sid_render.c, with the host's C compiler. */
async function nativeRenderer() {
    const dir = await mkdtemp(join(tmpdir(), "sid_check-"));
    execFileSync("sh", ["libs/c/crsid/patch.sh", `${dir}/tree`]);
    let glue = await readFile("libs/c/crsid/zm_sid.c", "utf8");
    if (broke === "seed") glue = glue.replace("zm_crsid_lfsr = 0x0055A5AA;", "zm_crsid_lfsr = 0x0055A5AB;");
    await writeFile(`${dir}/zm_sid.c`, glue);
    execFileSync("cc", ["-std=gnu99", "-O2", "-w", `-I${dir}/tree`, "-Ilibs/c/crsid", "-o", `${dir}/sid_render`,
        "fpga/tools/sid_render.c", `${dir}/zm_sid.c`]);
    return (file, sub) => execFileSync(`${dir}/sid_render`, [String(BLOCKS), file, String(sub)], { encoding: "utf8" })
        .split("\n").filter((l) => l.startsWith("H ")).map((l) => l.split(" ")[2]);
}

/** The engine in machine-audio.wasm: the same blocks' hashes, and the samples. */
async function wasmRender(file, sub, n = BLOCKS) {
    const { memory, m, a } = await modules();
    const bytes = new Uint8Array(await readFile(file));
    const at = a.audioSongPtr(), dst = at + 0x20000;
    new Uint8Array(memory.buffer, at, bytes.length).set(bytes);
    const st = m.machineSidLoad(at, bytes.length, sub);
    const hashes = [], all = [];
    for (let b = 0; b < n; b++) {
        m.machineSidRender(dst, BLOCK);
        const blk = new Int16Array(memory.buffer, dst, BLOCK).slice();
        hashes.push(fnv(blk));
        all.push(...blk);
    }
    return { st, hashes, all };
}

async function parity(native, errors, notes) {
    const tunes = [[TUNE, 0]];
    const local = await readdir(LOCAL).catch(() => []);
    for (const f of local.filter((f) => f.endsWith(".sid")).sort()) tunes.push([`${LOCAL}/${f}`, 0]);
    let psid = 0;
    for (const [file, sub] of tunes) {
        const w = await wasmRender(file, sub), n = native(file, sub);
        const bad = w.hashes.findIndex((h, i) => h !== n[i]);
        if (n.length !== BLOCKS) errors.push(`parity: ${file}: the native build rendered ${n.length} blocks`);
        else if (bad >= 0) errors.push(`parity: ${file} differs from block ${bad} (wasm ${w.hashes[bad]}, native ${n[bad]})`);
        if (w.st === 0) psid++;
    }
    notes.push(`parity: ${tunes.length} tune(s) (${psid} PSID played, the rest refused), ${BLOCKS} x ${BLOCK} samples each: wasm = native${local.length ? "" : " (no local study tunes)"}`);
}

/** The player's 44.1 kHz output from the engine's 22.05: a midpoint between each pair, then >> 1. */
function expected(src, n) {
    const out = [];
    for (let i = 0; out.length < n; i++) {
        const a = src[i], b = src[i + 1];
        out.push(a >> 1, (a + (((b - a) * 16384) >> 15)) >> 1);
    }
    return out.slice(0, n);
}

async function player(errors, notes) {
    const { memory, m, a } = await modules();
    const bytes = new Uint8Array(await readFile(TUNE));
    new Uint8Array(memory.buffer, a.audioSongPtr(), bytes.length).set(bytes);
    if (!a.audioLoadSid(bytes.length, 0)) errors.push(`player: hermini.sid refused (status ${a.audioSidStatus()})`);
    const L = [], R = [];
    for (let b = 0; b < 60; b++) {
        a.audioRender(OUT);
        const l = new Float32Array(memory.buffer, m.audioLeftPtr(), OUT), r = new Float32Array(memory.buffer, m.audioRightPtr(), OUT);
        for (let i = 0; i < OUT; i++) { L.push(Math.round(l[i] * 32768)); R.push(Math.round(r[i] * 32768)); }
    }
    const mode = a.audioMode(), status = a.audioSidStatus();
    const ref = expected((await wasmRender(TUNE, 0, Math.ceil(L.length / 2 / BLOCK) + 1)).all, L.length);
    const bad = L.findIndex((v, i) => v !== ref[i] || R[i] !== ref[i]);
    if (bad >= 0) errors.push(`player: output differs at sample ${bad} (L ${L[bad]} R ${R[bad]}, want ${ref[bad]})`);
    if (L.every((v) => v === 0)) errors.push("player: silent");
    if (mode !== 1 || status !== 1) errors.push(`player: mode ${mode}, status ${status}`);
    notes.push(`player: hermini.sid ${L.length} samples a side = the engine upsampled >> 1, mode ${mode}, heard`);
}

async function refused(errors, notes) {
    const file = new Uint8Array(await readFile(TUNE));
    const rsid = file.slice();
    rsid[0] = "R".charCodeAt(0);
    if (broke === "rsid") rsid[0] = "P".charCodeAt(0); // the mutant: the RSID reaches the engine as a PSID
    for (const [what, bytes, want] of [["an RSID", rsid, 2], ["garbage", new Uint8Array(400).fill(7), 1]]) {
        const { memory, m, a } = await modules();
        new Uint8Array(memory.buffer, a.audioSongPtr(), bytes.length).set(bytes);
        const ok = a.audioLoadSid(bytes.length, 0);
        a.audioRender(OUT);
        const heard = new Float32Array(memory.buffer, m.audioLeftPtr(), OUT).some((v) => v !== 0);
        const st = (a.audioSidStatus() >> 8) & 0xff;
        if (ok || st !== want || heard || a.audioMode() !== 0) errors.push(`refused: ${what} loaded ${ok}, status ${st} (want ${want}), heard ${heard}`);
    }
    notes.push("refused: an RSID (status 2, 'RSID not supported') and garbage (1), silent, mode 0");
}

const errors = [], notes = [];
await parity(await nativeRenderer(), errors, notes);
await player(errors, notes);
await refused(errors, notes);
for (const n of notes) console.log(`  ${n}`);
// exitCode, never process.exit() (see apps/mod_sfx_check.mjs: node 24 deadlocks at exit).
if (broke) {
    const want = { seed: "parity:", rsid: "refused:" }[broke];
    const hit = errors.find((e) => e.startsWith(want));
    console.log(hit ? `sid_check: PASS (--break ${broke} caught: ${hit})` : `sid_check: FAILED -- --break ${broke} not caught (${errors.length} other errors)`);
    process.exitCode = hit ? 0 : 1;
} else {
    console.log(errors.length ? `sid_check: FAILED -- ${errors.join("; ")}` : "sid_check: all pass");
    process.exitCode = errors.length ? 1 : 0;
}
