// SID-Wizard's SID on the sound side (apps/ports/sidwizard, SW_SID_ON_BARD): every write the C64 program makes to
// the SID goes on the BARD queue stamped with its C64 cycle, and SID live plays it. Two hosts, as
// apps/bard_queue_check.mjs proves for BARD SID:
//   page     the cart (docs/demo-sidwizard.wasm) over the machine + ROM with its floppy in the drive, the loader's
//            hostBardAttach / bardFrame / bardPublish and the worklet's bardQueue / bardState on the real audio
//            modules (apps/bard_queue_lib.mjs pageSound)
//   native   the same cart on host_audio (fpga/build/host/sidwizard: wasm2c, cRSID native, host/bardq_pump.c)
//   equal    FLASHBAK.SWM opens at start, F1 plays it: the two outputs are the same samples from the first heard
//            one, >= 8 s of the song (the writes land at the same samples on both)
//   queue    heard on the page (SID live, mode 1), nothing refused, dropped or re-anchored
//   tempo    the page at 50 fps (20 ms frames) and at 16.7 fps (60 ms, the board's ~20): the C64 runs on the
//            frame's time, so it makes the same SID writes with the same stamps, and the outputs are the same samples
//   hold     the board's case where ZIGGY cannot run all of the C64 (kestrel_sw_pace.c): a host clock that says
//            each frame's allowance is spent ~25 % of the way in, so the main program waits for the rest of
//            it and only the IRQs run: F1 is seen later, but from the song's 150th tick on, each tick is the
//            same writes at the same distances (within 2 samples: the IRQ is entered from the wait), so the
//            player keeps its time
//   node apps/sidwizard_bard_check.mjs [--break stamp|reg] [--dump <commands.bin>]  (--dump: the song for snd-bench SND_BARDQ)
//     stamp: the loader delays every SID write two samples; reg: it writes the next register: both fail `equal`
import { execFileSync } from "node:child_process";
import { mkdtemp, readFile, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { cartRam, romRam } from "../docs/wasm_hiwater.js";
import { pageSound } from "./bard_queue_lib.mjs";

const CART = "docs/demo-sidwizard.wasm", DISK = "docs/demo-sidwizard.zmd";
const FRAMES = 900, F1_AT = 322, MIN_SAMPLES = 44100 * 8;
const BREAKS = ["stamp", "reg"];
const bi = process.argv.indexOf("--break");
const broke = bi > 0 ? process.argv[bi + 1] : null;
if (bi > 0 && !BREAKS.includes(broke)) throw new Error(`--break ${BREAKS.join(" | ")}`);

/** The cart on the page, `frames` frames of `ms` each; `clock`: the cart's hostMicros (0: none, every harness).
 * F1 goes down before frame F1_AT and up 6 frames later at 16.6 ms; at 49.8 ms (3 x 16.6) before frames
 * (F1_AT - 1) / 3 + 1 and 2 later: the same C64 instants, (F1_AT - 1) x 16.6 ms and 6 x 16.6 ms after.
 * Returns the left channel and the sound side's counters. */
async function pageRun({ ms = 16.6, base = 16.6, frames = FRAMES, clock = () => 0 } = {}) {
    const memory = new WebAssembly.Memory({ initial: 128, maximum: 128 });
    const machine = (await WebAssembly.instantiate(await readFile("docs/machine-video.wasm"), { env: { memory, hblDispatch() {} } })).instance.exports;
    const romBytes = await readFile("docs/rom.wasm");
    const rom = (await WebAssembly.instantiate(romBytes, { env: { memory, hwVideoBase: machine.hwVideoBase, hwBlit: machine.hwBlit } })).instance.exports;
    machine.hwSetRomHigh(romRam(romBytes).high ?? 0);
    const disk = await readFile(DISK), cartBytes = await readFile(CART);
    const sound = await pageSound(memory, { brk: broke, frames: Math.ceil(frames * ms / 16.6) + 4 });
    const log = [];
    const env = {
        memory, ...rom, hostBardAttach: sound.hostBardAttach, hostMicros: clock,
        consoleLogJS: (p, n) => log.push(new TextDecoder().decode(new Uint8Array(memory.buffer, p, n))),
        diskReadBlock: (b, dst) => { const s = disk.subarray(b * 512, b * 512 + 512); new Uint8Array(memory.buffer, dst, s.length).set(s); return s.length; },
        kosFileOp: () => -46, kosDriveRead: () => 0, // no C:, as the native host without --c-image
    };
    for (const k of Object.keys(machine)) if (k.startsWith("hw")) env[k] = machine[k];
    for (const imp of WebAssembly.Module.imports(new WebAssembly.Module(cartBytes))) if (!(imp.name in env)) env[imp.name] = () => 0;
    const demo = (await WebAssembly.instantiate(cartBytes, { env })).instance.exports;
    machine.hwSetCartHigh(cartRam(cartBytes).high ?? 0);
    machine.hwInit();
    demo.boot();
    demo.skipBoot();
    const k = Math.round(ms / base), f1 = (F1_AT - 1) / k + 1;
    for (let f = 1; f <= frames; f++) {
        if (f === f1) demo.key(0xe001);
        if (f === f1 + 6 / k) demo.keyUp(0xe001);
        demo.frame(ms);
        sound.frame(Math.round(ms * 44.1)); // 732 samples a 16.6 ms frame, 2205 a 50 ms one
    }
    return { left: sound.left(), stats: sound.stats(), log, cmds: sound.commands() };
}

async function nativeRun() {
    const host = "build/host/sidwizard/host_audio";
    execFileSync("mkdir", ["-p", "fpga/build/bardq"]);
    execFileSync("flock", ["build/bardq/make.lock", "make", "-s", "memmap", host], { cwd: "fpga", stdio: ["ignore", "ignore", "inherit"] });
    const dir = await mkdtemp(join(tmpdir(), "sidwizard_bard-"));
    execFileSync(`fpga/${host}`, ["sidwizard", String(FRAMES), String(FRAMES), "--disk", DISK,
        "--call", `${F1_AT}:key:57345`, "--call", `${F1_AT + 6}:keyUp:57345`],
        { env: { ...process.env, ZM_AUDIO_LOG: `${dir}/h`, ZM_GLASS_KEYS: "" }, encoding: "utf8", timeout: 900000, stdio: ["ignore", "ignore", "inherit"] });
    const pcm = await readFile(`${dir}/h.pcm`);
    const st = new Int16Array(pcm.buffer, pcm.byteOffset, pcm.length >> 1);
    const left = new Int16Array(st.length >> 1);
    for (let i = 0; i < left.length; i++) left[i] = st[2 * i];
    return { left };
}

const firstHeard = (a) => a.findIndex((v) => v !== 0);
// The SID writes as [t, addr, value] (the reset too); SONG_T: before F1's instant (the editor's own writes are earlier)
const writes = (c) => Array.from({ length: c.length / 4 }, (_, i) => [c[4 * i], c[4 * i + 1], c[4 * i + 2]]);
const SONG_T = Math.floor((F1_AT - 1) * 16.6 * 44.1);
// The song's ticks after F1: its writes in clusters (a gap of 200 samples parts two IRQs): the first write's
// stamp, the writes (register, value: `key`) and their stamps relative to it (`dt`).
function ticks(c) {
    const out = [];
    for (const [t, a, v] of writes(c)) {
        if (t <= SONG_T) continue;
        if (!out.length || t - out[out.length - 1].last > 200) out.push({ t, last: t, w: [], dt: [] });
        const k = out[out.length - 1];
        k.last = t;
        k.w.push(`${a}:${v}`);
        k.dt.push(t - k.t);
    }
    for (const k of out) k.key = k.w.join(",");
    return out;
}
function same(name, a, b, errors, notes, min = MIN_SAMPLES) {
    const a0 = firstHeard(a), b0 = firstHeard(b);
    if (a0 < 0 || b0 < 0) return errors.push(`${name}: silent (from ${a0} and ${b0})`);
    const n = Math.min(a.length - a0, b.length - b0);
    if (n < min) return errors.push(`${name}: only ${n} samples to compare`);
    for (let i = 0; i < n; i++) if (a[a0 + i] !== b[b0 + i]) return errors.push(`${name}: differs ${i} samples in (${a[a0 + i]} vs ${b[b0 + i]})`);
    notes.push(`${name}: ${n} samples (${(n / 44100).toFixed(1)} s) from the first heard one are the same (heard from ${a0} and ${b0})`);
}

const errors = [], notes = [];
const page = await pageRun();
const di = process.argv.indexOf("--dump");
if (di > 0) { // the song for snd-bench SND_BARDQ (BARDQ_LOG): a reset and the registers as they stand at the song's
    // first write, at t 0, then the song's writes rebased to it (the bench plays a log from t 0, a frame's lead)
    const w = writes(page.cmds), i = w.findIndex((x) => x[0] > SONG_T), t0 = w[i][0], reg = new Map();
    for (const [, a, v] of w.slice(0, i)) if (a >= 0xd400) reg.set(a, v);
    const out = [0, 1, 8580, 0, ...[...reg].flatMap(([a, v]) => [0, a, v, 0]), ...w.slice(i).flatMap(([t, a, v]) => [t - t0 + 1, a, v, 0])];
    await writeFile(process.argv[di + 1], new Uint8Array(Uint32Array.from(out).buffer));
    console.log(`  dump: ${out.length / 4} commands (the song from ${t0}) to ${process.argv[di + 1]}`);
}
if (process.env.PROFILE) { // the page's output, the peak of each 0.1 s
    const row = [];
    for (let i = 0; i < page.left.length; i += 4410) row.push(page.left.subarray(i, i + 4410).reduce((m, v) => Math.max(m, Math.abs(v)), 0));
    console.log(row.join(" "));
}
const native = await nativeRun();
same("equal", page.left, native.left, errors, notes);
if (!broke) {
    const s = page.stats, peak = page.left.reduce((m, v) => Math.max(m, Math.abs(v)), 0);
    if (s.mode !== 1 || peak < 1000 || s.refused || s.dropped || s.resyncs) errors.push(`queue: ${JSON.stringify(s)}, peak ${peak}`);
    else notes.push(`queue: SID live (mode ${s.mode}), ${s.applied} writes applied, none refused, dropped or re-anchored; peak ${peak}`);
    if (!page.log.some((l) => l.includes("BARD queue"))) errors.push("queue: the cart never opened the BARD queue");
    // (20 and 60 ms are exact floats: kestrel_frame_us turns 16.6 x 3 = 49.8 into 49799 us, not 49800)
    const fast = await pageRun({ ms: 20, base: 20 }), slow = await pageRun({ ms: 60, base: 20, frames: FRAMES / 3 });
    const wf = writes(fast.cmds), ws = writes(slow.cmds);
    const d = wf.findIndex((x, i) => !ws[i] || x.join() !== ws[i].join());
    if (wf.length < 2000 || d >= 0) errors.push(`tempo: ${wf.length} writes at 50 fps, ${ws.length} at 16.7 fps; write ${d} differs: ${wf[d]} vs ${ws[d]}`);
    else notes.push(`tempo: the same ${wf.length} SID writes, same stamps, at 50 and 16.7 fps`);
    same("tempo", fast.left, slow.left, errors, notes, 44100 * 5);
    // 3 ms a look at the clock: the frame's 10 ms allowance (60 % of 16.6) is spent after ~4 of its ~12 looks,
    // so the main program waits for the last ~3/4 of every frame. F1 is then seen later: the song is compared
    // from its 150th tick.
    let t = 0;
    const held = await pageRun({ clock: () => (t += 3000) });
    const a = ticks(page.cmds), b = ticks(held.cmds), at = Math.min(150, a.length - 1);
    const k = b.findIndex((x) => x.key === a[at].key); // the held run's tick that is the plain run's tick 150
    const n = Math.min(a.length - at, b.length - k) - 1;
    let bad = k < 0 || n < 200 ? 0 : -1;
    // Within 2 samples: a held main program enters the IRQ from the wait (which steps to the IRQ's own cycle), not
    // from its own instructions (2..7), so an IRQ may start a cycle or few apart: a stamp a sample apart.
    const near = (x, y) => Math.abs(x - y) <= 2;
    for (let i = 1; bad < 0 && i < n; i++)
        if (a[at + i].key !== b[k + i].key || !near(a[at + i].t - a[at].t, b[k + i].t - b[k].t)
            || a[at + i].dt.some((d, j) => !near(d, b[k + i].dt[j]))) bad = i;
    if (bad >= 0) errors.push(`hold: tick ${at} of the song ${k < 0 ? "never comes" : `departs ${bad} ticks later`} (${a.length} and ${b.length} ticks)`);
    else notes.push(`hold: the main program waited ~3/4 of every frame: from the song's tick ${at} on, ${n} ticks are the same writes at the same` +
        ` distances (tick ${at} came ${b[k].t - a[at].t} samples later: the slower main program loaded the song and saw F1 later)`);
}
for (const n of notes) console.log(`  ${n}`);
if (broke) {
    const hit = errors.find((e) => e.startsWith("equal:"));
    console.log(hit ? `sidwizard_bard_check: PASS (--break ${broke} caught: ${hit})` : `sidwizard_bard_check: FAILED -- --break ${broke} not caught`);
    process.exitCode = hit ? 0 : 1;
} else {
    console.log(errors.length ? `sidwizard_bard_check: FAILED -- ${errors.join("; ")}` : "sidwizard_bard_check: all pass");
    process.exitCode = errors.length ? 1 : 0;
}
