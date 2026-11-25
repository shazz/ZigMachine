// The BARD queue's FM device (libs/c/vgm/zm_vgm_sfx.c + zm_vgm_own.c; players/fm_live.zig; zg.bard.fm; R82 M4):
//   parity   a scripted SFX sequence over KESTREL RACING's race tune (kr_race.vgm), engine + output stage: machine-audio.wasm
//            = the same C built natively (fpga/tools/vgm_render.c -s, what BARD runs), and the same samples whatever the size
//            of the render calls (128 / 735) and however early the writes come (600 / 2,000 samples): a write lands where its
//            stamp says, not where it arrived; the native render's hashes and counters pinned (PINS below)
//   stamp    a key-on lands at the engine frame its stamp maps to (2 + stamp x rate / 44,100): two stamps 4,000 samples
//            apart sound the same number of engine frames apart as their maps
//   order    two writes with one stamp apply in the order pushed (TL 127 then 0: heard; 0 then 127: silent)
//   tune     the tune's writes to channels the cart owns are kept aside: owning every channel silences KESTREL FM, giving
//            them back brings it back; owning FM 5-6 + PSG 3 + noise leaves kr_race (which never writes them) unchanged
//   latches  the tune and the cart each keep their own A4 latch and PSG latch: tune + effects = tune alone + effects alone,
//            sample for sample (within 2 of rounding), through the tune's own A4/A0 and PSG latch/data pairs (FM 5-6 and
//            tone 3; the noise's phase is not linear: sn76489_mix stops the counters while every channel is off)
//   refused  a write to a channel not owned, an unknown address, a PSG byte for a tone not owned; a full ring (512); a
//            device that is off: refused and counted
//   player   demo-audio.wasm's queue (audioBardOpen, stage, audioBardQueue): the first FM write gives the queue to the VGM
//            player, the room for a song shrinks below the queue's block, a tune loaded under it plays with the queue open,
//            each side = the reference stage (the writes at their stamp + the lead) sample for sample; the tune stop command
//            silences the tune and the effects play on; a SID write on the FM open refused
//   (the racer cart's wiring: racer_audio_check.mjs)
//   node apps/harness/fm_sfx_check.mjs [--break latch|own|late|order] [--print-pins]
//     latch / own: the native C mutated (the cart's A4 latch not swapped in / every channel owned): the pins or parity fail;
//     late / order: the player's writes staged 300 samples late / same-stamp pairs swapped: the player check fails
import { execFileSync } from "node:child_process";
import { cp, mkdtemp, readFile, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { FRAME, FULL, LEAD, OWN, SECS, TUNE, engine, fnv, modules, onset, patch, script, wasmStage } from "./fm_sfx_lib.mjs";

const SRC = ["vgm/zm_vgm.c", "vgm/zm_vgm_sfx.c", "vgm/zm_vgm_own.c", "vgm/vgm_seq.c", "vgm/vgm_stream.c", "vgm/zm_inflate.c",
    "vgm/zm_vgm_out.c", "ym2612/ym2612.c", "ym2612/ym2612_eg.c", "ym2612/ym2612_render.c", "sn76489/sn76489.c"];
const BREAKS = {
    latch: ["vgm/zm_vgm_sfx.c", "v->ym.latch_hi[port] = zs.hi[port];", ""],
    own: ["vgm/zm_vgm_sfx.c", "static int owns(uint32_t bit) { return bit < 12u && (zs.own >> bit & 1u); }", "static int owns(uint32_t bit) { return bit < 12u; }"],
    late: null, order: null,
};
const PINS = { hashes: "b227c3a5", stats: "applied 684 refused 18 late 0 pending 0 pushed 702" }; // --print-pins
const bi = process.argv.indexOf("--break"), broke = bi > 0 ? process.argv[bi + 1] : null;
if (bi > 0 && !(broke in BREAKS)) throw new Error(`--break ${Object.keys(BREAKS).join(" | ")}`);

async function nativeStage(dir, w, block, feed) {
    await writeFile(`${dir}/script.txt`, w.map((x) => x.join(" ")).join("\n"));
    const lines = execFileSync(`${dir}/vgm_render`, [TUNE, String(SECS), "-s", `${dir}/script.txt`, String(block), String(feed)], { encoding: "utf8" }).split("\n");
    return { hashes: lines.filter((l) => l.startsWith("P ")).map((l) => l.split(" ")[2]), stats: lines.find((l) => l.startsWith("SFX ")).slice(4) };
}

async function parity(errors, notes) {
    const dir = await mkdtemp(join(tmpdir(), "fm_sfx_check-"));
    await cp("libs/c", `${dir}/c`, { recursive: true });
    if (BREAKS[broke]) {
        const [file, from, to] = BREAKS[broke], text = await readFile(`${dir}/c/${file}`, "utf8");
        if (!text.includes(from)) throw new Error(`--break ${broke}: "${from}" is not in ${file}`);
        await writeFile(`${dir}/c/${file}`, text.replace(from, to));
    }
    execFileSync("cc", ["-std=c99", "-O2", "-Wall", "-Werror", "-o", `${dir}/vgm_render`, "fpga/tools/vgm_render.c", ...SRC.map((s) => `${dir}/c/${s}`), `-I${dir}/c/vgm`]);
    const w = script(), runs = [[128, 600], [735, 2000]];
    const nat = [], was = [];
    for (const [b, f] of runs) nat.push(await nativeStage(dir, w, b, f)), was.push(await wasmStage(w, b, f));
    const all = [...nat, ...was].map((r) => r.hashes.join(","));
    const same = all.every((h) => h === all[0]) && nat.every((r) => r.stats === nat[0].stats) && was.every((r) => r.stats === nat[0].stats);
    if (!same) errors.push(`parity: wasm / native / block sizes / arrival differ (${nat.map((r) => r.stats).join(" | ")} | ${was.map((r) => r.stats).join(" | ")})`);
    const sig = fnv(2166136261, Buffer.from(all[0])).toString(16).padStart(8, "0");
    if (process.argv.includes("--print-pins")) console.log(`PINS = { hashes: "${sig}", stats: "${nat[0].stats}" }`);
    if (sig !== PINS.hashes || nat[0].stats !== PINS.stats) errors.push(`parity: pins moved (hashes ${sig} want ${PINS.hashes}; ${nat[0].stats} want ${PINS.stats})`);
    if (same) notes.push(`parity: ${w.length} writes over ${SECS} s of kr_race: wasm = native, renders of 128 and 735 frames, writes 600 and 2,000 samples early: the same samples (${nat[0].stats}), pinned`);
}


async function stampAndOrder(errors, notes) {
    const key = (t) => [[0, 0x300, OWN], ...patch(2, 4, 127, 0), [t, 0x028, 0xf6]];
    const on = [];
    for (const s of [1000, 5000]) { const r = await engine(key(s), 8000); on.push(onset(r.pcm) - (2 + Math.floor(s * r.rate / 44100))); }
    if (on[0] < 0 || on[0] > 2 || on[0] !== on[1]) errors.push(`stamp: onsets minus their maps ${on}`);
    else notes.push(`stamp: a key-on at 1,000 and at 5,000 samples sounds ${on[0]} engine frame(s) after its map, both`);
    const tl = (a, b) => [[0, 0x300, OWN], ...patch(2, 4, 127, 0), [100, 0x14e, a], [100, 0x14e, b], [100, 0x028, 0xf6]];
    const loud = await engine(tl(127, 4), 4000), mute = await engine(tl(4, 127), 4000);
    if (onset(loud.pcm) < 0 || onset(mute.pcm) >= 0) errors.push("order: same-stamp writes not applied in order");
    else notes.push("order: TL 127 then 0 at one stamp is heard, 0 then 127 is silent");
}

async function tune(errors, notes) {
    const n = 3 * 26633, sq = (p, a, b) => { let e = 0; for (let i = 2 * a; i < 2 * b; i++) e += p[i] * p[i]; return e; };
    const mute = await engine([[0, 0x300, 0x0f3f], [2 * 44100, 0x300, 0]], n, FULL);
    const lastHalf = sq(mute.pcm, 26633, 2 * 26633), back = sq(mute.pcm, 2 * 26633 + 2000, n);
    const plain = await engine([], n, TUNE), owned = await engine([[0, 0x300, OWN]], n, TUNE);
    // KESTREL FM plays drums on the DAC (FM 6's): taking FM 6 switches the DAC off, so the cart's FM 6 is heard as
    // loud as with no tune at all (every channel owned: the tune silent by 1 s).
    const dacW = [[0, 0x300, 0x0f3f], ...patch(2, 4, 28, 0), [0, 0x1a6, 3 << 3 | 2], [0, 0x1a2, 0x58], [0, 0x028, 0xf6]];
    const overDac = sq((await engine(dacW, n, FULL)).pcm, 26633, n), alone = sq((await engine(dacW, n)).pcm, 26633, n);
    if (Math.abs(overDac / alone - 1) > 0.1) errors.push(`tune: the cart's FM 6 over a DAC tune at ${(overDac / alone).toFixed(2)} of its level alone`);
    else notes.push(`tune: the cart's FM 6 over KESTREL FM's DAC drums = ${(overDac / alone).toFixed(3)} of its level alone (the DAC switched off when FM 6 is taken)`);
    const same = plain.pcm.every((v, i) => v === owned.pcm[i]);
    if (lastHalf !== 0 || back === 0 || !same) errors.push(`tune: owned-everything energy ${lastHalf}, given back ${back}, kr_race unchanged by its owners ${same}`);
    else notes.push("tune: every channel owned silences KESTREL FM (1-2 s), given back it plays (2-3 s); owning FM 5-6 + PSG 3 + noise leaves kr_race sample for sample");
    // The PSG's counters stand still while every channel is off (sn76489_mix): a tone 3 held on from the start keeps them
    // running in both renders, so the sum is a fair reference for tone 3. The noise is left out: its LFSR's phase
    // depends on the 2 engine frames before any cart write, when only the tune's PSG runs the counters.
    const noise = ([, ad, v]) => ad === 0x200 && ((v & 0xf0) >= 0xe0 || v === 0xdf);
    const w = [[0, 0x200, 0xcf], [0, 0x200, 0x3f], [0, 0x200, 0xd8], ...script(2).filter((x) => !noise(x))].sort((x, y) => x[0] - y[0]);
    const sfxOnly = await engine(w, n), both = await engine(w, n, TUNE);
    let worst = 0;
    for (let i = 0; i < both.pcm.length; i++) {
        const sum = Math.max(-32768, Math.min(32767, plain.pcm[i] + sfxOnly.pcm[i]));
        worst = Math.max(worst, Math.abs(both.pcm[i] - sum));
    }
    if (worst > 2 || sq(sfxOnly.pcm, 0, n) === 0) errors.push(`latches: tune + effects differs from their sum by ${worst}`);
    else notes.push(`latches: kr_race + the effects = kr_race + the effects alone within ${worst} a sample, 3 s (A4/A0 and PSG pairs interleaved)`);
}

async function refused(errors, notes) {
    const { m } = await modules();
    const off = m.machineVgmSfxPush(0, 0x028, 0xf6);
    m.machineVgmSfxOn(1);
    for (const x of [[0, 0x300, OWN], [0, 0x030, 1], [0, 0x3ff, 1], [0, 0x200, 0x9f], [0, 0x200, 0x02], [0, 0x122, 1], [0, 0x1a9, 1], [0, 0x200, 0xdf]]) m.machineVgmSfxPush(...x);
    let pushed = 0;
    while (m.machineVgmSfxPush(10, 0x1a2, 1) && pushed < 600) pushed++;
    m.machineVgmRender(0x2e0000, 64);
    const st = [m.machineVgmSfxStat(0), m.machineVgmSfxStat(1)];
    // own; FM 1 reg, unknown, PSG tone 1 latch, its data byte, port 1 0x22, port 1 0xA9 refused (6); the PSG 3 byte + 504 pairs applied
    if (off || pushed !== 512 - 8 || st[0] !== 2 + pushed || st[1] !== 6) errors.push(`refused: off ${off}, ring took ${pushed}, applied/refused ${st}`);
    else notes.push(`refused: off -> 0; FM 1, an unknown address, a PSG tone not owned (latch and its data byte), port 1's 0x22 and 0xA9: 6 refused; the ring full at 512`);
}

async function player(errors, notes) {
    const stopAt = 2 * 44100;
    const orig = script(3).concat([[stopAt, 0x301, 0], [stopAt, 0xd418 - 0xc000, 15]]).sort((x, y) => x[0] - y[0]); // the tune stops; a SID write: refused
    let w = orig;
    if (broke === "late") w = w.map(([t, a, v], i) => [i ? t + 300 : t, a, v]);
    if (broke === "order") { w = w.slice(); for (let i = 1; i < w.length; i++) if (w[i][0] === w[i - 1][0] && w[i][1] === 0x1a2 && w[i - 1][1] === 0x1a6) [w[i - 1], w[i]] = [w[i], w[i - 1]]; }
    const { memory, m, a } = await modules(), frames = Math.floor(3 * 44100 / FRAME), L = [];
    a.audioBardOpen(LEAD);
    let i = 0, room = 0, dev = 0, loaded = false;
    for (let f = 0; f < frames; f++) {
        const st = new Uint32Array(memory.buffer, a.audioBardStagePtr(), 4 * a.audioBardStageCap());
        let n = 0;
        for (; i < w.length && w[i][0] < (f + 1) * FRAME && n < 200; i++, n++) st.set([w[i][0], 0xc000 + w[i][1], w[i][2], 0], 4 * n);
        if (n) a.audioBardQueue(n);
        if (f === 0) {
            dev = a.audioBardDevice(), room = a.audioSongCapacity();
            const b = await readFile(TUNE);
            new Uint8Array(memory.buffer, a.audioSongPtr(), b.length).set(b);
            loaded = a.audioLoadVgm(b.length) && a.audioBardActive() === 1 && a.audioVgmActive();
        }
        for (let k = 0; k < FRAME; k += 105) {
            a.audioRender(105);
            const l = new Float32Array(memory.buffer, m.audioLeftPtr(), 105);
            for (const v of l) L.push(Math.round(v * 32768));
        }
    }
    const ref = await wasmStage(orig.map(([t, ad, v]) => [t + LEAD, ad, v]), 735, 4000);
    const bad = L.findIndex((v, j) => j < 3 * 44100 && v !== ((ref.out[0][j] << 24 >> 24) * 128 + (ref.out[2][j] << 24 >> 24))); // hi L x 128 + lo L
    const tail = L.slice(stopAt + LEAD + 3000), stopped = tail.some((v) => v !== 0);
    const s = { dev, room, loaded, applied: a.audioBardApplied(), refused: a.audioBardRefused(), late: a.audioBardLate(), resyncs: a.audioBardResyncs() };
    if (bad >= 0 || dev !== 3 || room !== 0xea000 || !loaded || s.late || s.resyncs || !stopped) errors.push(`player: differs at ${bad}; ${JSON.stringify(s)}, effects after the stop ${stopped}`);
    else notes.push(`player: the FM write gave the queue to the VGM player (device 3), the song room ${room} below the queue, kr_race loaded under it; 2 s = the reference stage with the lead (${LEAD}); ${s.applied} applied, ${s.refused} refused (the script's + a SID write), none late; after the tune stop the effects play on`);
}

const errors = [], notes = [];
if (!broke || BREAKS[broke]) await parity(errors, notes);
if (!broke) await stampAndOrder(errors, notes), await tune(errors, notes), await refused(errors, notes);
if (!broke || !BREAKS[broke]) await player(errors, notes);
for (const n of notes) console.log(`  ${n}`);
if (broke) {
    const hit = errors.find((e) => e.startsWith(BREAKS[broke] ? "parity:" : "player:"));
    console.log(hit ? `fm_sfx_check: PASS (--break ${broke} caught: ${hit})` : `fm_sfx_check: FAILED -- --break ${broke} not caught`);
    process.exitCode = hit ? 0 : 1;
} else {
    console.log(errors.length ? `fm_sfx_check: FAILED -- ${errors.join("; ")}` : "fm_sfx_check: all pass");
    process.exitCode = errors.length ? 1 : 0;
}
