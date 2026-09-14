// Headless Union Demo TNT2 check (apps/zig/scenes/union_tnt2.zig).
//
// 1. Loader. The cart starts behind the TEX loader panel (depack fx = tex_loader):
//    the panel's ink (#C0A000) is on screen while the data depacks, the depack
//    takes the frames its pacing gives, and the screen starts on the frame it ends.
// 2. Screen. screen.js (update 73-157, draw 164-190), codef_core.js image.draw /
//    drawTile and codef_scrolltext.js (54-172) are replayed here at CANVAS
//    resolution (640x400), from the source and not from the scene, with a key
//    script driving update()'s else-if chain the way melonJS reports held keys.
//    The cart's ST pixel (X, Y) must equal canvas pixel (2X, 2Y) at every sampled
//    frame, including frames where a key made a band or the scroller sit at an
//    odd canvas x. The pictures are tnt2.bin pixel-doubled back to canvas size;
//    with --remake DIR they are decoded from the remake's own PNGs instead.
// 3. The song request names the SNDH and it plays on the sealed YM (mode SNDH,
//    no stuck PC, every second audible, all three voices written).
// 4. Space asks for the hub; a frame fits 60 fps with room to spare.
//
//   node apps/union_tnt2_headless.mjs [outdir] [cart.wasm] [--remake DIR] [--break green]
// --break green replays screen.js with the green band at -5 instead of -6
// (screen.js:41): the fail proof, it must report WRONG.
import { readFile, writeFile, mkdir } from "node:fs/promises";
import { performance } from "node:perf_hooks";
import { deflateSync, inflateSync } from "node:zlib";
import { cartRam, romRam } from "../docs/wasm_hiwater.js";

const PAGES = 112, AUDIO_PAGES = 48; // SHARED_PAGES in machine/sdk/memmap.zig; machine/sdk/audio.zig
const TOP = 40, LEFT = 80; // ST (0,0) in the physical frame (x doubled)
const ASSETS = "apps/zig/assets/screens/union_tnt2";
const TEXT_FILE = "apps/zig/assets/screens/union_demo/scrolltext.txt"; // jsApp.scrolltext
const MUSIC = "union/cybernoid.sndh";
const TEX_INK = [0xc0, 0xa0, 0x00];
const K_ESC = 0xe012;
const MODE_SNDH = 4;
const HOLD = 2; // union_tnt2/controls.zig: a host key event holds its key two frames

const argv = process.argv.slice(2);
const at = argv.indexOf("--remake");
const remake = at >= 0 ? argv.splice(at, 2)[1] : null;
const bi = argv.indexOf("--break");
const brk = bi >= 0 ? argv.splice(bi, 2)[1] : null;
if (bi >= 0 && brk !== "green") throw new Error(`--break takes green, not ${brk}`);
const outDir = argv[0] || "/tmp/union_tnt2";
const cartPath = argv[1] || "docs/demo-union_tnt2.wasm";
await mkdir(outDir, { recursive: true });

// ---- the pictures at canvas size: { w, h, px: Int32Array of 0xRRGGBB, -1 transparent } ----
// tnt2.bin's layout (union_tnt2/assets.zig): name, ST crop x, y, w, h, canvas size.
const LAYOUT = [
    ["overlay2", 96, 0, 131, 198, 640, 400], ["blueLayer", 0, 0, 320, 200, 640, 400],
    ["brownLayer", 0, 40, 320, 120, 640, 400], ["greenLayer", 0, 64, 320, 72, 640, 400],
    ["overlay", 99, 4, 131, 191, 640, 400], ["fonts", 0, 0, 320, 140, 640, 280],
];

async function fromBin() {
    const bin = new Uint8Array(await readFile(`${ASSETS}/tnt2.bin`));
    const pal = new Uint8Array(await readFile(`${ASSETS}/pal.dat`));
    const out = {};
    let off = 0;
    for (const [name, cx, cy, w, h, cw, ch] of LAYOUT) {
        const px = new Int32Array(cw * ch).fill(-1);
        for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
            const v = bin[off + y * w + x];
            if (!v) continue;
            const rgb = (pal[v * 4] << 16) | (pal[v * 4 + 1] << 8) | pal[v * 4 + 2];
            for (let d = 0; d < 4; d++) px[(2 * (cy + y) + (d >> 1)) * cw + 2 * (cx + x) + (d & 1)] = rgb;
        }
        off += w * h;
        out[name] = { w: cw, h: ch, px };
    }
    if (off !== bin.length) throw new Error(`tnt2.bin is ${bin.length} bytes, the layout says ${off}`);
    return out;
}

/// An 8-bit indexed PNG, the only kind screens/tnt2 holds.
function decodePng(buf) {
    let p = 8, w = 0, h = 0, pal = null, trns = new Uint8Array(0);
    const idat = [];
    while (p < buf.length) {
        const len = buf.readUInt32BE(p), type = buf.toString("latin1", p + 4, p + 8), d = buf.subarray(p + 8, p + 8 + len);
        p += 12 + len;
        if (type === "IHDR") {
            w = d.readUInt32BE(0); h = d.readUInt32BE(4);
            if (d[8] !== 8 || d[9] !== 3 || d[12] !== 0) throw new Error("not an 8-bit indexed, non-interlaced PNG");
        } else if (type === "PLTE") pal = d;
        else if (type === "tRNS") trns = d;
        else if (type === "IDAT") idat.push(d);
    }
    const raw = inflateSync(Buffer.concat(idat)), px = new Int32Array(w * h);
    let prev = new Uint8Array(w);
    for (let y = 0; y < h; y++) {
        const f = raw[y * (w + 1)], line = raw.subarray(y * (w + 1) + 1, (y + 1) * (w + 1)), cur = new Uint8Array(w);
        for (let x = 0; x < w; x++) {
            const a = x ? cur[x - 1] : 0, b = prev[x], c = x ? prev[x - 1] : 0;
            const pa = Math.abs(b - c), pb = Math.abs(a - c), pc = Math.abs(a + b - 2 * c);
            const pred = [0, a, b, (a + b) >> 1, pa <= pb && pa <= pc ? a : pb <= pc ? b : c][f];
            cur[x] = (line[x] + pred) & 255;
            const alpha = cur[x] < trns.length ? trns[cur[x]] : 255;
            if (alpha !== 0 && alpha !== 255) throw new Error(`palette entry ${cur[x]} is partly transparent`);
            px[y * w + x] = alpha ? (pal[cur[x] * 3] << 16) | (pal[cur[x] * 3 + 1] << 8) | pal[cur[x] * 3 + 2] : -1;
        }
        prev = cur;
    }
    return { w, h, px };
}

async function fromRemake(dir) {
    const out = {};
    for (const [name] of LAYOUT) out[name] = decodePng(await readFile(`${dir}/screens/tnt2/${name}.png`));
    return out;
}

// ---- the original, replayed at canvas resolution ----------------------------------
function makeOriginal(img, text) {
    const s = { draws: 0, blue: -640, brown: -640, green: -640, blueSpeed: -2, brownSpeed: -4, greenSpeed: brk === "green" ? -5 : -6, scrollSpeed: 2, select: 1 };
    // onResetEvent: scrolltext.init(maincanvas 640x400, font 64x40 from 32, scrollSpeed, no sinparam, 0, mainscrollerPos 0)
    const sc = { speed: s.scrollSpeed, scroffset: 0, wide: Math.ceil(640 / 64) + 1, letters: [] };
    for (let i = 0; i <= sc.wide; i++) sc.letters.push({ posx: Math.ceil(sc.wide * 64 + i * 64), ltr: text.charCodeAt(sc.scroffset++) });
    const wrap = (v) => (v > 0 ? -640 : v < -640 ? 0 : v);

    s.update = (pressed) => {
        s.blue = wrap(s.blue + s.blueSpeed);
        s.brown = wrap(s.brown + s.brownSpeed);
        s.green = wrap(s.green + s.greenSpeed);
        sc.speed = s.scrollSpeed;
        if (pressed("1")) s.select = 1;
        else if (pressed("2")) s.select = 2;
        else if (pressed("3")) s.select = 3;
        else if (pressed("4")) s.select = 4;
        else if (pressed("left") || pressed("right")) {
            const left = pressed("left");
            if (s.select === 1) s.blueSpeed = left ? -2 : 2;
            else if (s.select === 2) left ? s.brownSpeed-- : s.brownSpeed++;
            else if (s.select === 3) left ? s.greenSpeed-- : s.greenSpeed++;
            else if (s.select === 4) { if (left && s.scrollSpeed < 9) s.scrollSpeed++; if (!left && s.scrollSpeed > 0) s.scrollSpeed--; }
        }
    };

    s.draw = (render) => {
        for (const l of sc.letters) {
            l.posx -= sc.speed;
            if (l.posx <= -64) {
                l.posx = sc.wide * 64 + (l.posx + 64);
                l.ltr = text.charCodeAt(sc.scroffset++);
                if (sc.scroffset > text.length - 1) sc.scroffset = 0;
            }
        }
        s.draws++;
        if (!render) return null;
        const canvas = new Int32Array(640 * 400).fill(0); // maincanvas.fill('#000000')
        const draw = (im, dx, dy, sx = 0, sy = 0, sw = im.w, sh = im.h) => {
            for (let y = Math.max(0, dy); y < Math.min(400, dy + sh); y++)
                for (let x = Math.max(0, dx); x < Math.min(640, dx + sw); x++) {
                    const v = im.px[(sy + y - dy) * im.w + sx + x - dx];
                    if (v >= 0) canvas[y * 640 + x] = v;
                }
        };
        draw(img.overlay2, 0, 0);
        for (const [name, x] of [["blueLayer", s.blue], ["brownLayer", s.brown], ["greenLayer", s.green]]) {
            draw(img[name], x, 0);
            draw(img[name], x + 640, 0);
        }
        const temp = sc.letters.map((l, j) => ({ j, posx: l.posx })).sort((a, b) => a.posx - b.posx);
        for (const { j } of temp) {
            const nb = sc.letters[j].ltr - 32;
            draw(img.fonts, sc.letters[j].posx, 180, (nb % 10) * 64, Math.floor(nb / 10) * 40, 64, 40);
        }
        draw(img.overlay, 0, 0);
        return canvas;
    };
    return s;
}

// The key script, by screen frame: every band and the scroller get changed,
// with the else-if priority exercised (left and right held on one frame) and odd
// canvas speeds reached. host: ["key", codepoint] or ["input", direction].
const SCRIPT = new Map([
    [100, [["key", 0x32]]],                                   // '2': brown
    [110, [["input", 2]]], [111, [["input", 3]]],             // left, then right: brown -4 -> -5 -> -6 -> -5
    [200, [["key", 0x63]]],                                   // 'c': green
    [210, [["input", 3]]], [211, [["input", 3]]], [212, [["input", 3]]], // green -6 -> -2
    [300, [["key", 0x34]]],                                   // '4': the scroller
    [310, [["input", 2]]],                                    // 2 -> 4
    [350, [["input", 3]]], [351, [["input", 2]]],             // 4 -> 3 -> 4 -> 3: odd
    [450, [["key", 0x41]]],                                   // 'A': blue
    [460, [["input", 3]]],                                    // blue -2 -> +2
    [900, [["key", 0x44]]],                                   // 'D': the scroller
    ...Array.from({ length: 7 }, (_, i) => [910 + i, [["input", 3]]]), // down to 0, clamped
]);
const ACTION = (ev) => ev[0] === "input" ? (ev[1] === 2 ? "left" : "right") : ({ a: "1", b: "2", c: "3", d: "4" })[String.fromCharCode(ev[1]).toLowerCase()] ?? String.fromCharCode(ev[1]);
const pressedAt = (k) => (name) => {
    for (let f = k - HOLD + 1; f <= k; f++) for (const ev of SCRIPT.get(f) ?? []) if (ACTION(ev) === name) return true;
    return false;
};
const SHOTS = [0, 1, 2, 60, 61, 105, 113, 215, 305, 355, 470, 800, 920, 921, 1234, 3000];

// ---- the machine ----------------------------------------------------------------
async function boot(cart) {
    const memory = new WebAssembly.Memory({ initial: PAGES, maximum: PAGES });
    let demo;
    const machine = (await WebAssembly.instantiate(await readFile("docs/machine-video.wasm"), {
        env: { memory, hblDispatch: (id, p, l, x) => demo.hblDispatch(id, p, l, x) },
    })).instance.exports;
    const romBytes = await readFile("docs/rom.wasm");
    const rom = (await WebAssembly.instantiate(romBytes, {
        env: { memory, hwVideoBase: machine.hwVideoBase, hwBlit: machine.hwBlit },
    })).instance.exports;
    machine.hwSetRomHigh(romRam(romBytes).high ?? 0);
    const cartBytes = await readFile(cart);
    const env = { memory, ...rom };
    for (const k of Object.keys(machine)) if (k.startsWith("hw")) env[k] = machine[k];
    for (const imp of WebAssembly.Module.imports(new WebAssembly.Module(cartBytes)))
        if (imp.module === "env" && !(imp.name in env)) env[imp.name] = () => {};
    demo = (await WebAssembly.instantiate(cartBytes, { env })).instance.exports;
    machine.hwSetCartHigh(cartRam(cartBytes).high ?? 0);
    machine.hwInit();
    demo.boot();
    demo.skipBoot();
    return { memory, machine, demo };
}

async function sndhPlay(name, tune) {
    const memory = new WebAssembly.Memory({ initial: AUDIO_PAGES, maximum: AUDIO_PAGES });
    const machine = (await WebAssembly.instantiate(await readFile("docs/machine-audio.wasm"), { env: { memory } })).instance.exports;
    const env = { memory };
    for (const n of Object.keys(machine)) if (n.startsWith("machine")) env[n] = machine[n];
    const volWrites = [0, 0, 0];
    env.machineYmWrite = (r, v) => { if (r >= 8 && r <= 10) volWrites[r - 8]++; return machine.machineYmWrite(r, v); };
    const audio = (await WebAssembly.instantiate(await readFile("docs/demo-audio.wasm"), { env })).instance.exports;
    audio.audioInit();
    const bytes = new Uint8Array(await readFile(`docs/music/${name}`));
    if (bytes.length > audio.audioSongCapacity() || (new Uint8Array(memory.buffer, audio.audioSongPtr(), bytes.length).set(bytes), !audio.audioLoadSndh(bytes.length)))
        return { loaded: false };
    audio.audioSndhPlay(tune);
    volWrites.fill(0);
    const SR = 44100, BLOCK = 882, SECONDS = 10;
    let peak = 0, secPeak = 0, silent = 0;
    for (let done = 0; done < SECONDS * SR; done += BLOCK) {
        audio.audioRender(BLOCK);
        for (const v of new Float32Array(memory.buffer, machine.audioLeftPtr(), BLOCK)) { peak = Math.max(peak, Math.abs(v)); secPeak = Math.max(secPeak, Math.abs(v)); }
        if ((done / BLOCK + 1) % 50 === 0) { if (secPeak <= 0.01) silent++; secPeak = 0; }
    }
    return { loaded: true, peak, silent, volWrites, mode: audio.audioMode(), stuckPc: audio.audioSndhStuckPc() };
}

function png(rgbAt) {
    const crcTable = Array.from({ length: 256 }, (_, n) => { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1; return c >>> 0; });
    const crc = (b) => { let c = 0xffffffff; for (const v of b) c = crcTable[(c ^ v) & 0xff] ^ (c >>> 8); return (c ^ 0xffffffff) >>> 0; };
    const raw = Buffer.alloc(200 * 961);
    for (let y = 0; y < 200; y++) for (let x = 0; x < 320; x++) raw.set(rgbAt(x, y).slice(0, 3), y * 961 + 1 + x * 3);
    const chunk = (type, data) => {
        const b = Buffer.alloc(12 + data.length);
        b.writeUInt32BE(data.length, 0); b.write(type, 4, "latin1"); data.copy(b, 8);
        b.writeUInt32BE(crc(b.subarray(4, 8 + data.length)), 8 + data.length);
        return b;
    };
    const ihdr = Buffer.alloc(13); ihdr.writeUInt32BE(320, 0); ihdr.writeUInt32BE(200, 4); ihdr.set([8, 2, 0, 0, 0], 8);
    return Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk("IHDR", ihdr), chunk("IDAT", deflateSync(raw)), chunk("IEND", Buffer.alloc(0))]);
}

const errors = [];
const img = remake ? await fromRemake(remake) : await fromBin();
if (remake) { // the conversion itself: tnt2.bin, doubled back, is the remake's PNGs
    const bin = await fromBin();
    const diffs = LAYOUT.map(([name]) => img[name].px.reduce((n, v, i) => n + (v !== bin[name].px[i]), 0) + Math.abs(img[name].w * img[name].h - bin[name].px.length));
    console.log(`union_tnt2 assets: tnt2.bin vs ${remake}/screens/tnt2/*.png: ${LAYOUT.map(([n], i) => `${n} ${diffs[i]}`).join(", ")} px differ`);
    if (diffs.some((d) => d)) errors.push("tnt2.bin is not the remake's PNGs halved");
}
const text = await readFile(TEXT_FILE, "latin1");
const { memory, machine, demo } = await boot(cartPath);
const W = machine.hwPhysWidth(), H = machine.hwPhysHeight(), dec = new TextDecoder();
let song = null, tune = 0, cartMs = 0, renderMs = 0, timed = 0, screenFrame = -1;

function step() {
    for (const [kind, v] of SCRIPT.get(screenFrame) ?? []) demo[kind](v);
    const t0 = performance.now();
    demo.frame(1000 / 60);
    const ms = performance.now() - t0;
    if (demo.pollSongRequest()) { song = dec.decode(new Uint8Array(memory.buffer, demo.songNamePtr(), demo.songNameLen())); tune = demo.songTune(); }
    return ms;
}
function screen() {
    let planes = 0;
    for (let p = 0; p < machine.hwPlanesNumber(); p++) if (demo.isPlaneEnabled(p)) planes++;
    const t0 = performance.now();
    machine.hwRenderPlane(0);
    const ms = performance.now() - t0;
    const px = new Uint8Array(memory.buffer, machine.hwPhysicalPtr(), W * H * 4);
    return { planes, ms, at: (x, y) => { const o = ((y + TOP) * W + LEFT + x * 2) * 4; return [px[o], px[o + 1], px[o + 2], px[o + 3]]; } };
}

// 1. the loader: run until row 0 is opaque (the panel's top rows are blank)
const DEPACK_FRAMES = Math.ceil(221199 / (8 * 280)); // tnt2.bin at DEPACK_BYTES_PER_LINE = 8
let inkFrames = 0, maxInk = 0, first = -1;
for (let f = 1; f <= 400 && first < 0; f++) {
    step();
    const sh = screen();
    let ink = 0, row0 = 0;
    for (let y = 0; y < 200; y++) for (let x = 0; x < 320; x++) {
        const [r, g, b, a] = sh.at(x, y);
        if (a && r === TEX_INK[0] && g === TEX_INK[1] && b === TEX_INK[2]) ink++;
        if (y === 0 && a) row0++;
    }
    if (row0 === 320) first = f;
    else {
        if (ink) inkFrames++;
        if (ink > maxInk) { maxInk = ink; if (f > DEPACK_FRAMES - 10) await writeFile(`${outDir}/union_tnt2-loader.png`, png(sh.at)); }
    }
}
if (first < 0) errors.push("the screen never started");
else if (Math.abs(first - DEPACK_FRAMES) > 1) errors.push(`the screen started at frame ${first}, the depack pacing says ${DEPACK_FRAMES}`);
if (inkFrames < DEPACK_FRAMES / 2 || maxInk < 2000) errors.push(`the TEX loader panel barely showed: ink on ${inkFrames} frames, at most ${maxInk} px`);

// 2. the screen against the replay; screen frame k = the (k+1)-th update()+draw()
const st = makeOriginal(img, text);
const seen = new Map();
screenFrame = 0;
for (const target of SHOTS) {
    while (screenFrame < target) {
        screenFrame++;
        const ms = step();
        if (screenFrame > 30) { cartMs += ms; timed++; }
    }
    let canvas;
    while (st.draws <= target) { st.update(pressedAt(st.draws)); canvas = st.draw(st.draws === target); }
    const sh = screen();
    if (target > 30) renderMs += sh.ms;
    if (sh.planes !== 1) errors.push(`screen frame ${target}: ${sh.planes} planes enabled, the screen uses one`);
    let wrong = 0, firstWrong = null;
    for (let y = 0; y < 200; y++) for (let x = 0; x < 320; x++) {
        const v = canvas[2 * y * 640 + 2 * x], [r, g, b, a] = sh.at(x, y);
        if (a !== 255 || r !== v >> 16 || g !== ((v >> 8) & 255) || b !== (v & 255)) {
            wrong++;
            firstWrong ??= `(${x},${y}) got ${r},${g},${b},${a} want ${v >> 16},${(v >> 8) & 255},${v & 255}`;
        }
    }
    if (wrong) errors.push(`screen frame ${target}: ${wrong} px off the screen.js replay, first ${firstWrong}`);
    seen.set(target, canvas);
    if ([0, 113, 355, 1234].includes(target)) {
        await writeFile(`${outDir}/union_tnt2-${target}.png`, png(sh.at));
        await writeFile(`${outDir}/union_tnt2-${target}-replay.png`, png((x, y) => { const v = canvas[2 * y * 640 + 2 * x]; return [v >> 16, (v >> 8) & 255, v & 255]; }));
    }
}
const moved = (a, b, y0, y1) => seen.get(a).subarray(y0 * 640, y1 * 640).some((v, i) => v !== seen.get(b)[y0 * 640 + i]);
if (!moved(60, 61, 0, 60)) errors.push("frames 60/61: the bands do not move");
const speeds = [st.blueSpeed, st.brownSpeed, st.greenSpeed, st.scrollSpeed].join(",");
if (speeds !== "2,-5,-2,0") errors.push(`the key script left speeds ${speeds}, it is written to reach 2,-5,-2,0`);

// 3. the music
if (song !== MUSIC) errors.push(`song request ${JSON.stringify(song)}, wanted "${MUSIC}"`);
const music = song === MUSIC ? await sndhPlay(song, tune || 1) : { loaded: false };
if (!music.loaded) errors.push(`${MUSIC} did not load`);
else if (music.mode !== MODE_SNDH || music.stuckPc || !(music.peak > 0.01) || music.silent || !music.volWrites.every((n) => n > 0))
    errors.push(`${MUSIC}: mode ${music.mode}, stuck PC ${music.stuckPc}, peak ${music.peak.toFixed(4)}, silent seconds ${music.silent}, volume writes ${music.volWrites}`);

// 4. leaving, cost
if (demo.pollCartRequest() !== 0) errors.push("the screen asks for a cart before being told to leave");
demo.key(0x20);
const req = demo.pollCartRequest();
const tag = dec.decode(new Uint8Array(memory.buffer, demo.getCartTagPtr(), demo.getCartTagLen()));
if (req !== 1 || tag !== "union_demo") errors.push(`Space asked for cart request ${req} "${tag}", wanted 1 "union_demo"`);
demo.key(K_ESC);
if (demo.pollCartRequest() !== 1) errors.push("Escape does not ask for the hub");
const perFrame = cartMs / timed, perRender = renderMs / (SHOTS.filter((f) => f > 30).length);
if (perFrame > 2) errors.push(`cart update+render takes ${perFrame.toFixed(3)} ms a frame`);

if (errors.length) {
    console.error(`union_tnt2: WRONG${brk ? ` (--break ${brk})` : ""} (${cartPath})\n  ${errors.slice(0, 12).join("\n  ")}`);
    process.exit(1);
}
console.log(`union_tnt2: TEX loader depacked in ${first} frames (ink on ${inkFrames}, up to ${maxInk} px); ` +
    `screen = screen.js replay (${remake ? "remake PNGs" : "tnt2.bin"}) at frames ${SHOTS.join(",")} with the key script; ` +
    `${MUSIC} tune ${tune} plays (peak ${music.peak.toFixed(4)}, 0 silent s, voices ${music.volWrites.join("/")}); Space/Esc -> union_demo; ` +
    `${perFrame.toFixed(3)} ms cart + ${perRender.toFixed(3)} ms hwRenderPlane a frame; shots in ${outDir}`);
