// Headless DHS / (n)0 PIXELS (n)0 REGRETS driver. Boots the sealed machine the
// way docs/sealed-loader.js does and runs the whole demo, one 20 ms VBL per host
// frame, through the end part (which the demo holds forever). It checks:
//   frames   every 50th frame, 440 of them across all seventeen parts, the WHOLE
//            400x280 physical frame (borders included) hashes to what the
//            reference model's colour-0 writes paint (apps/dhs_0pxl0reg_fixture.json,
//            from tools/private_tools/dhs_0pxl0reg_fixture.py): byte for byte
//   beam     REG_BEAM_DROPPED stays 0 over the entire run: no write the scene
//            queues breaks the 68000's limits
//   planes   no plane is ever enabled: every pixel is colour 0, as on the ST
//   music    "Fake It" starts at frame 159, stops at 7759, "AY Tunage" at 8173
//   node apps/dhs_0pxl0reg_headless.mjs [outdir]
//   node apps/dhs_0pxl0reg_headless.mjs --break skip   one VBL skipped at frame 1000:
//            passes only if the frame checks catch it
//   node apps/dhs_0pxl0reg_headless.mjs --break drop   a write 4 px after another on
//            line 150 (faster than a move.w): passes only if the machine counts drops
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { cartRam, romRam } from "../docs/wasm_hiwater.js";

const PAGES = 112; // SHARED_PAGES in machine/sdk/memmap.zig
const VIDEO = 0x300000; // HW_VIDEO_BASE
const REG_BEAM_COUNT = 0x64, REG_BEAM_DROPPED = 0x68, OFF_BEAM_TABLE = 0x1DBD00;
const W = 400, RW = 800, RH = 280;
const VBL_MS = 20;
const SONGS = [[159, "dhs_0pxl0reg_fake_it.sndh"], [7759, "none"], [8173, "dhs_0pxl0reg_ay_tuneage.sndh"]];
const bi = process.argv.indexOf("--break");
const broke = bi > 0 ? process.argv[bi + 1] : null;
if (broke && broke !== "skip" && broke !== "drop") throw new Error("--break skip | drop");
const outdir = process.argv.slice(2).find((a, i, v) => !a.startsWith("--") && v[i - 1] !== "--break") || "/tmp/dhs_0pxl0reg";

const fixture = JSON.parse(await readFile("apps/dhs_0pxl0reg_fixture.json", "utf8"));
const want = new Map(fixture.frames.map((f) => [f.f, f]));

const memory = new WebAssembly.Memory({ initial: PAGES, maximum: PAGES });
const dv = () => new DataView(memory.buffer);
let demo;
const hbl = (id, p, line, x) => {
    demo.hblDispatch(id, p, line, x);
    if (broke === "drop" && line === 150) { // a write 4 px after the last one: faster than any move.w
        const n = dv().getUint16(VIDEO + REG_BEAM_COUNT, true);
        const last = n ? dv().getUint32(VIDEO + OFF_BEAM_TABLE + 4 * (n - 1), true) >>> 16 : 100;
        const put = (i, x) => dv().setUint32(VIDEO + OFF_BEAM_TABLE + 4 * i, ((x << 16) | 0x700) >>> 0, true);
        if (!n) put(0, last);
        put(n ? n : 1, last + 4);
        dv().setUint16(VIDEO + REG_BEAM_COUNT, n ? n + 1 : 2, true);
    }
};
const machine = (await WebAssembly.instantiate(await readFile("docs/machine-video.wasm"),
    { env: { memory, hblDispatch: (...a) => hbl(...a) } })).instance.exports;
const romBytes = await readFile("docs/rom.wasm");
const env0 = { memory, hwVideoBase: machine.hwVideoBase, hwBlit: machine.hwBlit };
const rom = (await WebAssembly.instantiate(romBytes, { env: env0 })).instance.exports;
machine.hwSetRomHigh(romRam(romBytes).high ?? 0);
const cartBytes = await readFile("docs/demo-dhs_0pxl0reg.wasm");
const env = {
    ...env0,
    hwRamBase: machine.hwRamBase, hwRamTop: machine.hwRamTop, hwRamSize: machine.hwRamSize,
    hwRamUsed: machine.hwRamUsed, hwRamFree: machine.hwRamFree,
    hwRomRamBase: machine.hwRomRamBase, hwRomRamTop: machine.hwRomRamTop,
    hwRomRamSize: machine.hwRomRamSize, hwRomRamUsed: machine.hwRomRamUsed,
    hwRomRamFree: machine.hwRomRamFree, ...rom,
};
for (const imp of WebAssembly.Module.imports(new WebAssembly.Module(cartBytes)))
    if (imp.module === "env" && !(imp.name in env)) env[imp.name] = () => {};
demo = (await WebAssembly.instantiate(cartBytes, { env })).instance.exports;
machine.hwSetCartHigh(cartRam(cartBytes).high ?? 0);
machine.hwInit();
demo.boot();
demo.skipBoot();

// The physical frame, un-doubled: 400x280 RGBA words. Both raster pixels of a
// physical pixel must agree (a beam span is always whole pixels).
function frame() {
    const pfb = new Uint32Array(memory.buffer, machine.hwPhysicalPtr(), RW * RH);
    const px = new Uint32Array(W * RH);
    for (let y = 0; y < RH; y++) for (let x = 0; x < W; x++) {
        const a = pfb[y * RW + 2 * x];
        if (a !== pfb[y * RW + 2 * x + 1]) throw new Error(`line ${y} x ${x}: the two raster pixels differ`);
        px[y * W + x] = a;
    }
    return px;
}
function fnv(px) {
    const b = new Uint8Array(px.buffer);
    let h = 0x811c9dc5;
    for (let i = 0; i < b.length; i++) h = Math.imul(h ^ b[i], 0x01000193) >>> 0;
    return h;
}
async function shot(px, path) {
    const rgb = Buffer.alloc(W * RH * 3);
    for (let i = 0; i < W * RH; i++) { rgb[3 * i] = px[i] & 255; rgb[3 * i + 1] = (px[i] >> 8) & 255; rgb[3 * i + 2] = (px[i] >> 16) & 255; }
    await writeFile(path, Buffer.concat([Buffer.from(`P6\n${W} ${RH}\n255\n`), rgb]));
}

await mkdir(outdir, { recursive: true });
const songs = [];
// one shot per part, from the middle of its checked frames
const byPart = new Map();
for (const f of fixture.frames) byPart.set(f.part, [...(byPart.get(f.part) || []), f.f]);
const shotAt = new Set([...byPart.values()].map((fs) => fs[fs.length >> 1]));
let bad = 0, checked = 0, planesOn = 0, clearMs = 0, frameMs = 0;
const parts = new Set();
for (let F = 0; F <= fixture.last; F++) {
    let t = performance.now();
    machine.hwClear(); // runs the global HBL: paints frame F from the writes tick F listed
    clearMs += performance.now() - t;
    for (let p = 0; p < 4; p++) if (demo.isPlaneEnabled(p)) planesOn++;
    const w = want.get(F);
    if (w) {
        const px = frame();
        const h = fnv(px);
        checked++;
        parts.add(w.part);
        if (h !== w.hash) {
            if (bad < 5) console.log(`  FAIL frame ${F} (${w.part}): hash ${h.toString(16)}, model ${w.hash.toString(16)}`);
            if (bad === 0) await shot(px, `${outdir}/fail-${F}.ppm`);
            bad++;
        } else if (shotAt.has(F)) await shot(px, `${outdir}/${w.part}-${F}.ppm`);
    }
    t = performance.now();
    demo.frame(broke === "skip" && F === 1000 ? 2 * VBL_MS : VBL_MS);
    frameMs += performance.now() - t;
    if (demo.pollSongRequest()) {
        const name = new TextDecoder().decode(new Uint8Array(memory.buffer, demo.songNamePtr(), demo.songNameLen()));
        songs.push([F + 1, name]);
    }
}
const dropped = dv().getUint32(VIDEO + REG_BEAM_DROPPED, true);
const n = fixture.last + 1;
console.log(`  frames: ${checked - bad}/${checked} identical to the model (${parts.size} parts: ${[...parts].join(" ")})`);
console.log(`  beam: ${dropped} writes dropped over ${n} frames`);
console.log(`  cost: ${(frameMs / n).toFixed(3)} ms/frame scene + ${(clearMs / n).toFixed(3)} ms/frame beam paint`);
const songsOk = JSON.stringify(songs) === JSON.stringify(SONGS);
console.log(`  music: ${songs.map(([f, s]) => `${f}:${s}`).join(", ")}`);

if (broke) {
    const ok = broke === "skip" ? bad > 0 && dropped === 0 : dropped > 0;
    console.log(ok ? `dhs_0pxl0reg: PASS (--break ${broke} caught: ${bad} frames differ, ${dropped} writes dropped)`
        : `dhs_0pxl0reg: FAILED — --break ${broke} was not caught (bad ${bad}, dropped ${dropped})`);
    process.exit(ok ? 0 : 1);
}
const errors = [];
if (bad) errors.push(`${bad} frames differ from the model`);
if (checked !== fixture.frames.length) errors.push(`checked ${checked} of ${fixture.frames.length} frames`);
if (dropped) errors.push(`${dropped} beam writes dropped`);
if (planesOn) errors.push(`a plane was enabled on ${planesOn} frame-planes`);
if (!songsOk) errors.push(`music requests ${JSON.stringify(songs)}, want ${JSON.stringify(SONGS)}`);
console.log(errors.length ? `dhs_0pxl0reg: FAILED — ${errors.join("; ")}` : "dhs_0pxl0reg: all pass");
process.exit(errors.length ? 1 : 0);
