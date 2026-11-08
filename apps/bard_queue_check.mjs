// The BARD queue (zg.bard, system table 1.12) and its first device, SID live, on two hosts:
//   page     BARD SID (cart 121) writes its tune into its ring; the loader's bardFrame takes the frame's
//            commands, the worklet's bardQueue queues them on demo-audio.wasm, raw cRSID (machine-audio.wasm)
//            plays each at its sample; the worklet's bardState comes back through the loader's bardPublish
//            (apps/bard_queue_lib.mjs, the real loader and worklet code)
//   native   the same cart on host_audio (fpga/build/host/bard_sid: the cart and the players through wasm2c,
//            cRSID native, host/audio_bardq.c + host/bardq_pump.c: BARD's own pump)
//   equal    the two outputs are the same samples from the first heard one, for FRAMES frames: the
//            writes land at the same sample on both, whatever each host's blocks and frames
//   queue    the tune is heard (mode 1), every command applied, none refused, dropped or re-anchored,
//            the beats' marks came back to the cart
//   model    key 2 resets the SID as an 8580 at the next tick: the page's output parts from the 6581's
//            after the key, and the reset comes back as an event. (Which tick is "next" follows the
//            sound side's position, so it is host-dependent: equal runs without it.)
//   drain    bardDrain stops at an entry not yet whole (its seq), and takes nothing from a bad header
//   node apps/bard_queue_check.mjs [--break stamp|reg] [--dump <commands.bin>]
//     stamp: the loader delays every SID write two samples (the resets keep their stamp); reg: it
//     writes the next register: both must
//     fail `equal`
import { execFileSync } from "node:child_process";
import { mkdtemp, readFile, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { loaderBard, pageRun } from "./bard_queue_lib.mjs";

const FRAMES = 420, KEY_AT = 300, MIN_SAMPLES = 44100 * 5;
const BREAKS = ["stamp", "reg"];
const bi = process.argv.indexOf("--break");
const broke = bi > 0 ? process.argv[bi + 1] : null;
if (bi > 0 && !BREAKS.includes(broke)) throw new Error(`--break ${BREAKS.join(" | ")}`);

async function nativeRun() {
    const host = "build/host/bard_sid/host_audio";
    // One make at a time: the gate runs this harness three times at once (ROADMAP: the mp3_player flake).
    execFileSync("mkdir", ["-p", "fpga/build/bardq"]);
    execFileSync("flock", ["build/bardq/make.lock", "make", "-s", "memmap", host], { cwd: "fpga", stdio: ["ignore", "ignore", "inherit"] });
    const dir = await mkdtemp(join(tmpdir(), "bard_queue-"));
    const log = execFileSync(`fpga/${host}`, ["bard_sid", String(FRAMES), String(FRAMES)],
        { env: { ...process.env, ZM_AUDIO_LOG: `${dir}/h`, ZM_GLASS_KEYS: "" }, encoding: "utf8", timeout: 600000 });
    const pcm = await readFile(`${dir}/h.pcm`);
    const st = new Int16Array(pcm.buffer, pcm.byteOffset, pcm.length >> 1);
    const left = new Int16Array(st.length >> 1);
    for (let i = 0; i < left.length; i++) left[i] = st[2 * i];
    return { left, log };
}

const firstHeard = (a) => a.findIndex((v) => v !== 0);

function equal(page, native, errors, notes) {
    const p0 = firstHeard(page), n0 = firstHeard(native);
    if (p0 < 0 || n0 < 0) return errors.push(`equal: silent (page from ${p0}, native from ${n0})`);
    const n = Math.min(page.length - p0, native.length - n0);
    if (n < MIN_SAMPLES) return errors.push(`equal: only ${n} samples to compare`);
    for (let i = 0; i < n; i++)
        if (page[p0 + i] !== native[n0 + i])
            return errors.push(`equal: differs ${i} samples in (page ${page[p0 + i]}, native ${native[n0 + i]})`);
    notes.push(`equal: ${n} samples (${(n / 44100).toFixed(1)} s) from the first heard one: page = native` +
        ` (heard from ${p0} on the page, ${n0} natively)`);
}

function queue(run, errors, notes) {
    const s = run.stats, peak = run.left.reduce((m, v) => Math.max(m, Math.abs(v)), 0);
    if (run.mode !== 1 || peak < 1000) errors.push(`queue: mode ${run.mode}, peak ${peak}: not heard`);
    if (s.applied + s.pending !== run.commands || s.refused || s.dropped || s.resyncs || s.closed || s.cartDropped)
        errors.push(`queue: ${run.commands} commands taken, ${JSON.stringify(s)}`);
    if (s.events < 10 || s.lost || !s.anchored) errors.push(`queue: ${s.events} events back, ${s.lost} lost, anchored ${s.anchored}`);
    notes.push(`queue: ${run.commands} commands, ${s.applied} applied and ${s.pending} still ahead; ${s.events} events back (beat marks, the resets); peak ${peak}`);
}

async function model(plain, errors, notes) {
    const swapped = await pageRun(FRAMES, { keys: { [KEY_AT]: 1 } });
    const at = KEY_AT * 735, cut = plain.left.findIndex((v, i) => v !== swapped.left[i]);
    const reset = swapped.events.find((e) => e[1] === 2 && e[2] === 8580);
    if (cut < at || !reset) errors.push(`model: the 8580 parts at ${cut} (key at ${at}), its reset event ${JSON.stringify(reset)}`);
    else notes.push(`model: key 2 at sample ${at}: the 8580's reset stamped ${reset[0]} comes back, the output parts at ${cut}`);
}

async function drain(errors, notes) {
    const mem = { buffer: new ArrayBuffer(65536) }, u = new Uint32Array(mem.buffer), b = 64;
    const L = await loaderBard(mem, null, null);
    u.set([0x51424d5a, 8, 4, 4096, 3, 0], b);
    for (let i = 0; i < 3; i++) u.set([100 * i, 0xD400 + i, i, i === 2 ? 99 : i], b + 16 + 4 * i); // the third not whole
    const got = L.bardDrain(u, b);
    if (got.length !== 8 || u[b + 5] !== 2) errors.push(`drain: took ${got.length / 4} entries, tail ${u[b + 5]}, not 2 and 2`);
    u[b + 1] = 6; // not a power of two
    if (L.bardDrain(u, b).length) errors.push("drain: a bad header was drained");
    notes.push("drain: stops at an entry whose seq is not its index; a bad header gives nothing");
}

const errors = [], notes = [];

const page = await pageRun(FRAMES, { brk: broke });
const di = process.argv.indexOf("--dump"); // the commands as the loader posted them: snd-bench SND_BARDQ's log
if (di > 0) await writeFile(process.argv[di + 1], new Uint8Array(page.log.buffer));
const native = await nativeRun();
equal(page.left, native.left, errors, notes);
if (!broke) {
    queue(page, errors, notes);
    await model(page, errors, notes);
    await drain(errors, notes);
}
for (const n of notes) console.log(`  ${n}`);
// exitCode, never process.exit() (apps/mod_sfx_check.mjs: node 24 deadlocks at exit).
if (broke) {
    const hit = errors.find((e) => e.startsWith("equal:"));
    console.log(hit ? `bard_queue_check: PASS (--break ${broke} caught: ${hit})` : `bard_queue_check: FAILED -- --break ${broke} not caught`);
    process.exitCode = hit ? 0 : 1;
} else {
    console.log(errors.length ? `bard_queue_check: FAILED -- ${errors.join("; ")}` : "bard_queue_check: all pass");
    process.exitCode = errors.length ? 1 : 0;
}
