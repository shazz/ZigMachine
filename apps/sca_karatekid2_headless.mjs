// Headless SCA - THE KARATE KID PART II driver (CODEF 495, apps/zig/scenes/sca_karatekid2.zig).
// Boots the sealed machine as docs/sealed-loader.js does, renders every frame and
// checks what this screen is made of, against the CODEF source's own numbers:
//   bar      the LEFT BORDER (physical x 3) on the 28 bar lines is raster.png's colours,
//            black above and below: the register shows in the border, full width
//   ink      the scroller's lit pixels on text line r carry fontraster's colour r
//   logo     every opaque logo pixel is logo.png's colour, at (82,120)
//   stars    star colours reach the bottom 40 content rows (the open bottom border)
//   node apps/sca_karatekid2_headless.mjs [outdir]
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { cartRam, romRam } from "../docs/wasm_hiwater.js";

const PAGES = 128; // must match SHARED_PAGES in machine/sdk/memmap.zig
const CART = "docs/demo-sca_karatekid2.wasm";
const TOP = 40; // physical row of content line 0 (and column 40 of content x 0)
const LEFT = 40;
const BAR_Y = 50, BAR_LINES = 28;
const TEXT_Y = 60, TEXT_LINES = 7;
const LOGO_X = 82, LOGO_Y = 120, LOGO_W = 150, LOGO_H = 72;

// The CODEF numbers, transcribed from raster.png, fontraster.png and logo.png.
const BAR = [
    [0, 255, 255], [0, 238, 255], [0, 204, 255], [0, 170, 255], [0, 136, 255], [0, 102, 255], [0, 0, 204],
    [34, 17, 102], [34, 17, 102], [34, 17, 102], [34, 17, 102], [34, 17, 102], [34, 17, 102], [34, 17, 102],
    [34, 17, 102], [34, 17, 102], [34, 17, 102], [34, 17, 102], [34, 17, 102], [34, 17, 102],
    [0, 102, 255], [0, 51, 238], [0, 34, 204], [0, 34, 170], [0, 17, 136], [0, 17, 102], [0, 17, 68], [0, 0, 34],
];
const INK = [[255, 221, 187], [255, 204, 170], [238, 187, 153], [238, 170, 136], [204, 153, 119], [204, 136, 102], [187, 119, 85]];
const LOGO_RGB = [
    [153, 153, 204], [187, 187, 221], [85, 85, 136], [170, 136, 153], [136, 102, 119], [204, 170, 187], [119, 119, 170],
    [102, 68, 85], [238, 238, 255], [255, 255, 255], [68, 34, 51], [238, 204, 221], [51, 51, 119], [34, 34, 85],
];
const STARS = [[221, 238, 238], [136, 170, 187], [85, 102, 136], [34, 68, 85]];
const BLACK = [0, 0, 0];

const same = (a, b) => a[0] === b[0] && a[1] === b[1] && a[2] === b[2];

async function boot(cart = CART) {
    const memory = new WebAssembly.Memory({ initial: PAGES, maximum: PAGES });
    const dec = new TextDecoder();
    let demo;
    const machine = (await WebAssembly.instantiate(await readFile("docs/machine-video.wasm"), {
        env: { memory, hblDispatch: (id, p, l, x) => demo.hblDispatch(id, p, l, x) },
    })).instance.exports;
    const romBytes = await readFile("docs/rom.wasm");
    const env0 = { memory, hwVideoBase: machine.hwVideoBase, hwBlit: machine.hwBlit };
    const rom = (await WebAssembly.instantiate(romBytes, { env: env0 })).instance.exports;
    machine.hwSetRomHigh(romRam(romBytes).high ?? 0);
    const noop = () => {};
    const cartBytes = await readFile(cart);
    demo = (await WebAssembly.instantiate(cartBytes, {
        env: {
            ...env0,
            jsConsoleLogWrite: noop, jsConsoleLogFlush: noop, jsThrowError: noop,
            consoleLogJS: (p, l) => console.log("[wasm]", dec.decode(new Uint8Array(memory.buffer, p, l))),
            hwRamUsed: machine.hwRamUsed, hwRamFree: machine.hwRamFree,
            hwRamAlloc: machine.hwRamAlloc, hwRamMark: machine.hwRamMark,
            hwRamRelease: machine.hwRamRelease, hwRamAllocFailures: machine.hwRamAllocFailures,
            hwRomRamBase: machine.hwRomRamBase, hwRomRamTop: machine.hwRomRamTop,
            hwRomRamSize: machine.hwRomRamSize, hwRomRamUsed: machine.hwRomRamUsed,
            hwRomRamFree: machine.hwRomRamFree, ...rom,
            audioPlay: noop, audioStop: noop, loadSample: noop, beep: noop, diskReadBlock: noop,
            hostAudioStreamStart: noop, hostAudioFeed: noop, hostAudioStreamStop: noop,
        },
    })).instance.exports;
    machine.hwSetCartHigh(cartRam(cartBytes).high ?? 0);
    machine.hwInit();
    demo.boot();
    demo.skipBoot();
    return new Screen(memory, machine, demo);
}

class Screen {
    constructor(memory, machine, demo) {
        this.machine = machine;
        this.demo = demo;
        this.w = machine.hwPhysWidth(); // 800: the window is x-DOUBLED
        this.h = machine.hwPhysHeight(); // 280
        this.pfb = new Uint8Array(memory.buffer, machine.hwPhysicalPtr(), this.w * this.h * 4);
        this.frames = 0;
        this.rgb = null;
    }

    // One host frame: the per-scanline palette only exists during a render (an HBL side
    // effect), so every frame is rendered, not just the ones that get looked at.
    run(n) {
        for (let i = 0; i < n; i++, this.frames++) {
            this.machine.hwClear();
            this.demo.frame(16.6);
            this.machine.hwRenderPlane(0);
        }
        this.rgb = this.compose();
    }

    // The 400x280 physical frame, un-doubled, 3 bytes a pixel.
    compose() {
        const half = this.w / 2;
        const out = new Uint8Array(half * this.h * 3);
        for (let y = 0; y < this.h; y++) {
            for (let x = 0; x < half; x++) {
                const i = (y * this.w + x * 2) * 4;
                const a = this.pfb[i + 3] / 255;
                const o = (y * half + x) * 3;
                for (let c = 0; c < 3; c++) out[o + c] = Math.round(this.pfb[i + c] * a);
            }
        }
        return out;
    }

    px(x, y) {
        const o = (y * 400 + x) * 3;
        return [this.rgb[o], this.rgb[o + 1], this.rgb[o + 2]];
    }

    async shot(path) {
        const hdr = new TextEncoder().encode(`P6\n400 ${this.h}\n255\n`);
        const out = new Uint8Array(hdr.length + this.rgb.length);
        out.set(hdr);
        out.set(this.rgb, hdr.length);
        await writeFile(path, out);
        console.log(`  shot: ${path} (frame ${this.frames})`);
    }
}

// The bar lives in the BORDER too: x=3 is left of the 320-pixel content.
function checkBar(s) {
    for (let i = 0; i < BAR_LINES; i++) {
        const got = s.px(3, TOP + BAR_Y + i);
        if (!same(got, BAR[i])) throw new Error(`bar line ${BAR_Y + i}: border ${got}, want ${BAR[i]}`);
    }
    for (const y of [BAR_Y - 1, BAR_Y + BAR_LINES]) {
        const got = s.px(3, TOP + y);
        if (!same(got, BLACK)) throw new Error(`line ${y} outside the bar: border ${got}, want black`);
    }
    console.log("  bar: 28 raster lines in the full-width border, black above and below");
}

// Every lit pixel of a text line carries fontraster's colour for that line.
function checkInk(s) {
    let lit = 0;
    for (let r = 0; r < TEXT_LINES; r++) {
        for (let x = 0; x < 320; x++) {
            const got = s.px(LEFT + x, TOP + TEXT_Y + r);
            if (got[0] === 0 && got[1] === 0 && got[2] === 0) continue;
            if (!same(got, INK[r]) && !isBarColour(got, TEXT_Y + r)) throw new Error(`text line ${r}: pixel ${got}, want ${INK[r]}`);
            if (same(got, INK[r])) lit++;
        }
    }
    if (lit < 100) throw new Error(`only ${lit} lit text pixels: the scroller is not drawing`);
    console.log(`  ink: ${lit} lit scroller pixels carry fontraster's colour for their line`);
}

function isBarColour(got, row) {
    return same(got, BAR[row - BAR_Y]);
}

function checkLogo(s) {
    let n = 0;
    for (let y = 0; y < LOGO_H; y++) {
        for (let x = 0; x < LOGO_W; x++) {
            const got = s.px(LEFT + LOGO_X + x, TOP + LOGO_Y + y);
            const v = s.logo[y * LOGO_W + x];
            if (v === 0) continue;
            if (!same(got, LOGO_RGB[v - 16])) throw new Error(`logo (${x},${y}): ${got}, want ${LOGO_RGB[v - 16]}`);
            n++;
        }
    }
    console.log(`  logo: ${n} opaque pixels exact at (${LOGO_X},${LOGO_Y})`);
}

// The stars cover the whole 240-row content: some reach the bottom 40 rows, which
// are the open bottom border on a 200-row screen.
function checkStars(s) {
    let bottom = 0;
    for (let y = 200; y < 240; y++) {
        for (let x = 0; x < 320; x++) {
            const got = s.px(LEFT + x, TOP + y);
            if (STARS.some((c) => same(got, c))) bottom++;
        }
    }
    if (bottom < 4) throw new Error(`only ${bottom} star pixels in rows 200..239: the stars do not reach the bottom border`);
    console.log(`  stars: ${bottom} star pixels in content rows 200..239 (the open bottom border)`);
}

function checkAll(s, scrolled) {
    checkBar(s);
    if (scrolled) checkInk(s); // letters enter from screen column 333: no ink before they reach the window
    checkLogo(s);
    checkStars(s);
}

// The logo's raw ST-res indices, as the scene embeds them.
async function loadLogo() {
    return new Uint8Array(await readFile("apps/zig/assets/screens/sca_karatekid2/logo.raw"));
}

const out = process.argv[2] || "sca_karatekid2_frames";
await mkdir(out, { recursive: true });
const screen = await boot();
screen.logo = await loadLogo();
screen.run(1);
await screen.shot(`${out}/00-first.ppm`);
checkAll(screen, false);

screen.run(299);
await screen.shot(`${out}/01-scroll.ppm`);
checkAll(screen, true);

screen.run(1500);
await screen.shot(`${out}/02-soak.ppm`);
checkAll(screen, true);
console.log("sca_karatekid2 headless: all checks pass");
