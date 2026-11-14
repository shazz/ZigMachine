// The AY on BARD against today's ZIGGY render (README "AY on BARD", step d). Not a gate: a measurement.
//   make -C apps/ports/chipnomad link OUT=build_autoplay EXTRA='-DKESTREL_AUTOPLAY="\"/MICROEGG.CNM\""'
//   make -C apps/ports/chipnomad link OUT=build_autoplay_ziggy EXTRA='-DKESTREL_AUTOPLAY="\"/MICROEGG.CNM\"" -DKESTREL_AY_ON_ZIGGY=1'
//   node apps/ports/chipnomad/tools/bard_compare.mjs [seconds=20] [--script]
// --script: the shipped cart (docs/) and the gate's C-4 on an AY Classic instrument (ports_headless.mjs), BARD
// against the same cart on a host with no queue (its fallback, the stream).
// Both builds play the song from boot on the page's machine (its floppy in the drive). ZIGGY's output is the stream
// the cart feeds: 22050 Hz, 8-bit, mono ((L + R) / 2 >> 8). BARD's is the audio modules' 44.1 kHz stereo (the hi/lo
// Paula path, x >> 1). BARD's is folded the stream's way (mono, pairs averaged to 22050, 8 bits), aligned by
// cross-correlation (the two start at different leads), then compared: correlation, RMS, the difference's RMS, zero
// crossings (pitch), and both sides' own RMS (BARD keeps the project's pans).
import { readFile } from "node:fs/promises";
import { cartRam, romRam } from "../../../../docs/wasm_hiwater.js";
import { pageSound } from "../../../bard_queue_lib.mjs";

const SCRIPTED = process.argv.includes("--script");
const SECONDS = +(process.argv.find((a, i) => i > 1 && /^\d/.test(a)) ?? 20), FRAMES = Math.ceil(SECONDS * 60) + (SCRIPTED ? 200 : 120);
const KEY_X = 0x78, KEY_SPACE = 0x20, SHIFT_LEFT = 0xe015, RIGHT = 3;
const tap = (f, name, arg) => [[f, name, arg], [f + 2, name === "key" ? "keyUp" : "inputRelease", arg]];
const next = (f) => [[f, "key", SHIFT_LEFT], ...tap(f + 2, "input", RIGHT), [f + 6, "keyUp", SHIFT_LEFT]];
const SCRIPT = !SCRIPTED ? [] : [...tap(30, "key", KEY_X), ...next(40), ...tap(55, "key", KEY_X), ...next(65), ...tap(80, "key", KEY_X),
    ...next(90), [105, "key", KEY_X], ...tap(108, "input", RIGHT), [113, "keyUp", KEY_X], ...tap(130, "key", KEY_SPACE)];

async function run(cart, attach = true) {
    const memory = new WebAssembly.Memory({ initial: 128, maximum: 128 });
    const machine = (await WebAssembly.instantiate(await readFile("docs/machine-video.wasm"), { env: { memory, hblDispatch() {} } })).instance.exports;
    const romBytes = await readFile("docs/rom.wasm");
    const rom = (await WebAssembly.instantiate(romBytes, { env: { memory, hwVideoBase: machine.hwVideoBase, hwBlit: machine.hwBlit } })).instance.exports;
    machine.hwSetRomHigh(romRam(romBytes).high ?? 0);
    const disk = await readFile("docs/demo-chipnomad.zmd"), cartBytes = await readFile(cart);
    const sound = await pageSound(memory, { frames: FRAMES + 4 });
    const fed = [], log = [];
    const env = {
        memory, ...rom, hostBardAttach: attach ? sound.hostBardAttach : () => 0, hostMicros: () => 0,
        hostAudioFeed: (p, n) => fed.push(new Int8Array(memory.buffer, p, n).slice()),
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
    for (let f = 1; f <= FRAMES; f++) {
        for (const [cf, name, arg] of SCRIPT) if (cf === f) demo[name](arg);
        demo.frame(16.6);
        sound.frame(732);
    }
    const stream = new Int8Array(fed.reduce((s, a) => s + a.length, 0));
    let o = 0;
    for (const a of fed) { stream.set(a, o); o += a.length; }
    return { stream, left: sound.left(), right: sound.right(), stats: sound.stats(), log };
}

const rms = (a, from = 0, n = a.length - from) => { let s = 0; for (let i = 0; i < n; i++) s += a[from + i] * a[from + i]; return Math.sqrt(s / n); };
const first = (a) => a.findIndex((v) => v !== 0);
const crossings = (a, from, n) => { let c = 0; for (let i = from + 1; i < from + n; i++) if ((a[i - 1] < 0) !== (a[i] < 0)) c++; return c; };

const bard = await run(SCRIPTED ? "docs/demo-chipnomad.wasm" : "apps/ports/chipnomad/build_autoplay/demo-chipnomad.wasm");
const ziggy = SCRIPTED ? await run("docs/demo-chipnomad.wasm", false) : await run("apps/ports/chipnomad/build_autoplay_ziggy/demo-chipnomad.wasm");
console.log(`bard: ${bard.log.filter((l) => /autoplay|BARD|ZIGGY/.test(l)).join(" | ")}; ${JSON.stringify(bard.stats)}, stream ${bard.stream.length} B`);
console.log(`ziggy: ${ziggy.log.filter((l) => /autoplay|BARD|ZIGGY/.test(l)).join(" | ")}; stream ${ziggy.stream.length} B`);

// BARD folded the stream's way: L, R are x >> 1, so L + R is the mono x; pairs averaged to 22050; >> 8.
const n22 = bard.left.length >> 1, m16 = new Float64Array(n22), m8 = new Int8Array(n22);
for (let i = 0; i < n22; i++) {
    m16[i] = (bard.left[2 * i] + bard.right[2 * i] + bard.left[2 * i + 1] + bard.right[2 * i + 1]) / 2;
    m8[i] = Math.max(-128, Math.min(127, Math.floor(m16[i] / 256)));
}
const z = ziggy.stream, b0 = first(m8), z0 = first(z), N = Math.min(SECONDS * 22050, n22 - b0 - 2205, z.length - z0 - 2205);
// align: the lag (within 100 ms of the first heard samples) with the best correlation
let best = { lag: 0, c: -Infinity };
for (let lag = -2205; lag <= 2205; lag++) {
    let c = 0;
    for (let i = 0; i < 44100; i++) c += m8[b0 + i] * (z[z0 + lag + i] ?? 0);
    if (c > best.c) best = { lag, c };
}
const zs = z0 + best.lag;
let sab = 0, saa = 0, sbb = 0, sd = 0, same = 0;
for (let i = 0; i < N; i++) {
    const a = m8[b0 + i], b = z[zs + i];
    sab += a * b; saa += a * a; sbb += b * b; sd += (a - b) * (a - b); same += a === b;
}
const corr = sab / Math.sqrt(saa * sbb);
if (process.env.LAGS) for (let lag = -4; lag <= 4; lag++) { let c = 0, aa = 0, bb = 0; for (let i = 0; i < N; i++) { const a = m8[b0 + i], b = z[zs + lag + i]; c += a * b; aa += a * a; bb += b * b; } console.log(`  lag ${lag}: ${(c / Math.sqrt(aa * bb)).toFixed(4)}`); }
console.log(`compared ${(N / 22050).toFixed(1)} s at 22050 Hz, 8-bit mono, aligned at lag ${best.lag}:`);
console.log(`  correlation ${corr.toFixed(4)}; samples equal ${(100 * same / N).toFixed(1)} %`);
console.log(`  rms BARD ${rms(m8, b0, N).toFixed(2)}, ZIGGY ${rms(z, zs, N).toFixed(2)} (ratio ${(rms(m8, b0, N) / rms(z, zs, N)).toFixed(3)}), difference ${Math.sqrt(sd / N).toFixed(2)}`);
console.log(`  zero crossings BARD ${crossings(m8, b0, N)}, ZIGGY ${crossings(z, zs, N)}`);
const L0 = first(bard.left), n44 = Math.min(N * 2, bard.left.length - L0);
console.log(`  BARD stereo (16-bit, x >> 1): rms L ${rms(bard.left, L0, n44).toFixed(0)}, R ${rms(bard.right, L0, n44).toFixed(0)}`);
