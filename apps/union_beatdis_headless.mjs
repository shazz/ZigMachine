// Headless Union Demo TCB1 BEAT DIS check (apps/zig/scenes/union_beatdis.zig),
// run once per version, 1 MB (SPACE) and 1/2 MB (RETURN):
//
// 1. Loader. The TEX loader panel (depack fx = tex_loader, ink #C0A000) shows
//    while beatdis.bin depacks, for the ~130 frames its pacing gives; then the
//    whole frame must be the panel with loader.js's question under it, pixel
//    for pixel, and must wait there (no song, no screen) until a key.
// 2. Screen. screen.js / screen2.js replayed in canvas units
//    (apps/union_beatdis_replay.mjs, from the sources, not the scene), sampled
//    at canvas (2X, 2Y) for ST pixel (X, Y), at fixed frames and at the first
//    frames a '!' shows at an odd and an even x. The CurveRipper tables in
//    curve.zig must equal screen2.js's when the remake is on this machine.
//    Hub notes (ROM scratch "UNI1", return_note.zig): 1024 runs with a note for
//    ANOTHER door and 512 with one for this door at scroll 500, so the text
//    starts at 0 and at 500; a third run's out-of-range scroll starts at 0.
//    Leaving, the accepted note must hold the same door and x/y and the
//    scroller's scroffset; a refused one must not have changed a byte.
// 3. The song request (name and subtune 1), the SNDH really playing on the
//    sealed YM, ESC / SPACE back to the hub, RETURN not, and the frame cost.
//
//   node apps/union_beatdis_headless.mjs [outdir] [cart.wasm]
import { readFile, writeFile, mkdir, access } from "node:fs/promises";
import { performance } from "node:perf_hooks";
import { deflateSync } from "node:zlib";
import { cartRam, romRam } from "../docs/wasm_hiwater.js";
import { loadAssets, makeReplay, promptMap, CW } from "./union_beatdis_replay.mjs";

const PAGES = 112, AUDIO_PAGES = 48; // machine/sdk/memmap.zig, machine/sdk/audio.zig
const TOP = 40, LEFT = 80; // ST (0,0) in the physical frame (x doubled)
const DEPACK_FRAMES = Math.ceil(325408 / (9 * 280)); // DEPACK_BYTES_PER_LINE = 9
const TEX_INK = [0xc0, 0xa0, 0x00];
const K_ESC = 0xe012, K_RETURN = 13, K_SPACE = 32;
const BANG_LIMIT = 40000; // 16,128 letters at 96/7 frames each is 221k frames: '!' is common enough well before
const FRAMES = [0, 1, 2, 24, 25, 26, 45, 46, 99, 100, 101, 148, 149, 150, 199, 200, 201, 512, 513, 1234, 3000];
const BEATDIS_DOOR = 0; // TMX object 0 in menu_map.zig, the door doors.zig tags union_beatdis
const VERSIONS = [
    { name: "1024", key: K_SPACE, song: "union/beat_dis.sndh", note: { door: 8, scroll: 500 }, start: 0, accept: false },
    { name: "512", key: K_RETURN, song: "union/pro_bmx_simulator_b.sndh", note: { door: BEATDIS_DOOR, scroll: 500 }, start: 500, accept: true },
    { name: "1024", key: K_SPACE, song: "union/beat_dis.sndh", note: { door: BEATDIS_DOOR, scroll: 16128 }, start: 0, accept: false },
];
const REMAKE = "prototypes/oldies/Union-Demo-HTML5-Remake-0.9.8/screens/beatdis/screen2.js";

const outDir = process.argv[2];
const cartPath = process.argv[3] || "docs/demo-union_beatdis.wasm";
if (outDir) await mkdir(outDir, { recursive: true });
const A = await loadAssets();
const errors = [];
const dec = new TextDecoder();

async function boot(note) {
    const memory = new WebAssembly.Memory({ initial: PAGES, maximum: PAGES });
    let demo;
    const machine = (await WebAssembly.instantiate(await readFile("docs/machine-video.wasm"), {
        env: { memory, hblDispatch: (id, p, l, x) => demo.hblDispatch(id, p, l, x) },
    })).instance.exports;
    const romBytes = await readFile("docs/rom.wasm");
    const rom = (await WebAssembly.instantiate(romBytes, { env: { memory, hwVideoBase: machine.hwVideoBase, hwBlit: machine.hwBlit } })).instance.exports;
    machine.hwSetRomHigh(romRam(romBytes).high ?? 0);
    writeHubNote(memory, rom, note);
    const cartBytes = await readFile(cartPath);
    const env = { memory, ...rom };
    for (const k of Object.keys(machine)) if (k.startsWith("hw")) env[k] = machine[k];
    for (const imp of WebAssembly.Module.imports(new WebAssembly.Module(cartBytes)))
        if (imp.module === "env" && !(imp.name in env)) env[imp.name] = () => {};
    demo = (await WebAssembly.instantiate(cartBytes, { env })).instance.exports;
    machine.hwSetCartHigh(cartRam(cartBytes).high ?? 0);
    machine.hwInit();
    demo.boot();
    demo.skipBoot();
    return { memory, machine, demo, rom };
}

// return_note.write's record, as the hub leaves it at door `note.door` (Charly at 686,127).
function writeHubNote(memory, rom, note) {
    const at = new DataView(memory.buffer, rom.romScratchPtr(), 20);
    at.setUint8(6, note.door); at.setUint8(7, 0);
    at.setFloat32(8, 686, true); at.setFloat32(12, 127, true); at.setUint32(16, note.scroll, true);
    let xor = 0;
    for (let i = 6; i < 20; i++) xor ^= at.getUint8(i);
    at.setUint8(4, 14); at.setUint8(5, xor);
    [..."UNI1"].forEach((c, i) => at.setUint8(i, c.charCodeAt(0)));
}
const noteBytes = ({ memory, rom }) => Array.from(new Uint8Array(memory.buffer, rom.romScratchPtr(), 20));

// The note after leaving: unchanged when refused; else a valid record with the
// hub's door and x/y and `scroll` = the scroller's scroffset.
function noteAfterLeaving(v, before, after, scroffset) {
    if (!v.accept) return after.some((b, i) => b !== before[i]) ? `${v.name}: a refused note was rewritten` : null;
    const dv = new DataView(Uint8Array.from(after).buffer);
    const xor = after.slice(6).reduce((a, b) => a ^ b, 0);
    const same = [0, 1, 2, 3, 4, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15].every((i) => after[i] === before[i]);
    if (!same || after[5] !== xor) return `${v.name}: the note came back with its tag, door or x/y changed, or a bad checksum`;
    if (dv.getUint32(16, true) !== scroffset) return `${v.name}: the note's scroll is ${dv.getUint32(16, true)}, the scroller is at ${scroffset}`;
    return null;
}

function makeCart({ memory, machine, demo }) {
    const W = machine.hwPhysWidth(), H = machine.hwPhysHeight();
    const cart = { song: null, ms: 0, frames: 0, warm: [] };
    cart.step = (warm = false) => {
        const t0 = performance.now();
        demo.frame(1000 / 60);
        const ms = performance.now() - t0;
        cart.ms += ms;
        cart.frames++;
        if (warm) cart.warm.push(ms);
        if (demo.pollSongRequest()) cart.song = { name: dec.decode(new Uint8Array(memory.buffer, demo.songNamePtr(), demo.songNameLen())), tune: demo.songTune() };
    };
    cart.shot = () => {
        machine.hwRenderPlane(0);
        const px = new Uint8Array(memory.buffer, machine.hwPhysicalPtr(), W * H * 4);
        const img = new Uint8Array(320 * 200 * 4);
        for (let y = 0; y < 200; y++) for (let x = 0; x < 320; x++) {
            const o = ((y + TOP) * W + LEFT + x * 2) * 4;
            img.set(px.subarray(o, o + 4), (y * 320 + x) * 4);
        }
        return img;
    };
    cart.leaves = () => {
        const req = demo.pollCartRequest();
        return req === 1 && dec.decode(new Uint8Array(memory.buffer, demo.getCartTagPtr(), demo.getCartTagLen())) === "union_demo";
    };
    return cart;
}

// wrong pixels of a 320x200 shot against palette indices `at(x, y)`
function wrongPixels(img, at) {
    let wrong = 0;
    for (let y = 0; y < 200; y++) for (let x = 0; x < 320; x++) {
        const v = at(x, y), o = (y * 320 + x) * 4;
        if (img[o + 3] !== 255 || img[o] !== A.pal[v * 4] || img[o + 1] !== A.pal[v * 4 + 1] || img[o + 2] !== A.pal[v * 4 + 2]) wrong++;
    }
    return wrong;
}

function loader(v, cart) {
    let inkFrames = 0, maxInk = 0, asked = -1;
    const expected = promptMap(A);
    for (let f = 1; f <= 400 && asked < 0; f++) {
        cart.step();
        const img = cart.shot();
        let ink = 0;
        for (let i = 0; i < img.length; i += 4) if (img[i + 3] && img[i] === TEX_INK[0] && img[i + 1] === TEX_INK[1] && img[i + 2] === TEX_INK[2]) ink++;
        if (ink) inkFrames++;
        maxInk = Math.max(maxInk, ink);
        if (wrongPixels(img, (x, y) => expected[y * 320 + x]) === 0) asked = f;
    }
    if (asked < 0) return errors.push(`${v.name}: the loader never showed its panel and question`);
    if (Math.abs(asked - DEPACK_FRAMES) > 1) errors.push(`${v.name}: the question came at frame ${asked}, the depack pacing says ${DEPACK_FRAMES}`);
    if (inkFrames < DEPACK_FRAMES / 2 || maxInk < 2000) errors.push(`${v.name}: the TEX loader panel barely showed: ink on ${inkFrames} frames, at most ${maxInk} px`);
    for (let f = 0; f < 30; f++) cart.step();
    if (cart.song) errors.push(`${v.name}: a song was requested before the question was answered`);
    if (wrongPixels(cart.shot(), (x, y) => expected[y * 320 + x])) errors.push(`${v.name}: the question did not wait`);
    return asked;
}

async function screen(v, cart, demo) {
    const replay = makeReplay(A, v.name, v.start);
    demo.key(v.key);
    const want = new Set(FRAMES);
    const bangs = { odd: -1, even: -1 };
    const seen = new Map();
    // Past the last fixed frame, keep stepping (painting nothing) until a '!' has
    // shown at both parities: where they fall depends on where the text starts.
    const last = Math.max(...FRAMES);
    for (let f = 0; f <= last || (f <= BANG_LIMIT && (bangs.odd < 0 || bangs.even < 0)); f++) {
        cart.step(f > 1234);
        replay.update();
        for (const l of replay.letters) if (l.ltr === 33 && l.posx > -96 && l.posx < 576) {
            const kind = l.posx & 1 ? "odd" : "even";
            if (bangs[kind] < 0) { bangs[kind] = f; want.add(f); }
        }
        if (!want.has(f)) continue;
        const map = replay.paint(), img = cart.shot();
        const wrong = wrongPixels(img, (x, y) => map[2 * y * CW + 2 * x]);
        if (wrong) errors.push(`${v.name} screen frame ${f}: ${wrong} px off the screen.js replay`);
        seen.set(f, img);
        if (outDir && [0, 100, 1234].includes(f)) await writeFile(`${outDir}/union_beatdis-${v.name}-${f}.png`, png(img));
    }
    if (bangs.odd < 0 || bangs.even < 0) errors.push(`${v.name}: no '!' at both parities by frame ${BANG_LIMIT}`);
    const moved = (a, b, y0, y1) => seen.get(a).subarray(y0 * 1280, y1 * 1280).some((p, i) => p !== seen.get(b)[y0 * 1280 + i]);
    if (!moved(200, 201, 0, 150)) errors.push(`${v.name} frames 200/201: beatdis.png does not scroll`);
    if (!moved(200, 201, 167, 183)) errors.push(`${v.name} frames 200/201: the scroller does not move`);
    if (v.name === "512" && !moved(1234, 3000, 0, 150)) errors.push("512: the sprites do not move");
    return { bangs, replay };
}

async function sndhPlays(song) {
    const memory = new WebAssembly.Memory({ initial: AUDIO_PAGES, maximum: AUDIO_PAGES });
    const machine = (await WebAssembly.instantiate(await readFile("docs/machine-audio.wasm"), { env: { memory } })).instance.exports;
    const env = { memory };
    for (const n of Object.keys(machine)) if (n.startsWith("machine")) env[n] = machine[n];
    const audio = (await WebAssembly.instantiate(await readFile("docs/demo-audio.wasm"), { env })).instance.exports;
    audio.audioInit();
    const bytes = new Uint8Array(await readFile(`docs/music/${song.name}`));
    if (bytes.length > audio.audioSongCapacity()) return `${song.name} is over the song capacity`;
    new Uint8Array(memory.buffer, audio.audioSongPtr(), bytes.length).set(bytes);
    if (!audio.audioLoadSndh(bytes.length)) return `${song.name}: audioLoadSndh refused it`;
    if (audio.audioSndhSubtunes() < song.tune) return `${song.name} has ${audio.audioSndhSubtunes()} subtunes, ${song.tune} requested`;
    audio.audioSndhPlay(song.tune);
    const SR = 44100, BLOCK = 882, SECONDS = 8;
    let peak = 0, secPeak = 0, silent = 0;
    for (let done = 0; done < SECONDS * SR; done += BLOCK) {
        audio.audioRender(BLOCK);
        for (const s of new Float32Array(memory.buffer, machine.audioLeftPtr(), BLOCK)) { const a = Math.abs(s); peak = Math.max(peak, a); secPeak = Math.max(secPeak, a); }
        if ((done / BLOCK + 1) % 50 === 0) { if (secPeak <= 0.01) silent++; secPeak = 0; }
    }
    if (audio.audioMode() !== 4 || audio.audioSndhStuckPc() || silent) return `${song.name}: mode ${audio.audioMode()}, stuck PC $${audio.audioSndhStuckPc().toString(16)}, ${silent} silent s`;
    return `peak ${peak.toFixed(2)}`;
}

async function curveMatchesRemake() {
    try { await access(REMAKE); } catch { return "remake not on this machine, tables not re-read"; }
    const js = await readFile(REMAKE, "utf8");
    const table = (n) => js.match(new RegExp(`this.${n} = new Array\\(([^)]*)\\)`))[1].split(",").map((t) => Number(t.trim()));
    const same = (a, b) => a.length === b.length && a.every((x, i) => x === b[i]);
    if (!same(table("spritePosX"), A.curveX) || !same(table("spritePosY"), A.curveY)) errors.push("curve.zig differs from screen2.js's CurveRipper tables");
    return `curve.zig = screen2.js (${A.curveX.length} points)`;
}

const report = [await curveMatchesRemake()];
for (const v of VERSIONS) {
    const booted = await boot(v.note);
    const planted = noteBytes(booted);
    const cart = makeCart(booted);
    const asked = loader(v, cart);
    const { bangs, replay } = await screen(v, cart, booted.demo);
    if (!cart.song || cart.song.name !== v.song || cart.song.tune !== 1) errors.push(`${v.name}: song request ${JSON.stringify(cart.song)}, wanted "${v.song}" tune 1`);
    const played = cart.song ? await sndhPlays(cart.song) : "no song";
    if (!played.startsWith("peak")) errors.push(`${v.name}: ${played}`);
    if (noteBytes(booted).some((b, i) => b !== planted[i])) errors.push(`${v.name}: the screen changed the hub's note before leaving`);
    booted.demo.key(K_RETURN);
    if (booted.demo.pollCartRequest() !== 0) errors.push(`${v.name}: RETURN left the screen`);
    booted.demo.key(v.name === "1024" ? K_ESC : K_SPACE);
    if (!cart.leaves()) errors.push(`${v.name}: ${v.name === "1024" ? "ESC" : "SPACE"} did not ask for union_demo`);
    const noteWrong = noteAfterLeaving(v, planted, noteBytes(booted), replay.scroffset);
    if (noteWrong) errors.push(noteWrong);
    const perFrame = cart.ms / cart.frames, warm = cart.warm.sort((a, b) => a - b)[cart.warm.length >> 1];
    if (perFrame > 4) errors.push(`${v.name}: cart takes ${perFrame.toFixed(3)} ms/frame`);
    report.push(`${v.name} (note door ${v.note.door} scroll ${v.note.scroll} -> text at ${v.start}, left at ${replay.scroffset}): question at frame ${asked}, '!' odd/even at ${bangs.odd}/${bangs.even}, ${cart.song?.name} ${played}, ${perFrame.toFixed(3)} ms/frame mean, ${warm.toFixed(3)} warm median`);
}

if (errors.length) {
    console.error(`union_beatdis: WRONG\n  ${errors.slice(0, 12).join("\n  ")}`);
    process.exit(1);
}
console.log(`union_beatdis: loader panel + question exact, screen = screen.js/screen2.js replay at frames ${FRAMES.join(",")} + '!' frames; ${report.join("; ")}`);

function png(rgba) {
    const raw = Buffer.alloc(200 * (1 + 320 * 3));
    for (let y = 0; y < 200; y++) for (let x = 0; x < 320; x++) {
        const o = (y * 320 + x) * 4;
        raw.set([rgba[o], rgba[o + 1], rgba[o + 2]], y * 961 + 1 + x * 3);
    }
    const table = Array.from({ length: 256 }, (_, n) => { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1; return c >>> 0; });
    const crc = (b) => { let c = 0xffffffff; for (const x of b) c = table[(c ^ x) & 0xff] ^ (c >>> 8); return (c ^ 0xffffffff) >>> 0; };
    const chunk = (type, data) => {
        const b = Buffer.alloc(12 + data.length);
        b.writeUInt32BE(data.length, 0); b.write(type, 4, "latin1"); data.copy(b, 8);
        b.writeUInt32BE(crc(b.subarray(4, 8 + data.length)), 8 + data.length);
        return b;
    };
    const ihdr = Buffer.alloc(13); ihdr.writeUInt32BE(320, 0); ihdr.writeUInt32BE(200, 4); ihdr.set([8, 2, 0, 0, 0], 8);
    return Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk("IHDR", ihdr), chunk("IDAT", deflateSync(raw)), chunk("IEND", Buffer.alloc(0))]);
}
