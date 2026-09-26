// Headless TEX check (CODEF screen 14): stars, logo, sprites and scrolltext all
// sit where screen.js puts them, frame by frame.
//
// This replays the original's JavaScript in canvas units, halves it the way the
// scene documents, and rebuilds the expected index map of three planes:
//   plane 0  starfield2D_dot (codef_starfield.js:99-121): 25 stars at -5.0 and 30
//            at -1.2 on 640x190, seeded by the scene's xorshift32, plotted then
//            moved, one ST pixel per 2x2 dot;
//   plane 1  the logo at 320 + sin(sinx)*(100*sin(inc)) - 208 (screen.js:110-112)
//            under the eleven sprites at 305 + 306*sin(p), 86 + 84*cos(1.5p);
//   plane 3  scrolltext_horizontal (codef_scrolltext.js:57-133) at 3 canvas px a
//            frame, masked by the font background.
// Each is checked pixel for pixel at several frames; on top of that the sprite
// chain, the logo and the scroller must move between consecutive frames, the
// star layers must keep their counts, and a frame must leave 60 fps headroom.
//
//   node apps/tex_headless.mjs [outdir] [cart.wasm]
import { readFile, writeFile } from "node:fs/promises";
import { cartRam, romRam } from "../docs/wasm_hiwater.js";

const PAGES = 112; // SHARED_PAGES in machine/sdk/memmap.zig
const TOP = 40, LEFT = 80; // the visible window in the physical frame (x doubled)
const FRAMES = [1, 60, 61, 200, 1234, 3600];
const ASSETS = "apps/zig/assets/screens/the_union/";
const SPRITES = ["delta", "delta", "delta", "h", "o", "w", "d", "y", "delta", "delta", "delta"];
const TEXT = "THE EXCEPTIONS PROUDLY PRESENT THIS NEW GAME CRACKED BY HOWDY FROM THE EXCEPTIONS MEMBER OF THE UNION     LET WRAP              ";
const STAR_SEED = 0x2545f491;
const LAYERS = [{ nb: 25, speedx: -5.0, color: 2 }, { nb: 30, speedx: -1.2, color: 1 }];
const SCROLL_POS = 142, BACK_POS = 113;

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

    const noop = () => {};
    const cartBytes = await readFile(cart);
    const env = {
        memory,
        hwVideoBase: machine.hwVideoBase, hwBlit: machine.hwBlit,
        hwRamBase: machine.hwRamBase, hwRamTop: machine.hwRamTop,
        hwRamSize: machine.hwRamSize, hwRamUsed: machine.hwRamUsed, hwRamFree: machine.hwRamFree,
        hwRamAlloc: machine.hwRamAlloc, hwRamMark: machine.hwRamMark,
        hwRamRelease: machine.hwRamRelease, hwRamAllocFailures: machine.hwRamAllocFailures,
        hwRomRamBase: machine.hwRomRamBase, hwRomRamTop: machine.hwRomRamTop,
        hwRomRamSize: machine.hwRomRamSize, hwRomRamUsed: machine.hwRomRamUsed,
        hwRomRamFree: machine.hwRomRamFree,
        ...rom,
    };
    for (const imp of WebAssembly.Module.imports(new WebAssembly.Module(cartBytes)))
        if (imp.module === "env" && !(imp.name in env)) env[imp.name] = noop;
    demo = (await WebAssembly.instantiate(cartBytes, { env })).instance.exports;
    machine.hwSetCartHigh(cartRam(cartBytes).high ?? 0);
    machine.hwInit();
    demo.boot();
    demo.skipBoot();
    return { memory, machine, demo };
}

// ---- the original, replayed in canvas units --------------------------------
const halve = (c) => Math.floor(Math.round(c) / 2);

function makeOriginal() {
    let seed = STAR_SEED;
    const random = () => {
        seed = (seed ^ (seed << 13)) >>> 0; seed = (seed ^ (seed >>> 17)) >>> 0; seed = (seed ^ (seed << 5)) >>> 0;
        return seed / 4294967296;
    };
    const stars = [];
    for (const l of LAYERS) for (let j = 0; j < l.nb; j++) stars.push({ x: random() * 640, y: random() * 190, drawn: 0, ...l });
    const letters = Array.from({ length: 12 }, (_, i) => ({ x: 11 * 64 + i * 64, ch: TEXT.charCodeAt(i) }));
    const st = { frame: 0, stars, letters, offset: 12, sinx: 0, inc: 0, phase: SPRITES.map((_, i) => 0.3 * (i + 1)) };
    st.go = () => {
        st.frame++;
        for (const s of stars) {
            s.drawn = s.x; s.x += s.speedx;
            if (s.x > 640) s.x = 0;
            if (s.x < 0) s.x = 640;
        }
        st.sinx += 0.13; st.inc += 0.008;
        st.phase = st.phase.map((p) => p + 0.04);
        for (const l of letters) {
            l.x -= 3;
            if (l.x <= -64) {
                l.x = 11 * 64 + (l.x + 64); l.ch = TEXT.charCodeAt(st.offset++);
                if (st.offset > TEXT.length - 1) st.offset = 0;
            }
        }
    };
    st.logoX = () => halve(320 + Math.sin(st.sinx) * (100 * Math.sin(st.inc)) - 208);
    return st;
}

function paint(map, img, w, part, dx, dy, key0) {
    const h = part ? part.h : img.length / w, y0 = part ? part.y : 0;
    for (let r = 0; r < h; r++) for (let c = 0; c < w; c++) {
        const v = img[(y0 + r) * w + c], x = dx + c, y = dy + r;
        if ((key0 && v === 0) || x < 0 || x >= 320 || y < 0 || y >= 200) continue;
        map[y * 320 + x] = v;
    }
}

function expectStars(st) {
    const map = new Uint8Array(320 * 200);
    for (const s of st.stars) {
        const x = Math.floor(Math.floor(s.drawn + 1) / 2), y = Math.floor(Math.floor(s.y + 1) / 2);
        if (x >= 0 && x < 320 && y < 95) map[y * 320 + x] = s.color;
    }
    return map;
}

function expectLogoSprites(st, a) {
    const map = new Uint8Array(320 * 200);
    paint(map, a.logo, 208, null, st.logoX(), 0, true);
    st.phase.forEach((p, i) => paint(map, a.sprites[i], 16, null, halve(305 + 306 * Math.sin(p)), halve(86 + 84 * Math.cos(p * 1.5)), true));
    return map;
}

function expectScroll(st, a) {
    const map = new Uint8Array(320 * 200);
    for (const l of st.letters) paint(map, a.font, 32, { y: (l.ch - 32) * 17, h: 17 }, Math.floor(l.x / 2), SCROLL_POS, true);
    for (let i = SCROLL_POS * 320, t = (SCROLL_POS - BACK_POS) * 320; i < (SCROLL_POS + 17) * 320; i++, t++) map[i] &= a.back[t];
    return map;
}

// ---- the cart ----------------------------------------------------------------
/// Compare a plane with an expected index map: index 0 (and the plane's other
/// transparent entries) must be clear, every other index its palette colour.
function check(px, W, map, pal, clear, name, frame, errors) {
    let wrong = 0, ink = 0;
    for (let y = 0; y < 200; y++) for (let x = 0; x < 320; x++) {
        const v = map[y * 320 + x], o = ((y + TOP) * W + LEFT + x * 2) * 4;
        if (clear.includes(v)) { if (px[o + 3] !== 0) wrong++; continue; }
        ink++;
        if (px[o + 3] === 0 || px[o] !== pal[v * 4] || px[o + 1] !== pal[v * 4 + 1] || px[o + 2] !== pal[v * 4 + 2]) wrong++;
    }
    if (wrong) errors.push(`frame ${frame} ${name}: ${wrong} px off the screen.js replay (${ink} ink px expected)`);
    return ink;
}

const { memory, machine, demo } = await boot(process.argv[3] || "docs/demo-tex.wasm");
const a = {
    logo: await readFile(`${ASSETS}logo.raw`), back: await readFile(`${ASSETS}back.raw`), font: await readFile(`${ASSETS}fonts.raw`),
    sprites: await Promise.all(SPRITES.map((n) => readFile(`${ASSETS}${n}.raw`))),
    logoPal: await readFile(`${ASSETS}logo_pal.dat`), bluePal: await readFile(`${ASSETS}blue_back_pal.dat`),
};
const starPal = new Uint8Array(1024);
starPal.set([0x60, 0x60, 0x60, 255], 4); starPal.set([0xe0, 0xe0, 0xe0, 255], 8);
const W = machine.hwPhysWidth(), H = machine.hwPhysHeight();
const st = makeOriginal();
const errors = [], seen = new Map();
let cartMs = 0;

for (const target of FRAMES) {
    while (st.frame < target) {
        const t0 = performance.now(); demo.frame(1000 / 60); cartMs += performance.now() - t0;
        st.go();
    }
    const maps = [expectStars(st), expectLogoSprites(st, a), null, expectScroll(st, a)];
    const got = [];
    for (const [p, pal, clear, name] of [[0, starPal, [0], "stars"], [1, a.logoPal, [0, 255], "logo+sprites"], [3, a.bluePal, [0], "scrolltext"]]) {
        machine.hwRenderPlane(p);
        const px = new Uint8Array(memory.buffer, machine.hwPhysicalPtr(), W * H * 4);
        got[p] = check(px, W, maps[p], pal, clear, name, st.frame, errors);
        if (process.argv[2]) {
            const hdr = new TextEncoder().encode(`P6\n320 200\n255\n`);
            const buf = new Uint8Array(hdr.length + 320 * 200 * 3);
            buf.set(hdr);
            for (let y = 0; y < 200; y++) for (let x = 0; x < 320; x++) for (let c = 0; c < 3; c++)
                buf[hdr.length + (y * 320 + x) * 3 + c] = px[((y + TOP) * W + LEFT + x * 2) * 4 + c];
            await writeFile(`${process.argv[2]}/tex-plane${p}-${st.frame}.ppm`, buf);
        }
    }
    // star layers keep their counts: every visible dot is one of its layer's stars
    const perLayer = LAYERS.map((l) => maps[0].filter((v) => v === l.color).length);
    if (perLayer[0] > 25 || perLayer[1] > 30 || perLayer[0] + perLayer[1] < 40)
        errors.push(`frame ${st.frame}: star layers show ${perLayer.join("+")} dots (25 + 30 stars)`);
    seen.set(st.frame, { maps, logoX: st.logoX(), letter0: st.letters[0].x, stars: st.stars.map((s) => s.drawn) });
}

// between frames 60 and 61 everything moves by the original's own step
const f60 = seen.get(60), f61 = seen.get(61);
if (f60.maps[1].every((v, i) => v === f61.maps[1][i])) errors.push("frames 60/61: the sprite layer does not move");
if (f61.letter0 - f60.letter0 !== -3 && f61.letter0 - f60.letter0 !== 765) errors.push("frames 60/61: the scroller did not move 3 canvas px");
f60.stars.forEach((x, i) => {
    const d = f61.stars[i] - x, want = st.stars[i].speedx;
    if (Math.abs(d - want) > 1e-9 && Math.abs(d - (640 + want)) > 1e-9 && f61.stars[i] !== 640) errors.push(`star ${i}: moved ${d}, not ${want}`);
});
if (errors.length === 0 && FRAMES.every((f) => seen.get(f).logoX === seen.get(1).logoX)) errors.push("the logo never sways");

const perFrame = cartMs / st.frame;
if (perFrame > 4) errors.push(`cart takes ${perFrame.toFixed(3)} ms/frame`);

if (errors.length) {
    console.error(`tex: WRONG\n  ${errors.slice(0, 12).join("\n  ")}`);
    process.exit(1);
}
console.log(`tex: stars, logo, 11 sprites and scrolltext on the screen.js replay at frames ${FRAMES.join(",")}; logo x ${FRAMES.map((f) => seen.get(f).logoX).join(",")}; ${perFrame.toFixed(3)} ms/frame`);
