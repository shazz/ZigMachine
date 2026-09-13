// Headless Union Demo MULTIFAKE (TCB3) check: the loader really depacks, then
// the screen matches screen.js, pixel for pixel, at every sampled frame.
//
// 1. Loader. The cart starts on the TEX loader panel (depack fx = tex_loader):
//    the panel's ink (#C0A000) must be on screen while the data depacks, the
//    depack must take the ~94 frames its pacing gives, and the screen must
//    start on the frame it ends.
// 2. Screen. screen.js (89-134), codef_core.js drawTile/drawPart and
//    codef_scrolltext.js (44-174) are replayed here in CANVAS units, from the
//    source and not from the scene, then halved the way the scene documents:
//      mountains  bgpos = (bgpos - bgspeed) % 256; ST column X shows column
//                 X + floor(-bgpos/2 + 0.5); rows 0..15 at 5i, 16..31 at 5i+42
//      THE        scale(1, sin(the)) about (300,176): ST row Y samples the
//                 canvas row under its centre, 16 + (2Y+1-176)/s, halved
//      CAREBEARS  canvas row 2k at halve(16 + sin(logosinx+0.2k)*20), 97+k
//      scroller   letters at floor((posx-32)/2), halve(sin(myvalue)*120+224-32),
//                 coloured by rasters.png's row ('source-in')
//    where halve(c) = floor(round(c)/2). Any drift in a table, increment,
//    order or rounding shows up as wrong pixels.
// 3. The song request names the SNDH, Escape asks for the hub, and a frame
//    leaves 60 fps headroom.
//
//   node apps/union_multifake_headless.mjs [outdir] [cart.wasm]
import { readFile, writeFile, mkdir } from "node:fs/promises";
import { performance } from "node:perf_hooks";
import { deflateSync } from "node:zlib";
import { cartRam, romRam } from "../docs/wasm_hiwater.js";

const PAGES = 112; // SHARED_PAGES in machine/sdk/memmap.zig
const TOP = 40, LEFT = 80; // ST (0,0) in the physical frame (x doubled)
const ASSETS = "apps/zig/assets/screens/union_multifake";
const SCREEN_FRAMES = [0, 1, 2, 60, 61, 200, 1234, 3000];
const DEPACK_FRAMES = Math.ceil(156511 / (6 * 280)); // DEPACK_BYTES_PER_LINE = 6
const TEX_INK = [0xc0, 0xa0, 0x00];
const MUSIC = "union/thundercats.sndh";
const K_ESC = 0xe012;

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

// ---- assets: multifake.bin's layout (union_multifake/assets.zig) ----------
const bin = new Uint8Array(await readFile(`${ASSETS}/multifake.bin`));
const pal = new Uint8Array(await readFile(`${ASSETS}/pal.dat`));
const TEXT = await readFile(`${ASSETS}/scrolltext.txt`, "latin1");
let at = 0;
const take = (w, h) => { const img = { px: bin.subarray(at, at + w * h), w, h }; at += w * h; return img; };
const A = { mountains: take(512, 160), logo: take(303, 25), the: take(80, 16), font: take(512, 128), rasters: take(200, 1).px };
if (at !== bin.length) throw new Error(`multifake.bin is ${bin.length} bytes, layout says ${at}`);

// ---- the original, replayed in canvas units ---------------------------------
const halve = (c) => Math.floor(Math.round(c) / 2);
const BGSPEED = [8, 7.5, 7, 6.5, 6, 5.5, 5, 4.5, 4, 3.5, 3, 2.5, 2, 1.5, 1, 0.5, 0.5, 1, 1.5, 2, 2.5, 3, 3.5, 4, 4.5, 5, 5.5, 6, 6.5, 7, 7.5, 8];

function makeOriginal() {
    const st = { draws: 0, bgpos: new Array(32).fill(0), the: 0, logosinx: 0 };
    // scrolltext.init(scrollcanvas 640x400, font 64x64, 1, [{myvalue:0, amp:120, inc:0.6, offset:-0.04}])
    const sp = { myvalue: 0, amp: 120, inc: 0.6, offset: -0.04 };
    const wide = Math.ceil(640 / 64) + 1;
    const letters = [];
    let scroffset = 0;
    for (let i = 0; i <= wide; i++) letters.push({ posx: Math.ceil(wide * 64 + i * 64), ltr: TEXT.charCodeAt(scroffset++) });

    st.draw = () => {
        const map = new Uint8Array(320 * 200).fill(1); // maincanvas.fill('#000000')
        const put = (x, y, v) => { if (x >= 0 && x < 320 && y >= 0 && y < 200) map[y * 320 + x] = v; };
        for (let i = 0; i < 32; i++) {
            st.bgpos[i] = (st.bgpos[i] - BGSPEED[i]) % 256;
            const y0 = i < 16 ? i * 10 : i * 10 + 84, shift = Math.floor(-st.bgpos[i] / 2 + 0.5);
            for (let r = 0; r < 5; r++) for (let x = 0; x < 320; x++)
                put(x, y0 / 2 + r, A.mountains.px[(i * 5 + r) * 512 + x + shift]);
        }
        const s = Math.sin(st.the);
        if (s !== 0) for (let y = 0; y < 200; y++) {
            const v = 16 + (2 * y + 1 - 176) / s;
            if (!(v >= 0 && v < 32)) continue;
            for (let x = 0; x < 80; x++) { const p = A.the.px[Math.floor(v / 2) * 80 + x]; if (p) put(110 + x, y, p); }
        }
        st.the += 0.1;
        const old = st.logosinx;
        for (let i = 0; i < 50; i++) {
            const x = 16 + Math.sin(st.logosinx) * 20;
            if (i % 2 === 0) for (let c = 0; c < 303; c++) { const p = A.logo.px[(i / 2) * 303 + c]; if (p) put(halve(x) + c, 97 + i / 2, p); }
            st.logosinx += 0.1;
        }
        st.logosinx = old + 0.1;
        // scrolltext_horizontal.draw(240-16)
        let oldvalue = sp.myvalue;
        for (const l of letters) {
            l.posx -= 1;
            if (l.posx <= -64) {
                l.posx = wide * 64 + (l.posx + 64);
                oldvalue += sp.inc;
                l.ltr = TEXT.charCodeAt(scroffset++);
                if (scroffset > TEXT.length - 1) scroffset = 0;
            }
        }
        sp.myvalue = oldvalue;
        const order = letters.map((l, j) => ({ j, posx: l.posx })).sort((a, b) => a.posx - b.posx);
        for (const { j } of order) {
            const prov = Math.sin(sp.myvalue) * sp.amp, nb = letters[j].ltr - 32;
            const dx = Math.floor((letters[j].posx - 32) / 2), dy = halve(prov + 224 - 32);
            for (let r = 0; r < 32; r++) for (let c = 0; c < 32; c++) {
                const y = dy + r;
                if (A.font.px[((nb >> 4) * 32 + r) * 512 + (nb % 16) * 32 + c] && y >= 0 && y < 200) put(dx + c, y, A.rasters[y]);
            }
            sp.myvalue += sp.inc;
        }
        sp.myvalue = oldvalue + sp.offset;
        st.draws++;
        return map;
    };
    return st;
}

// ---- the cart ------------------------------------------------------------
const out = process.argv[2];
if (out) await mkdir(out, { recursive: true });
const { memory, machine, demo } = await boot(process.argv[3] || "docs/demo-union_multifake.wasm");
const W = machine.hwPhysWidth(), H = machine.hwPhysHeight();
const errors = [];
const dec = new TextDecoder();
let song = null, cartMs = 0, frames = 0;
let screenFrame = -1; // -1 while the loader runs
const warm = []; // screen frames past 1234: JIT warm-up excluded

function step() {
    const t0 = performance.now();
    demo.frame(1000 / 60);
    const ms = performance.now() - t0;
    cartMs += ms;
    frames++;
    if (screenFrame > 1234) warm.push(ms);
    if (demo.pollSongRequest()) song = dec.decode(new Uint8Array(memory.buffer, demo.songNamePtr(), demo.songNameLen()));
}
function screen() {
    machine.hwRenderPlane(0);
    return new Uint8Array(memory.buffer, machine.hwPhysicalPtr(), W * H * 4);
}
const rgbAt = (px, x, y) => { const o = ((y + TOP) * W + LEFT + x * 2) * 4; return [px[o], px[o + 1], px[o + 2], px[o + 3]]; };

async function png(name, px) {
    const raw = Buffer.alloc(200 * (1 + 320 * 3));
    for (let y = 0; y < 200; y++) for (let x = 0; x < 320; x++) {
        const [r, g, b] = rgbAt(px, x, y);
        raw.set([r, g, b], y * 961 + 1 + x * 3);
    }
    const crcTable = Array.from({ length: 256 }, (_, n) => { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1; return c >>> 0; });
    const crc = (buf) => { let c = 0xffffffff; for (const v of buf) c = crcTable[(c ^ v) & 0xff] ^ (c >>> 8); return (c ^ 0xffffffff) >>> 0; };
    const chunk = (type, data) => {
        const b = Buffer.alloc(12 + data.length);
        b.writeUInt32BE(data.length, 0); b.write(type, 4, "latin1"); data.copy(b, 8);
        b.writeUInt32BE(crc(b.subarray(4, 8 + data.length)), 8 + data.length);
        return b;
    };
    const ihdr = Buffer.alloc(13); ihdr.writeUInt32BE(320, 0); ihdr.writeUInt32BE(200, 4); ihdr.set([8, 2, 0, 0, 0], 8);
    await writeFile(`${out}/${name}.png`, Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]),
        chunk("IHDR", ihdr), chunk("IDAT", deflateSync(raw)), chunk("IEND", Buffer.alloc(0))]));
}

// 1. the loader: run until row 0 shows the screen (the panel's top rows are blank)
let inkFrames = 0, maxInk = 0, first = -1;
for (let f = 1; f <= 400 && first < 0; f++) {
    step();
    const px = screen();
    let ink = 0, row0 = 0;
    for (let y = 0; y < 200; y++) for (let x = 0; x < 320; x++) {
        const [r, g, b, a] = rgbAt(px, x, y);
        if (a && r === TEX_INK[0] && g === TEX_INK[1] && b === TEX_INK[2]) ink++;
        if (y === 0 && a) row0++;
    }
    if (row0 === 320) first = f;
    else {
        if (ink) inkFrames++;
        if (ink > maxInk) { maxInk = ink; if (out && f > DEPACK_FRAMES - 10) await png("union_multifake-loader", px); }
    }
}
if (first < 0) errors.push("the screen never started");
else if (Math.abs(first - DEPACK_FRAMES) > 1) errors.push(`the screen started at frame ${first}, the depack pacing says ${DEPACK_FRAMES}`);
if (inkFrames < DEPACK_FRAMES / 2 || maxInk < 2000) errors.push(`the TEX loader panel barely showed: ink on ${inkFrames} frames, at most ${maxInk} px`);

// 2. the screen against the replay; screen frame k = the (k+1)-th draw()
const st = makeOriginal();
const seen = new Map();
screenFrame = 0;
for (const target of SCREEN_FRAMES) {
    while (screenFrame < target) { step(); screenFrame++; }
    let map;
    while (st.draws <= target) map = st.draw();
    const px = screen();
    let wrong = 0;
    for (let y = 0; y < 200; y++) for (let x = 0; x < 320; x++) {
        const v = map[y * 320 + x], [r, g, b, a] = rgbAt(px, x, y);
        if (a !== 255 || r !== pal[v * 4] || g !== pal[v * 4 + 1] || b !== pal[v * 4 + 2]) wrong++;
    }
    if (wrong) errors.push(`screen frame ${target}: ${wrong} px off the screen.js replay`);
    seen.set(target, map);
    if (out && [0, 200, 1234].includes(target)) await png(`union_multifake-${target}`, px);
}
const moved = (a, b, y0, y1) => seen.get(a).subarray(y0 * 320, y1 * 320).some((v, i) => v !== seen.get(b)[y0 * 320 + i]);
if (!moved(60, 61, 0, 80)) errors.push("frames 60/61: the top mountains do not move");
if (!moved(60, 61, 80, 97)) errors.push("frames 60/61: THE does not stretch");
if (!moved(60, 200, 97, 122)) errors.push("frames 60/200: CAREBEARS does not sway");

// 3. music, the way out, the frame cost
if (song !== MUSIC) errors.push(`song request ${JSON.stringify(song)}, wanted "${MUSIC}"`);
demo.key(K_ESC);
const req = demo.pollCartRequest();
const tag = dec.decode(new Uint8Array(memory.buffer, demo.getCartTagPtr(), demo.getCartTagLen()));
if (req !== 1 || tag !== "union_demo") errors.push(`Escape asked for cart request ${req} "${tag}", wanted 1 "union_demo"`);
const perFrame = cartMs / frames;
if (perFrame > 4) errors.push(`cart takes ${perFrame.toFixed(3)} ms/frame`);
warm.sort((a, b) => a - b);
const warmMedian = warm.length ? warm[warm.length >> 1] : NaN;

if (errors.length) {
    console.error(`union_multifake: WRONG\n  ${errors.slice(0, 12).join("\n  ")}`);
    process.exit(1);
}
console.log(`union_multifake: loader depacked in ${first} frames (ink on ${inkFrames}, up to ${maxInk} px); ` +
    `screen = screen.js replay at frames ${SCREEN_FRAMES.join(",")}; song ${song}; Esc -> union_demo; ${perFrame.toFixed(3)} ms/frame mean, ${warmMedian.toFixed(3)} ms warm median`);
