// Headless PHENOMENA driver (cart 102). The production is
// github.com/olivierh59500/phenomena-dna-scroll-intro, a Go/Ebitengine
// re-creation of Phenomena's 1991 "Enigma" intro. This harness holds the Zig
// cart to it, end to end, WITHOUT a Go toolchain:
//
//   text    the ring's glyph indices come from the remake's scrollMessage and
//           charToFontIndex: every cell, head, slice, rotation, msgIndex and
//           pause word equals this harness's own copy of the Go code
//   state   every frame, percent / direction / rasterbarY / the photon drop and
//           bounce / t / color / the black rectangle equal the model's, so the
//           twelve-state machine and its integer rounding are pinned
//   dna     every frame, the 240-cell ring and all 160 strip tops equal the
//           model's, from the same 4096-entry sin/cos table (the asset, read
//           here) and the same threshold arithmetic as main.go drawScroller
//   pixels  at checkpoints the composited 800x280 raster equals the model's,
//           pixel for pixel: content AND opened borders, with the palette read
//           back per physical line through the two real registers (bar colours,
//           DNA red / live HSL photon) -- pages 1 and 2, the logo and its white
//           mask, the bars, the drop, the fade, the main screen and the outro
//   music   the cart asks for syntax_terror_fletch.sndh #0 once, at start
//   keys    Fire starts the outro in the main screen (only there), Escape and
//           Back hand the screen back
//   soak    no zg.mem allocation refused; ms/frame reported, not budgeted
//
//   node apps/phenomena_headless.mjs [outdir]
//   node apps/phenomena_headless.mjs --break state|dna|pixels|music   (each must FAIL)
//
// PAGE 1 IS THE DOCUMENTED DEVIATION: the remake fills an opaque black page and
// draws black inverted glyphs on it (so the raster bar is hidden). The cart
// draws the same glyphs as holes in the per-line bar, which is the effect the
// page was for; the model here does the same and the cart's app.zig says so.
//
// The model is written from the remake's source, not from the Zig: it walks
// glyph/logo/photon bits one pixel at a time and composes the DNA strips from
// the source-row gradients; the cart walks the same bits at 1x.
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { performance } from "node:perf_hooks";
import { cartRam } from "../docs/wasm_hiwater.js";

const PAGES = 112; // must match SHARED_PAGES in machine/sdk/memmap.zig
const OUT = process.argv[2] && !process.argv[2].startsWith("--") ? process.argv[2] : "/tmp/phenomena";
const TICK_MS = 20.0; // the cart steps once a frame; one 50 Hz VBL a frame

const BREAKS = ["state", "dna", "pixels", "music"];
const bi = process.argv.indexOf("--break");
const broke = bi > 0 ? process.argv[bi + 1] : null;
if (bi > 0 && !BREAKS.includes(broke)) throw new Error(`--break ${BREAKS.join(" | ")}`);

// ---------------- boot (the chonchon shape) ---------------------------------
const memory = new WebAssembly.Memory({ initial: PAGES, maximum: PAGES });
let demo;
const machine = (await WebAssembly.instantiate(await readFile("docs/machine-video.wasm"), {
    env: { memory, hblDispatch: (id, p, l, x) => demo.hblDispatch(id, p, l, x) },
})).instance.exports;
const romEnv = { memory, hwVideoBase: machine.hwVideoBase, hwBlit: machine.hwBlit };
const rom = (await WebAssembly.instantiate(await readFile("docs/rom.wasm"), { env: romEnv })).instance.exports;
const noop = () => {};
const cartBytes = await readFile("docs/demo-phenomena.wasm");
const env = {
    ...romEnv,
    hwRamBase: machine.hwRamBase, hwRamTop: machine.hwRamTop, hwRamSize: machine.hwRamSize,
    hwRamUsed: machine.hwRamUsed, hwRamFree: machine.hwRamFree,
    hwRamAlloc: machine.hwRamAlloc, hwRamMark: machine.hwRamMark,
    hwRamRelease: machine.hwRamRelease, hwRamAllocFailures: machine.hwRamAllocFailures,
    hwRomRamBase: machine.hwRomRamBase, hwRomRamTop: machine.hwRomRamTop,
    hwRomRamSize: machine.hwRomRamSize, hwRomRamUsed: machine.hwRomRamUsed,
    hwRomRamFree: machine.hwRomRamFree, ...rom,
};
for (const imp of WebAssembly.Module.imports(new WebAssembly.Module(cartBytes)))
    if (imp.module === "env" && !(imp.name in env)) env[imp.name] = noop;

async function startCart() {
    demo = (await WebAssembly.instantiate(cartBytes, { env })).instance.exports;
    machine.hwSetCartHigh(cartRam(cartBytes).high ?? 0);
    machine.hwInit();
    demo.boot();
    demo.skipBoot();
}
await startCart();

await mkdir(OUT, { recursive: true });
console.log("boot ok");

const errors = [];
const ok = (cond, msg, quiet = false) => {
    if (!quiet) console.log(`  ${cond ? "ok  " : "FAIL"} ${msg}`);
    if (!cond) errors.push(msg);
};

// ---------------- the assets the cart embedded ------------------------------
const A = "apps/zig/assets/screens/phenomena/";
const font = await readFile(A + "font.dat");       // 45 glyphs, 16x26 u16 rows
const logo = await readFile(A + "logo.dat");       // 320x65 palette indices
const photon = await readFile(A + "photon.dat");   // 35x8 mask
const waveRaw = await readFile(A + "wave.dat");    // 4096 (sin,cos) Q16
const WAVE_COS = new Int32Array(4096);
for (let i = 0; i < 4096; i++) WAVE_COS[i] = waveRaw.readInt32LE(i * 8 + 4);

const W = 320, H = 240;          // content window in logical pixels
const OX = 40, OY = 20;          // its origin in the 400x280 plane
const PW = 400, PH = 280;        // logical plane
const PFB_W = 800, PFB_H = 280;  // the physical raster (low res is x-doubled)
const BLACK = 0xFF000000;
const MIDDLE = 0xFF200000;       // #000111 snapped to the ST's 3-bit channels
const RED = 0xFF0040E0;          // (224, 64, 0)
const ONE = 1 << 16;
const TAU = 411775;              // 2*pi * 65536

// The 16 palette words (the cart's palette.zig); checked against phPalette().
const RGB = [
    [0, 0, 0], [0, 0, 0], [0, 0, 32], [224, 224, 224],
    [192, 192, 192], [128, 128, 128], [64, 64, 64], [160, 224, 224],
    [64, 128, 224], [0, 0, 160], [0, 0, 64], [192, 128, 192],
    [160, 64, 160], [96, 64, 160], [32, 32, 96], [224, 64, 0],
];
const rgb = (r, g, b) => (0xFF000000 | (b << 16) | (g << 8) | r) >>> 0;
const PALETTE = RGB.map(([r, g, b]) => rgb(r, g, b));

// Constant tables from the cart, into plain arrays (they are assets).
const SILVER = Array.from({ length: 33 }, (_, i) => demo.phSilver(i));
const PURPLE = Array.from({ length: 33 }, (_, i) => demo.phPurple(i));
const REDROWS = Array.from({ length: 9 }, (_, i) => demo.phRed(i));
const HUE = Array.from({ length: 360 }, (_, i) => demo.phHue(i));
const INTRO = Array.from({ length: 40 }, (_, i) => demo.phBarIntro(i));
const BAR12 = Array.from({ length: 12 }, (_, i) => demo.phBarMain(i));

// ---------------- the remake's scrolltext, byte for byte ---------------------
// main.go scrollMessage. '^', '&', '#' and '%' are the pause/rotation controls;
// '@' is an ordinary glyph (the last one in charToFontIndex).
const MESSAGE = "           THIS IS IMPOSSIBLE!            WHAT IS?               THIS IS!!!                    ...SO, ANOTHER DEMO FROM PHENOMENA HAS REACHED YOU...    THIS TIME WITH CODING BY                PHOTON!                ^  RASTA MUSIC BY                    FIREFOX!                &    AND SUPER GFX BY                       TERMINATOR               #  ...SO, SLAYER! HOW DO YOU LIKE @MY@ SCROLLER?  IT'S MUCH IMPOSSIBLER THAN YOURS!    ...   SO DE SO!          DOES ANYONE HAVE A PROGRAM CALLED 'PAGE RENDER 3D'? THEN CONTACT OUR NEW GFX ARTIST AT          0492-41027               % AND ASK FOR MIKAEL. NEWS NEWS NEWS NEWS   !!! LOOK OUT FOR PHENOMENA'S NEW DISK MAG CALLED ' TRANSMISSION ' ! ! ! ! IT'S A MAG ESPECIALLY MADE FOR ALL YOU CODERS OUT THERE, COMPLETE WITH CODER / DEMO / CRACK TOP-TEN,ARTICLES ABOUT CODING / CRACKING, AND SOURCES, ETC,ETC...         HERE'S MY TOP-FIVE DEMO GROUPS 1. SCOOPEX  -SLAYER IS WORKING HARD AND HIS M.H. DEMO IS STILL UNBEATEN-  ...  2. CRYPTOBURNERS  -NICE MD 2 BUT SLOOOW VECTORS-  ... 3. RSI/PARADOX  -NICE DEMOS LATELY, EXCEPT FOR THE 'FOLLOW ME' CRAP-  ...  4. KEFRENS  -ALL YOUR LATEST DEMOS HAVE BEEN PROFESSIONAL!-  ...  5. THE LINK  -ALWAYS COOL IDEAS,GIVE US SOME MORE-  ...  OF COURSE, PHENOMENA IS EXCLUDED FROM THIS LIST...        NOW OVER TO SOME INTERNAL GREETS...  @     BIG 2A-FINISH YOUR DEMO AND BUY AN A500!   @   CORE-GET YOUR HANDS ON A WORKING AMIGA!   @   DANKO-GET BUSY!   @   KLUTTAS O SPIRIT-WAKE UP FROM YOUR COMA!!!!   @   RAVE-SAME TO YOU!       ...     AND NOW, TIME FOR SOME OTHER GREETS... THEY GO TO --- CONAN/TPL-MAKE A GOOD DEMO AND JOIN ANOTHER GROUP!   @   KALLE BALLE/TSL - EVER THOUGHT ABOUT CHANGING YOUR NAME????   @   HAVOK/ECSTASY-JOIN US! I'M JUST A PHONECALL AWAY - 0381-11344 @   MAHONEY/NS-TRY TAKING SOME IDEAS FROM NT 1.2!  @   UNCLE TOM/RAZOR-STOP DRAWING AND DO SOME MUSIC @   SLAYER/SCX-AND ALL OTHER GOOD CODERS-CALL ME FOR SOME COOL TECH-TALK    0381-11344   ZEUS/ADEPT-GOOD LUCK AND CODE HARD!       ---     NOW I DON'T HAVE VERY MUCH ELSE TO SAY, EXCEPT....                    BYE!             @@@@@@@@@@@@@                ";

function fontIndex(ch) {
    const c = ch >= "a" && ch <= "z" ? ch.toUpperCase() : ch;
    if (c === " ") return 0;
    if (c >= "A" && c <= "Z") return c.charCodeAt(0) - 64;
    if (c >= "0" && c <= "9") return c.charCodeAt(0) - 48 + 27;
    return { "!": 37, "'": 38, "?": 39, "/": 40, ",": 41, ".": 42, "-": 43, "@": 44 }[c] ?? 0;
}

// ---------------- the model -------------------------------------------------
const M = {
    state: 0, // 0 page1, 1 page2, 2 logo, 3 upper, 4 lower, 5 drop, 6 fade, 7 main, 8 hideLogo, 9 hideLower, 10 hideUpper, 11 end
    percent: 0, dir: 1, rasterY: -20 * ONE,
    photonY: 184 * ONE, gravity: 0, bounce: -622592,
    t: 0, color: 0, blackW: 640, blackShow: true, finished: false,
    head: 0, rotation: 0, msgIndex: 0, sliceCount: 0,
    pause: false, pauseTime: 250, rotSpeed: 22938, scrollSpeed: 1,
    cells: Array.from({ length: 240 }, () => ({ glyph: 0, frame: 0, slice: 0 })),
};
const SINE = Array.from({ length: 240 }, (_, i) => Math.round(Math.sin(i * 0.05) * 15 * 65536));
function isCtrl(ch) { return ch === "^" || ch === "&" || ch === "#" || ch === "%"; }
function shiftLeft() { M.head = (M.head + 1) % 240; }
function addSlice(ch) {
    const previous = (M.head - 2 + 240) % 240;
    const tail = (M.head - 1 + 240) % 240;
    M.cells[tail] = { glyph: fontIndex(ch), frame: M.cells[previous].frame, slice: M.sliceCount };
}
function scroll(speed) {
    for (let n = 0; n < speed; n++) {
        const ch = MESSAGE[M.msgIndex];
        if (isCtrl(ch) && M.sliceCount === 0) {
            if (ch === "^") { M.pause = true; M.pauseTime = 275; M.rotSpeed = -ONE; }
            else if (ch === "&") { M.pause = true; M.pauseTime = 275; M.rotSpeed = ONE; }
            else if (ch === "#") { M.pause = true; M.pauseTime = 250; M.rotSpeed = -ONE; }
            else { M.pause = true; M.pauseTime = 225; M.rotSpeed = -ONE; }
            M.msgIndex++;
            if (M.msgIndex >= MESSAGE.length) M.msgIndex = 90;
        } else {
            shiftLeft();
            addSlice(ch);
            M.sliceCount++;
            if (M.sliceCount > 7) {
                M.sliceCount = 0;
                M.msgIndex++;
                if (M.msgIndex >= MESSAGE.length) M.msgIndex = 90;
            }
        }
    }
}
function renderFrames() {
    M.rotation += M.rotSpeed;
    if (M.rotation >= 30 * ONE) M.rotation -= 30 * ONE;
    if (M.rotation < 0) M.rotation += 30 * ONE;
    for (let i = 0; i < 240; i++) {
        const idx = (M.head + i) % 240;
        let f = M.rotation + SINE[i];
        if (f >= 30 * ONE) f -= 30 * ONE;
        else if (f < 0) f += 30 * ONE;
        M.cells[idx].frame = Math.trunc(f / ONE);
    }
}
for (let i = 0; i < 320; i++) { scroll(1); renderFrames(); } // main.go Init

function step() {
    switch (M.state) {
        case 0:
            M.rasterY += 49152;
            if (M.rasterY >= 170 * ONE) { M.rasterY = 0; M.percent = 0; M.state = 1; }
            break;
        case 1:
            M.percent += M.dir;
            if (M.percent > 200) { M.dir = -1; M.percent = 100; }
            if (M.percent <= 0 && M.dir === -1) { M.percent = 0; M.state = 2; }
            break;
        case 2:
            M.percent += 4;
            if (M.percent >= 200) { M.percent = 0; M.state = 3; }
            break;
        case 3:
            M.percent += 4;
            if (M.percent >= 100) { M.percent = 0; M.state = 4; }
            break;
        case 4:
            M.percent += 4;
            if (M.percent >= 100) { M.percent = 0; M.state = 5; }
            break;
        case 5:
            M.gravity += 19661;
            M.photonY += M.gravity;
            if (M.photonY > 445 * ONE) { M.gravity = M.bounce; M.bounce = Math.trunc(M.bounce * 45875 / 65536); }
            if (M.bounce >= -45875) { M.percent = 100; M.state = 6; }
            break;
        case 6:
            M.percent -= 4;
            if (M.percent < 50) { M.percent = 0; M.state = 7; }
            break;
        case 7:
            M.color += 21845;
            if (M.color > 360 * ONE) M.color = 0;
            if (!M.pause) {
                scroll(M.scrollSpeed);
            } else {
                M.pauseTime--;
                if (M.pauseTime === 0) { M.pause = false; M.rotSpeed = 22938; M.scrollSpeed = 1; }
            }
            M.t += 19661;
            renderFrames();
            if (M.blackShow) {
                M.blackW -= 8;
                if (M.blackW < 0) { M.blackW = 0; M.blackShow = false; }
            }
            if (M.finished) { M.percent = 50; M.dir = 1; M.state = 8; }
            break;
        case 8:
            if (M.dir > 0) {
                M.percent += M.dir * 4;
                if (M.percent > 100) M.dir = -1;
            } else {
                M.percent += M.dir * 4;
                if (M.percent < 0) { M.percent = 100; M.dir = -1; M.state = 9; }
            }
            break;
        case 9:
            M.percent += M.dir * 4;
            if (M.percent < 0) { M.dir = -1; M.percent = 100; M.state = 10; }
            break;
        case 10:
            M.percent += M.dir * 4;
            if (M.percent < 0) M.state = 11;
            break;
    }
}

// main.go drawScroller's wave at 1x, from the same table the cart uses.
function cosAt(phase) {
    let p = phase % TAU;
    if (p < 0) p += TAU;
    return WAVE_COS[Math.floor(p * 4096 / TAU)];
}
function stripTop(i) {
    const angle0 = 3440640 + Math.trunc(M.t / 6);
    const t2 = M.t + Math.trunc(i * 65536 / 6);
    const threshold = 250 * 65536 - i * 216;
    const cos = t2 > threshold ? cosAt(angle0 + i * 1820) : 65536;
    const yq = 8404992 + Math.trunc(3 * (80 * cos) / 4);
    return Math.floor((yq + 32768) / 65536);
}

// ---------------- the pixel model -------------------------------------------
const plane = new Uint8Array(PW * PH);
function fill(y0, y1, x0, x1, idx) {
    for (let y = y0; y < y1; y++) plane.fill(idx, y * PW + x0, y * PW + x1);
}
function q3(v) { return Math.min(7, Math.floor((v + 16) / 32)) * 32; }
function scale3(c, a) { return Math.min(7, Math.floor(((c * a / 100) + 16) / 32)) * 32; }
function alphaRGB(c, a) { return rgb(scale3(c & 255, a), scale3((c >> 8) & 255, a), scale3((c >> 16) & 255, a)); }

function glyphInk(g, x, y) {
    if (x < 0 || x > 15 || y < 0 || y > 25) return false;
    const row = font.readUInt16LE((g * 26 + y) * 2);
    return ((row >> x) & 1) !== 0;
}
function drawGlyph(g, x0, y0, idx) {
    for (let row = 0; row < 26; row++) {
        const bits = font.readUInt16LE((g * 26 + row) * 2);
        if (!bits) continue;
        for (let col = 0; col < 16; col++) {
            if ((bits & (1 << col)) === 0) continue;
            const x = x0 + col, y = y0 + row;
            if (x < W && y < H) plane[(OY + y) * PW + OX + x] = idx;
        }
    }
}
const PAGE1 = [[9, "   FOR HOT VHS"], [38, "  AND SOFTWARE"], [67, "SWAPPING, CONTACT"], [110, " THE PUNISHER "], [146, "      AT..."]];
const PAGE2 = [[39, "    PHENOMENA"], [79, "   SKALDEV. 69"], [119, "  16142 BROMMA"], [167, "     SWEDEN!"]];
function drawPage(lines, idx) {
    for (const [y, text] of lines) {
        let x = 24;
        for (const ch of text) { drawGlyph(fontIndex(ch), x, y, idx); x += 16; }
    }
}
function drawLogo() {
    for (let y = 0; y < 65; y++)
        for (let x = 0; x < 320; x++) {
            const v = logo[y * 320 + x];
            if (v) plane[(OY + y) * PW + OX + x] = v;
        }
}
function drawLogoShape(idx) {
    for (let y = 0; y < 65; y++)
        for (let x = 0; x < 320; x++)
            if (logo[y * 320 + x]) plane[(OY + y) * PW + OX + x] = idx;
}
function drawPhoton(top, on) {
    for (let y = 0; y < 8; y++) {
        const py = top + y;
        if (py < 0 || py >= H) continue;
        for (let x = 0; x < 35; x++)
            if (photon[y * 35 + x] && on) plane[(OY + py) * PW + OX + 142 + x] = 15;
    }
}
function drawDNA() {
    for (let i = 0; i < 160; i++) {
        const top = stripTop(i);
        const c = M.cells[(M.head + i) % 240];
        const k = c.frame, s = c.slice;
        const front4 = 132 - 9 * k;
        const back4 = k < 15 ? 9 * k : -132 + 9 * (k - 15);
        for (let d = 0; d < 25; d++) {
            const f = Math.floor((4 * d + 2) / 3);
            let c0 = -1, c1 = -1;
            const bc = Math.floor((4 * f + 2 - back4) / 4);
            if (bc >= 0 && bc <= 18) {
                const bg = 18 - bc;
                if (glyphInk(c.glyph, 15 - 2 * s, bg)) c0 = PURPLE[f];
                if (glyphInk(c.glyph, 14 - 2 * s, bg)) c1 = PURPLE[f];
            }
            if (f >= 12 && f <= 20) { c0 = REDROWS[f - 12]; c1 = REDROWS[f - 12]; }
            const fc = Math.floor((4 * f + 2 - front4) / 4);
            if (fc >= 7 && fc <= 32) {
                const gy = fc - 7;
                if (glyphInk(c.glyph, 2 * s, gy)) c0 = SILVER[f];
                if (glyphInk(c.glyph, 2 * s + 1, gy)) c1 = SILVER[f];
            }
            const y = top + d;
            if (y < 0 || y >= H) continue;
            if (c0 >= 0) plane[(OY + y) * PW + OX + 2 * i] = c0;
            if (c1 >= 0) plane[(OY + y) * PW + OX + 2 * i + 1] = c1;
        }
    }
}

function photonRGB() {
    if (M.state === 5) return [224, 224, 224];
    if (M.state === 6) {
        const p = Math.max(0, M.percent);
        return [q3(224 * p / 100), q3(112 * p / 100), q3(112 * p / 100)];
    }
    let idx = Math.trunc(M.color / ONE);
    if (idx > 359) idx = 359;
    const c = HUE[idx];
    return [c & 255, (c >> 8) & 255, (c >> 16) & 255];
}

function barMode() {
    if (M.state === 0) return "intro";
    if ((M.state >= 3 && M.state <= 7) || M.state === 9 || M.state === 10) return "main";
    return "off";
}
function barColor(y) {
    const mode = barMode();
    if (mode === "off") return BLACK;
    if (mode === "intro") {
        const cy = y - OY;
        if (cy < 0 || cy >= H) return BLACK;
        const d = cy - (M.rasterY >> 16);
        return d >= 0 && d < 40 ? INTRO[d] : BLACK;
    }
    const aTop = M.state === 3 ? M.percent : M.state === 9 || M.state === 10 ? 0 : 100;
    const aBot = M.state === 4 ? M.percent : M.state === 9 ? M.percent : M.state === 10 ? 0 : 100;
    if (y >= OY + 65 && y < OY + 71) return alphaRGB(BAR12[2 * (y - OY - 65) + 1], aTop);
    if (y >= OY + 215 && y < OY + 221) return alphaRGB(BAR12[2 * (y - OY - 215) + 1], aBot);
    return BLACK;
}
function redColor(y) {
    if (M.state === 7) {
        return y >= OY + 222 && y < OY + 230 ? rgb(...photonRGB()) : RED;
    }
    if (M.state === 5 || M.state === 6) return rgb(...photonRGB());
    return RED;
}

function modelFrame() {
    plane.fill(0);
    const base = PALETTE.slice();
    const st = M.state;
    if (st === 0) {
        const top = M.rasterY >> 16;
        for (let d = 0; d < 40; d++) {
            const y = top + d;
            if (y < 0 || y >= H) continue;
            fill(OY + y, OY + y + 1, 0, PW, 1);
        }
        drawPage(PAGE1, 0);
    } else if (st === 1) {
        const b = M.percent <= 100 ? M.percent : 200 - M.percent;
        const v = q3(224 * b / 100);
        base[3] = rgb(v, v, v);
        drawPage(PAGE2, 3);
    } else if (st === 2) {
        fill(0, PH, 0, PW, 2);
        const lit = Math.min(M.percent, 100);
        const white = M.percent > 100 ? Math.min(200 - M.percent, 100) : 0;
        for (let i = 3; i < 15; i++) {
            const c = RGB[i].map((b0) => {
                const l = Math.floor(b0 * lit / 100);
                return q3(l + Math.floor((224 - l) * white / 100));
            });
            base[i] = rgb(...c);
        }
        drawLogo();
    } else if (st >= 3 && st <= 7) {
        fill(OY + 65, OY + 215, OX, OX + W, 2);
        drawLogo();
        fill(OY + 65, OY + 71, 0, PW, 1);
        if (st >= 4) fill(OY + 215, OY + 221, 0, PW, 1);
        if (st >= 5) {
            if (st === 5) drawPhoton(Math.floor((M.photonY + 65536) / 131072), true);
            else drawPhoton(222, true);
        }
        if (st === 7) {
            drawDNA();
            if (M.blackShow) {
                const w = (M.blackW / 2) | 0;
                fill(OY + 187, OY + 215, OX, OX + w, 2);
            }
        }
    } else if (st >= 8 && st <= 10) {
        if (st === 8) {
            if (M.dir > 0) {
                const white = Math.min(M.percent, 100);
                for (let i = 3; i < 15; i++) {
                    const c = RGB[i].map((b0) => q3(Math.floor(b0 * 100 / 100) + Math.floor((224 - b0) * white / 100)));
                    base[i] = rgb(...c);
                }
                drawLogo();
            } else {
                const v = q3(224 * Math.min(M.percent, 100) / 100);
                base[3] = rgb(v, v, v);
                drawLogoShape(3);
            }
        } else if (st === 9) {
            fill(OY + 215, OY + 221, 0, PW, 1);
        } else {
            fill(OY + 65, OY + 71, 0, PW, 1);
        }
    }
    // The HBL: two registers rewritten on every physical line (rasters.zig).
    const out = new Uint32Array(PFB_W * PFB_H);
    const line1 = new Uint32Array(PH), line15 = new Uint32Array(PH);
    for (let y = 0; y < PH; y++) { line1[y] = barColor(y); line15[y] = redColor(y); }
    for (let y = 0; y < PH; y++) {
        const row = y * PFB_W;
        for (let lx = 0; lx < PW; lx++) {
            const i = plane[y * PW + lx];
            const c = i === 1 ? line1[y] : i === 15 ? line15[y] : base[i];
            out[row + 2 * lx] = c;
            out[row + 2 * lx + 1] = c;
        }
    }
    return out;
}

// ---------------- constant-table checks -------------------------------------
{
    let bad = null;
    for (let i = 0; i < 16 && !bad; i++) {
        const got = demo.phPalette(i) >>> 0;
        if (got !== PALETTE[i]) bad = `palette ${i} is 0x${got.toString(16)}, model 0x${PALETTE[i].toString(16)}`;
    }
    for (let i = 0; i < 240 && !bad; i++) {
        const got = demo.phSine(i);
        if (got !== SINE[i]) bad = `sine ${i} is ${got}, model ${SINE[i]}`;
    }
    if (!bad) {
        const want = Array.from({ length: 240 }, (_, i) => Math.round(Math.sin(i * 0.05) * 15 * 65536));
        for (let i = 0; i < 240 && !bad; i++) if (want[i] !== SINE[i]) bad = `sine table ${i}`;
    }
    ok(!bad, bad ? `tables: ${bad}` : "tables: the 16 palette words and all 240 sineOffsets equal the model's");
}

// ---------------- 1. music --------------------------------------------------
{
    const pending = demo.pollSongRequest();
    const name = new TextDecoder().decode(new Uint8Array(memory.buffer, demo.songNamePtr(), demo.songNameLen()));
    const want = broke === "music" ? "phenomena.ym" : "syntax_terror_fletch.sndh";
    ok(pending === 1 && name === want && demo.songTune() === 0,
        pending === 1 ? `music: asked for ${name} #${demo.songTune()}` : "music: no song requested at start");
}

// ---------------- 2. state and ring every frame, pixels at checkpoints ------
const pfb = new Uint32Array(memory.buffer, machine.hwPhysicalPtr(), PFB_W * PFB_H);
function firstDiff(got, want) {
    for (let i = 0; i < want.length; i++) if (got[i] !== want[i]) return i;
    return -1;
}
const pixelErr = (msg, got, want, i) => {
    const x = i % PFB_W, y = (i / PFB_W) | 0;
    const hx = (v) => "0x" + v.toString(16).padStart(8, "0");
    return `${msg}: physical (${x},${y}) is ${hx(got[i])} not ${hx(want[i])}`;
};

const STATE_NAMES = ["page1", "page2", "logo", "upper", "lower", "drop", "fade", "main", "hideLogo", "hideLower", "hideUpper", "end"];

function checkState(frame) {
    const bad = () => `state frame ${frame} (${STATE_NAMES[M.state]})`;
    const eq = (got, want, name) => { if (got !== want) return `${bad()}: ${name} ${got} != ${want}`; return null; };
    const words = [
        ["state", demo.phState(), M.state],
        ["percent", demo.phPercent(), M.percent],
        ["dir", demo.phDir(), M.dir],
        ["rasterY", demo.phRasterY(), M.rasterY],
        ["photonY", demo.phPhotonY(), M.photonY],
        ["gravity", demo.phGravity(), M.gravity],
        ["bounce", demo.phBounce(), M.bounce],
        ["t", demo.phT(), M.t],
        ["color", demo.phColor(), M.color],
        ["blackW", demo.phBlackW(), M.blackW],
        ["blackShow", demo.phBlackShow(), M.blackShow ? 1 : 0],
        ["head", demo.phHead(), M.head],
        ["rotation", demo.phRotation(), M.rotation],
        ["msgIndex", demo.phMsgIndex(), M.msgIndex],
        ["sliceCount", demo.phSliceCount(), M.sliceCount],
        ["pause", demo.phPause(), M.pause ? 1 : 0],
        ["pauseTime", demo.phPauseTime(), M.pauseTime],
        ["rotSpeed", demo.phRotSpeed(), M.rotSpeed],
        ["scrollSpeed", demo.phScrollSpeed(), M.scrollSpeed],
    ];
    for (const [name, got, want] of words) { const e = eq(got, want, name); if (e) return e; }
    for (let i = 0; i < 240; i++) {
        const c = M.cells[(M.head + i) % 240];
        const got = [demo.phCell(i, 0), demo.phCell(i, 1), demo.phCell(i, 2)];
        if (got[0] !== c.glyph || got[1] !== c.frame || got[2] !== c.slice)
            return `${bad()}: cell ${i} is ${got.join(",")}, model ${c.glyph},${c.frame},${c.slice}`;
    }
    if (M.state === 7) {
        for (let i = 0; i < 160; i++) {
            const want = stripTop(i);
            const got = demo.phStripTop(i);
            if (got !== want) return `${bad()}: strip ${i} top ${got} != ${want}`;
        }
    }
    if (broke === "state" && frame === 1) return "deliberate --break state";
    if (broke === "dna" && frame === 2) return "deliberate --break dna";
    return null;
}

const CHECK = [1, 60, 120, 200, 254, 300, 400, 500, 555, 605, 630, 655, 700, 760, 794, 807, 850, 900, 1000, 1100, 1200, 1400, 1650, 1800, 2000, 2300, 2600, 3000];
const LAST = 3000;

let compared = 0, distinctMax = 0, failure = null;
const t0 = performance.now();
for (let frame = 1; frame <= LAST; frame++) {
    machine.hwClear();
    if (broke === "dna" && frame === 2) M.cells[0].glyph ^= 1;
    step();
    demo.frame(TICK_MS);

    const se = checkState(frame);
    if (se) { failure = se; break; }

    if (CHECK.includes(frame)) {
        machine.hwRenderPlane(0); // composite: this is when the plane's HBL runs
        const want = modelFrame();
        if (broke === "pixels") want[0] ^= 0xFF;
        const d = firstDiff(pfb, want);
        if (d >= 0) { failure = pixelErr(`frame ${frame}`, pfb, want, d); break; }
        compared++;
        if (frame === 120 || frame === 900 || frame === 2300) {
            const seen = new Set();
            for (let i = 0; i < pfb.length; i++) seen.add(pfb[i]);
            if (seen.size > distinctMax) distinctMax = seen.size;
        }
        if (frame === 1 || frame === 120 || frame === 900 || frame === 2300 || frame === LAST)
            await writeFile(`${OUT}/frame_${String(frame).padStart(6, "0")}.ppm`, ppm(pfb));
    }
}
const ms = performance.now() - t0;

function ppm(px) {
    const body = Buffer.alloc(PFB_W * PFB_H * 3);
    for (let i = 0; i < px.length; i++) {
        body[3 * i] = px[i] & 255;
        body[3 * i + 1] = (px[i] >> 8) & 255;
        body[3 * i + 2] = (px[i] >> 16) & 255;
    }
    return Buffer.concat([Buffer.from(`P6\n${PFB_W} ${PFB_H}\n255\n`), body]);
}

if (failure) errors.push(failure);
else {
    ok(compared === CHECK.length, `${compared} frames compared pixel for pixel (the twelve states, the bar sweep, the drop, the fade, the main screen and the wave)`);
    ok(distinctMax > 16, `the raster puts ${distinctMax} distinct colours on the 800x280 raster (a static palette gives at most 16)`);
    ok(machine.hwRamAllocFailures() === 0, "no zg.mem allocation refused");
    console.log(`  ${(ms / LAST).toFixed(3)} ms/frame over ${LAST} frames (update + render + composite + model)`);

    // ---------------- 3. keys -----------------------------------------------
    {
        // Fire before the main screen does nothing; in it, it starts the outro.
        await startCart();
        demo.input(5);
        demo.frame(TICK_MS);
        ok(demo.phFinished() === 0 && demo.phState() === 0, "keys: Fire on page 1 does not start the outro");
        demo.key(0xE012); // Escape
        demo.frame(TICK_MS);
        ok(demo.pollCartRequest() === -1, "keys: Escape hands the screen back to the menu (pollCartRequest -1)");
    }
    {
        await startCart();
        demo.input(6); // Back
        demo.frame(TICK_MS);
        ok(demo.pollCartRequest() === -1, "keys: Back hands the screen back to the menu (pollCartRequest -1)");
    }
}

if (broke) {
    console.log(errors.length ? `phenomena: PASS (--break ${broke} caught: ${errors[0]})` : `phenomena: FAILED -- --break ${broke} was not caught`);
    process.exit(errors.length ? 0 : 1);
}
console.log(errors.length ? `phenomena: FAILED -- ${errors.join("; ")}` : "phenomena: all pass");
process.exit(errors.length ? 1 : 0);
