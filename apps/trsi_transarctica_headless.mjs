// Headless TRSI / TRANSARCTICA driver: boots the sealed machine the way
// docs/sealed-loader.js does, runs the cracktro at one 20 ms VBL per host frame
// (the scene paces itself by real 50 Hz VBLs) and checks what the MACHINE shows
// against the reverse-engineered reference model (model.py), which reproduces
// the original's three Hatari RAM snapshots and seven screenshots exactly:
//   frames   at 17 program VBL counters (intro flash, logo fade, slide, all six
//            pages, the snapshot and screenshot frames) the 320x240 display --
//            physical rows 20..259, the top and bottom borders open -- hashes to
//            the model's display through its palette
//   borders  the open bands (rows 0..19, 260..279) are the Falcon border:
//            palette entry 0
//   loop     text frame n and n + 4210 (two passes of the colour list, all six
//            pages) are identical
//   music    the cart requests trsi_transarctica.mod at BPM 123 on its first
//            VBL, and the MOD, started that way on the real audio modules,
//            plays, at a tempo that is not 125's; started at 125 through the
//            new entry, it is byte-identical to audioModPlay
//   node apps/trsi_transarctica_headless.mjs [outdir]
//   node apps/trsi_transarctica_headless.mjs --break skip   one VBL skipped: must FAIL the frames
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { createHash } from "node:crypto";
import { cartRam, romRam } from "../docs/wasm_hiwater.js";

const PAGES = 112; // SHARED_PAGES in machine/sdk/memmap.zig
const AUDIO_PAGES = 48; // AUDIO_PAGES in machine/sdk/audio.zig
const VBL_MS = 20;
const W = 320, H = 240, TOP = 20; // the display, and its first physical row
const LOOP = 4210; // VBLs: two passes of the colour list = the six pages
const MUSIC = "trsi_transarctica.mod", BPM = 123;

// python3 re/expect.py (the RE model): [c, sha256 of the 320x240 RGB, palette 0]
const FRAMES = [
    [40, "ca683669f12f371d6e9e9bd92e565cd0dd4611c0acd4859c304ed897c46920ab", [150, 150, 150]], // white flash fading
    [100, "2a589ae1f2fa2a6328223ff195a29c9244bec633dca49139f6f231e1d79c0eb2", [0, 0, 0]], // logo copied, palette still black
    [160, "e585b51ed89b9ce0ba3a23a8aa6f3740b9642506d8afd56884b60b61bd1fed87", [0, 0, 0]], // logo fade-in
    [300, "bfd9e8b3a88e8639ffa17c9e98390039e0c879e83dfe9315f94b521f57834754", [0, 0, 0]], // intro hold (screenshot 0031)
    [440, "6a5d2fa8dbfbff13f4213c00a5f093dded5da9256103a542d311a88aba024243", [0, 0, 0]], // logo slide, base line 27
    [577, "df414d4c8138c3033f82c00adeb3ae8721e695acea2f85073698e57812447052", [0, 0, 0]], // text frame 0, window black
    [805, "15063e20bd42d5e3037e2b3b9259729e972a55c90f0485a8eb04e597c1745d6a", [0, 0, 0]], // page 0, n=228 (screenshot 0033)
    [901, "60a7179a5ddc9ef581eb34255ed71dcffcfc02815ec70e5155d12e2601e7d556", [0, 0, 0]], // page 0, n=324 (screenshot 0034)
    [906, "a6fcdd9fd75e988edab90ca4fc892f2094252250d0fe1cf991128e3468390569", [0, 0, 0]], // page 0 (RAM snapshot)
    [1341, "5597b4f147e22a095413bdb4e79577f6d250d87ab1de02e578e9e1f39ff6943b", [0, 0, 0]], // page 0 hiding (screenshot 0037)
    [1555, "b10d8030a15d26c044af4d1c8aa29531a2023b626903dec51e42603f50f668f4", [0, 0, 0]], // page 1 reveal (screenshot 0036)
    [1556, "e670fbe02ba80eb5d1a9d0fbe4fa3495e1e302ae15c3c81b96608aad99910778", [0, 0, 0]], // page 1 (RAM snapshot)
    [2377, "35922168bcda8a6168f9b97e08b1692f68650fbb1f53e27879911f9a88b3bf55", [0, 0, 0]], // page 2, n=1800
    [3117, "f83b8e41032e0890b7667f5243179c2b465d0b344a4f8795c181dd30b19e779b", [0, 0, 0]], // page 3, n=2540
    [3862, "3b337eb5b27aab454c8163769d0e310b7fd6a3101858d387166f2b8bf61703de", [0, 0, 0]], // page 4, n=3285
    [4477, "373b2fc9fc9048e84a6b90cb0a926e02cab155d7991c0875908ccb2b8a3eaafc", [0, 0, 0]], // page 5, n=3900
    [5556, "9e61e0101c667cb668a977fd4423572888aced7c35e191f58d517cc66fa0893c", [0, 0, 0]], // page 0, 2nd loop (RAM snapshot)
];
const LOOP_AT = 805; // compared with LOOP_AT + LOOP

const bi = process.argv.indexOf("--break");
const broke = bi > 0 ? process.argv[bi + 1] : null;
if (broke && broke !== "skip") throw new Error("--break skip");
const outdir = process.argv.slice(2).find((a, i, v) => !a.startsWith("--") && v[i - 1] !== "--break") || "/tmp/trsi_transarctica";

async function boot(cart = "docs/demo-trsi_transarctica.wasm") {
    const memory = new WebAssembly.Memory({ initial: PAGES, maximum: PAGES });
    let demo;
    const machine = (await WebAssembly.instantiate(await readFile("docs/machine-video.wasm"), {
        env: { memory, hblDispatch: (id, p, l, x) => demo.hblDispatch(id, p, l, x) },
    })).instance.exports;
    const romBytes = await readFile("docs/rom.wasm");
    const env0 = { memory, hwVideoBase: machine.hwVideoBase, hwBlit: machine.hwBlit };
    const rom = (await WebAssembly.instantiate(romBytes, { env: env0 })).instance.exports;
    machine.hwSetRomHigh(romRam(romBytes).high ?? 0);
    const cartBytes = await readFile(cart);
    const env = { ...env0, ...rom };
    for (const k of Object.keys(machine)) if (k.startsWith("hwRam") || k.startsWith("hwRomRam")) env[k] = machine[k];
    for (const imp of WebAssembly.Module.imports(new WebAssembly.Module(cartBytes)))
        if (imp.module === "env" && !(imp.name in env)) env[imp.name] = () => {};
    demo = (await WebAssembly.instantiate(cartBytes, { env })).instance.exports;
    machine.hwSetCartHigh(cartRam(cartBytes).high ?? 0);
    machine.hwInit();
    demo.boot();
    demo.skipBoot();
    return { memory, machine, demo };
}

const { memory, machine, demo } = await boot();
const PW = machine.hwPhysWidth(), PH = machine.hwPhysHeight(), BX = machine.hwBorderX(); // 800 (x-doubled), 280, 80
const pfb = () => new Uint8Array(memory.buffer, machine.hwPhysicalPtr(), PW * PH * 4);
const rgbAt = (p, x2, y) => { const i = (y * PW + x2) * 4; return [p[i], p[i + 1], p[i + 2]]; };

function display() { // the 320x240 display, un-doubled, RGB
    const p = pfb(), out = Buffer.alloc(W * H * 3);
    for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) out.set(rgbAt(p, BX + 2 * x, TOP + y), (y * W + x) * 3);
    return out;
}
function bandsAre(rgb) { // rows 0..19 and 260..279, the full width of the 320 window
    const p = pfb();
    for (const y of [...Array(TOP).keys(), ...Array.from({ length: TOP }, (_, i) => TOP + H + i)])
        for (let x = 0; x < W; x++) if (rgbAt(p, BX + 2 * x, y).some((v, k) => v !== rgb[k])) return false;
    return true;
}
const sha = (b) => createHash("sha256").update(b).digest("hex");

await mkdir(outdir, { recursive: true });
const want = new Map(FRAMES.map(([c, h, bg]) => [c, { h, bg }]));
const last = Math.max(LOOP_AT + LOOP, ...FRAMES.map(([c]) => c));
const songs = [];
const got = new Map();
let bad = 0, badBands = 0, ms = 0;
for (let c = 1; c <= last; c++) {
    const t = performance.now();
    machine.hwClear();
    demo.frame(broke === "skip" && c === 700 ? 2 * VBL_MS : VBL_MS); // runs program VBL c
    machine.hwRenderPlane(0);
    ms += performance.now() - t;
    if (demo.pollSongRequest())
        songs.push([c, new TextDecoder().decode(new Uint8Array(memory.buffer, demo.songNamePtr(), demo.songNameLen())), demo.songTune()]);
    const w = want.get(c);
    if (!w && c !== LOOP_AT + LOOP) continue;
    const img = display(), h = sha(img);
    got.set(c, h);
    if (w && h !== w.h) {
        if (bad++ < 3) {
            console.log(`  FAIL c=${c}: ${h} is not the model's ${w.h}`);
            await writeFile(`${outdir}/fail-${c}.ppm`, Buffer.concat([Buffer.from(`P6\n${W} ${H}\n255\n`), img]));
        }
    } else if (w) await writeFile(`${outdir}/c${c}.ppm`, Buffer.concat([Buffer.from(`P6\n${W} ${H}\n255\n`), img]));
    if (w && !bandsAre(w.bg)) { badBands++; console.log(`  FAIL c=${c}: the open border bands are not palette 0`); }
}
console.log(`  frames: ${FRAMES.length - bad}/${FRAMES.length} identical to the model; ${(ms / last).toFixed(3)} ms/frame (frame + plane composite)`);
if (broke) {
    console.log(bad ? `trsi_transarctica: PASS (--break skip caught: ${bad} frames differ)`
        : "trsi_transarctica: FAILED — --break skip was not caught");
    process.exit(bad ? 0 : 1);
}

// ---- music: requested on VBL 1 at BPM 123, and it plays on the audio modules ----
async function audio() {
    const mem = new WebAssembly.Memory({ initial: AUDIO_PAGES, maximum: AUDIO_PAGES });
    const chip = (await WebAssembly.instantiate(await readFile("docs/machine-audio.wasm"), { env: { memory: mem } })).instance.exports;
    const env = { memory: mem };
    for (const k of Object.keys(chip)) if (k.startsWith("machine")) env[k] = chip[k];
    const d = (await WebAssembly.instantiate(await readFile("docs/demo-audio.wasm"), { env })).instance.exports;
    const song = new Uint8Array(await readFile(`docs/music/${MUSIC}`));
    const render = (start) => { // 3 s of the left channel after a fresh start
        d.audioInit();
        new Uint8Array(mem.buffer, d.audioSongPtr(), song.length).set(song);
        if (!d.audioLoadMod(song.length)) throw new Error(`${MUSIC} does not load`);
        start(d);
        const out = [];
        for (let n = 0; n < 3 * 44100; n += 1024) {
            d.audioRender(1024);
            out.push(Buffer.from(new Float32Array(mem.buffer, chip.audioLeftPtr(), 1024).slice().buffer));
        }
        return { pcm: Buffer.concat(out), mode: d.audioMode() };
    };
    const at123 = render((d) => d.audioModPlayBpm(BPM));
    const plain = render((d) => d.audioModPlay());
    const at125 = render((d) => d.audioModPlayBpm(125));
    const f = new Float32Array(at123.pcm.buffer, at123.pcm.byteOffset, at123.pcm.length / 4);
    const peak = f.reduce((m, v) => Math.max(m, Math.abs(v)), 0);
    return { peak, mode: at123.mode, tempoDiffers: !at123.pcm.equals(plain.pcm), sameAt125: at125.pcm.equals(plain.pcm) };
}
const a = await audio();
console.log(`  music: requests ${JSON.stringify(songs)}; at BPM ${BPM}: mode ${a.mode}, peak ${a.peak.toFixed(3)}, ` +
    `differs from 125: ${a.tempoDiffers}, audioModPlayBpm(125) == audioModPlay: ${a.sameAt125}`);

const errors = [];
if (bad) errors.push(`${bad} frames differ from the model`);
if (badBands) errors.push(`${badBands} frames with the border bands off palette 0`);
if (got.get(LOOP_AT) !== got.get(LOOP_AT + LOOP)) errors.push(`c=${LOOP_AT + LOOP} is not c=${LOOP_AT}: the pages do not loop`);
else console.log(`  loop: c=${LOOP_AT + LOOP} is c=${LOOP_AT}, pixel for pixel (six pages, two list passes)`);
if (JSON.stringify(songs) !== JSON.stringify([[1, MUSIC, BPM]])) errors.push(`music requests ${JSON.stringify(songs)}`);
if (a.mode !== 1 || !(a.peak > 0.01)) errors.push("the MOD does not play");
if (!a.tempoDiffers) errors.push("BPM 123 plays exactly as 125");
if (!a.sameAt125) errors.push("audioModPlayBpm(125) is not audioModPlay");
console.log(errors.length ? `trsi_transarctica: FAILED — ${errors.join("; ")}` : "trsi_transarctica: all pass");
process.exit(errors.length ? 1 : 0);
