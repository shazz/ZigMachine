// ChipNomad's AY on BARD (apps/ports/chipnomad/kestrel_chip.cpp): every register write the tracker makes goes on the
// BARD queue stamped with its sample, and the AY device (libs/c/ayumi zm_ay_bank.h, libs/zig/players/ay_live.zig)
// plays it in stereo. Two hosts, as apps/sidwizard_bard_check.mjs proves for SID-Wizard's SID:
//   page     the cart (docs/demo-chipnomad.wasm) over the machine + ROM with its floppy in the drive, the loader's
//            hostBardAttach / bardFrame / bardPublish and the worklet's bardQueue / bardState on the real audio
//            modules (apps/bard_queue_lib.mjs pageSound)
//   native   the same cart on host_audio (fpga/build/host/chipnomad: wasm2c, the AY engine native, host/bardq_pump.c)
//   script   ports_headless.mjs's: X puts chain 00 in the song, a C-4 in its phrase on instrument 00, made AY
//            Classic, START plays it
//   equal    the two outputs are the same samples from the first heard one, both sides, >= 5 s
//   queue    the cart says it opened the queue; the stream is never started (the AY is not rendered on ZIGGY); heard on
//            the page (mode 1), in stereo (the project's ABC pans), nothing refused, dropped or re-anchored
//   soft     the same script with instrument 00 made AY Sample (Right three times: a software oscillator, stepped per
//            chip tick, no register stream): the cart goes back to ZIGGY (it says so, the queue closes: mode 0, the
//            stream starts and is fed)
//   node apps/chipnomad_bard_check.mjs [--break stamp|reg|soft]
//     stamp: the loader delays every AY register write two samples; reg: it writes the next register: both fail `equal`;
//     soft: the `soft` run's instrument left AY2 (Right twice: no oscillator) must fail `soft`
import { execFileSync } from "node:child_process";
import { mkdtemp, readFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { cartRam, romRam } from "../docs/wasm_hiwater.js";
import { pageSound } from "./bard_queue_lib.mjs";

const CART = "docs/demo-chipnomad.wasm", DISK = "docs/demo-chipnomad.zmd";
const FRAMES = 560, MIN_SAMPLES = 44100 * 5;
const KEY_X = 0x78, KEY_SPACE = 0x20, SHIFT_LEFT = 0xe015, RIGHT = 3;
const BREAKS = ["stamp", "reg", "soft"];
const bi = process.argv.indexOf("--break");
const broke = bi > 0 ? process.argv[bi + 1] : null;
if (bi > 0 && !BREAKS.includes(broke)) throw new Error(`--break ${BREAKS.join(" | ")}`);

// ports_headless.mjs's chipnomad script, as [frame, export, arg] (SELECT + Right: the next screen)
const tap = (f, name, arg) => [[f, name, arg], [f + 2, name === "key" ? "keyUp" : "inputRelease", arg]];
const next = (f) => [[f, "key", SHIFT_LEFT], ...tap(f + 2, "input", RIGHT), [f + 6, "keyUp", SHIFT_LEFT]];
const script = (rights) => [...tap(30, "key", KEY_X), ...next(40), ...tap(55, "key", KEY_X), ...next(65), ...tap(80, "key", KEY_X), ...next(90),
    [105, "key", KEY_X], ...Array.from({ length: rights }, (_, i) => tap(108 + 4 * i, "input", RIGHT)).flat(), [121, "keyUp", KEY_X],
    ...tap(130, "key", KEY_SPACE)];
const SCRIPT = script(1); // None -> AY Classic

async function pageRun(events = SCRIPT, frames = FRAMES) {
    const memory = new WebAssembly.Memory({ initial: 128, maximum: 128 });
    const machine = (await WebAssembly.instantiate(await readFile("docs/machine-video.wasm"), { env: { memory, hblDispatch() {} } })).instance.exports;
    const romBytes = await readFile("docs/rom.wasm");
    const rom = (await WebAssembly.instantiate(romBytes, { env: { memory, hwVideoBase: machine.hwVideoBase, hwBlit: machine.hwBlit } })).instance.exports;
    machine.hwSetRomHigh(romRam(romBytes).high ?? 0);
    const disk = await readFile(DISK), cartBytes = await readFile(CART);
    const sound = await pageSound(memory, { brk: broke === "soft" ? null : broke, frames: frames + 4 });
    const log = [], stream = { starts: 0, fed: 0 };
    const env = {
        memory, ...rom, hostBardAttach: sound.hostBardAttach, hostMicros: () => 0,
        hostAudioStreamStart: () => { stream.starts++; }, hostAudioFeed: (p, n) => { stream.fed += n; }, hostAudioStreamStop: () => {},
        consoleLogJS: (p, n) => log.push(new TextDecoder().decode(new Uint8Array(memory.buffer, p, n))),
        diskReadBlock: (b, dst) => { const s = disk.subarray(b * 512, b * 512 + 512); new Uint8Array(memory.buffer, dst, s.length).set(s); return s.length; },
    };
    for (const k of Object.keys(machine)) if (k.startsWith("hw")) env[k] = machine[k];
    for (const imp of WebAssembly.Module.imports(new WebAssembly.Module(cartBytes))) if (!(imp.name in env)) env[imp.name] = () => 0;
    const demo = (await WebAssembly.instantiate(cartBytes, { env })).instance.exports;
    machine.hwSetCartHigh(cartRam(cartBytes).high ?? 0);
    machine.hwInit();
    demo.boot();
    demo.skipBoot();
    for (let f = 1; f <= frames; f++) {
        for (const [cf, name, arg] of events) if (cf === f) demo[name](arg);
        demo.frame(16.6);
        sound.frame(732); // 16.6 ms at 44.1 kHz, as the cart's clock (kestrel_frame_us)
    }
    return { left: sound.left(), right: sound.right(), stats: sound.stats(), log, stream };
}

async function nativeRun() {
    const host = "build/host/chipnomad/host_audio";
    execFileSync("mkdir", ["-p", "fpga/build/bardq"]);
    execFileSync("flock", ["build/bardq/make.lock", "make", "-s", "memmap", host], { cwd: "fpga", stdio: ["ignore", "ignore", "inherit"] });
    const dir = await mkdtemp(join(tmpdir(), "chipnomad_bard-"));
    execFileSync(`fpga/${host}`, ["chipnomad", String(FRAMES), String(FRAMES), "--disk", DISK, ...SCRIPT.flatMap(([f, n, a]) => ["--call", `${f}:${n}:${a}`])],
        { env: { ...process.env, ZM_AUDIO_LOG: `${dir}/h`, ZM_GLASS_KEYS: "" }, encoding: "utf8", timeout: 900000, stdio: ["ignore", "ignore", "inherit"] });
    const pcm = await readFile(`${dir}/h.pcm`);
    const st = new Int16Array(pcm.buffer, pcm.byteOffset, pcm.length >> 1);
    const left = new Int16Array(st.length >> 1), right = new Int16Array(st.length >> 1);
    for (let i = 0; i < left.length; i++) { left[i] = st[2 * i]; right[i] = st[2 * i + 1]; }
    return { left, right };
}

const firstHeard = (a) => a.findIndex((v) => v !== 0);
function same(name, a, b, errors, notes) {
    const a0 = firstHeard(a.left), b0 = firstHeard(b.left);
    if (a0 < 0 || b0 < 0) return errors.push(`${name}: silent (from ${a0} and ${b0})`);
    const n = Math.min(a.left.length - a0, b.left.length - b0);
    if (n < MIN_SAMPLES) return errors.push(`${name}: only ${n} samples to compare`);
    for (let i = 0; i < n; i++)
        if (a.left[a0 + i] !== b.left[b0 + i] || a.right[a0 + i] !== b.right[b0 + i])
            return errors.push(`${name}: differs ${i} samples in (L ${a.left[a0 + i]} vs ${b.left[b0 + i]}, R ${a.right[a0 + i]} vs ${b.right[b0 + i]})`);
    notes.push(`${name}: ${n} samples (${(n / 44100).toFixed(1)} s) a side from the first heard one are the same (heard from ${a0} and ${b0})`);
}

// The soft-oscillator fallback: AY Sample (None -> AY1 -> AY2 -> AY Sample), or AY2 under --break soft.
async function soft(errors, notes) {
    const r = await pageRun(script(broke === "soft" ? 2 : 3), 200);
    const said = r.log.some((l) => l.includes("software oscillator")), s = r.stats;
    if (!said || s.mode !== 0 || !r.stream.starts || !r.stream.fed) errors.push(`soft: said ${said}, mode ${s.mode}, stream ${JSON.stringify(r.stream)}`);
    else notes.push(`soft: AY Sample's oscillator sent the cart back to ZIGGY: the queue closed (mode ${s.mode}), the stream fed ${r.stream.fed} bytes`);
}

const errors = [], notes = [];
if (broke === "soft") await soft(errors, notes);
const page = broke === "soft" ? null : await pageRun();
if (page) same("equal", page, await nativeRun(), errors, notes);
if (!broke) {
    await soft(errors, notes);
    const s = page.stats, peak = page.left.reduce((m, v) => Math.max(m, Math.abs(v)), 0);
    const stereo = page.left.some((v, i) => v !== page.right[i]);
    if (s.mode !== 1 || peak < 500 || !stereo || s.refused || s.dropped || s.resyncs) errors.push(`queue: ${JSON.stringify(s)}, peak ${peak}, stereo ${stereo}`);
    else notes.push(`queue: the AY device (mode ${s.mode}), ${s.applied} writes applied, none refused, dropped or re-anchored; peak ${peak}; L != R (the project's pans)`);
    if (!page.log.some((l) => l.includes("BARD queue"))) errors.push("queue: the cart never opened the BARD queue");
    if (page.stream.starts || page.stream.fed) errors.push(`queue: the stream ran beside it (${page.stream.starts} starts, ${page.stream.fed} bytes)`);
    else notes.push("queue: no stream: nothing rendered on ZIGGY");
}
for (const n of notes) console.log(`  ${n}`);
if (broke) {
    const hit = errors.find((e) => e.startsWith(broke === "soft" ? "soft:" : "equal:"));
    console.log(hit ? `chipnomad_bard_check: PASS (--break ${broke} caught: ${hit})` : `chipnomad_bard_check: FAILED -- --break ${broke} not caught`);
    process.exitCode = hit ? 0 : 1;
} else {
    console.log(errors.length ? `chipnomad_bard_check: FAILED -- ${errors.join("; ")}` : "chipnomad_bard_check: all pass");
    process.exitCode = errors.length ? 1 : 0;
}
