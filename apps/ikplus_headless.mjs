// Headless IK+ driver (cart 99). The production is
// github.com/olivierh59500/go-dom-intro, a Go/Ebitengine re-creation of The
// Replicants' "International Karate Plus" cracktro. This harness holds the Zig
// cart to it, end to end, WITHOUT a Go toolchain:
//
//   text    the cart's compiled scrolltext (GLYPH_COUNT, CHANGES, the four TILES
//           arrays) equals this harness's own parse of getFullText() (copied from
//           game.go with the spc0..spc3 expansions applied), control codes and all
//   state   every frame, off1 / actSize / posY / posY2 and all eight stars equal
//           the model's, so the update order and the two scroll clocks are pinned
//   model   the machine's composited 800x280 raster equals the model's, pixel for
//           pixel: the content window AND both side borders (the rasters run edge
//           to edge), with the palette read back per physical line -- which
//           validates the HBL, both colour tables and the flicker trick together
//   raster  the window carries more colours than the six palette words alone
//   music   the cart asks for so_watt_no_crew.sndh #1 once, at start
//   keys    F1 / F2 step spinc; Escape and Back hand the screen back
//   soak    no zg.mem allocation refused; ms/frame reported, not budgeted
//
//   node apps/ikplus_headless.mjs [outdir]
//   node apps/ikplus_headless.mjs --break raster|state|text   (each must FAIL)
//
// The model is written from the remake's source, not from the Zig: it walks the
// font/logo/star bytes one pixel at a time (the cart walks comptime runs), and it
// steps the two 2x raster clocks with the same formulas rasters.zig documents.
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { performance } from "node:perf_hooks";
import { cartRam } from "../docs/wasm_hiwater.js";

const PAGES = 112; // must match SHARED_PAGES in machine/sdk/memmap.zig
const OUT = process.argv[2] && !process.argv[2].startsWith("--") ? process.argv[2] : "/tmp/ikplus";
const TICK_MS = 20.0; // the cart steps once a frame; one 50 Hz VBL a frame

const BREAKS = ["raster", "state", "text"];
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
const cartBytes = await readFile("docs/demo-ikplus.wasm");
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
const A = "apps/zig/assets/screens/ikplus/";
const font = await readFile(A + "font.dat");     // 20x944, 1 = ink
const logo = await readFile(A + "logo.dat");     // 320x62, 1 = ink
const starAtlas = await readFile(A + "stars.dat"); // 10 frames of 32x23
const rast1Raw = await readFile(A + "rast1.dat"); // 200 RGBA
const rast2Raw = await readFile(A + "rast2.dat"); // 690 RGBA
const RAST1 = Array.from({ length: 200 }, (_, i) => rast1Raw.readUInt32LE(i * 4));
const RAST2 = Array.from({ length: 690 }, (_, i) => rast2Raw.readUInt32LE(i * 4));

const W = 320, H = 200;           // content window in logical pixels
const OY = 40, OX = 40;           // its origin in the 400x280 plane
const PHYS_W = 400, PHYS_H = 280; // logical plane
const PFB_W = 800, PFB_H = 280;   // the physical raster (low res is x-doubled)
const BLACK = 0xFF000000;
const LOGO_RGBA = 0xFFA0A0A0;
const STAR_RGBA = [0, 0, 0, 0xFF808080, 0xFFC0C0C0, 0xFFE0E0E0];

// ---------------- the remake's scrolltext, parsed here ----------------------
// game.go's getFullText(), with spc0..spc3 EXPANDED. (The Go concatenates
// literals and four spc variables; joining only the quoted literals silently
// drops 128 spaces, which is the bug this copy pins down.) It is a constant so
// the harness never depends on prototypes/ being checked out; the control-code
// parse and tile build below are still independent of the cart.
const SOURCE =
    "          THE UNION IS PROUD TO PRESENT YOU :                 ^Cs2;INTERNATIONAL KARATE PLUS     ^Cs0;CRACKED " +
    " BY                 ^Cs3;DOM AND CORWIN   ^Cs1;FROM THE         ^Cs3;REPLICANTS AND DMA   ^Cs1; PRESS F1-F5 AN" +
    "D SEE (IF YOU CAN !!!!) AND LIST..........    A SPECIAL HI TO WILD-XEROX OR RANK-COPPER MY MASTER!!!!!ARF.... " +
    "HEEEUUUU JUST A LITTLE QUESTION : WHO HAVE         ^Cs2;BARBARIAN 2 ????????     ^Cs1;RRRRHHHHHAAAAAAAAAAA!!!!" +
    "!! ANYBODY ????? I NEED BLOOD RRRHHAAAA!!!!! NEED HEAD !!!!! OOOUUUIIIINNNN I WEEP .. I CRY...... I RAVE , I'M" +
    " DELIRIOUS I'M CAUGHT IN THE ACT-HANDED!!!!!!!         ^Cs0;OK KO I STOP, I RESET, I BREAK, I DRINK,I FLY, I C" +
    "R...-CR... HIHIHI FINALLY I SAY :                 ^Cs3;SHEAT       ^Cs2;HEY HAVE-YOU CANAL PLUS??????????    W" +
    "HAT ???????    I SAY CANAL PLUS    BORDEL !! (IN FRENCH) YOU DON'T HAVE !!!! BUY THIS AND YOU WILL SEE MY MAST" +
    "ER : I NAME : RANK-COOPER ARF ARF HE TURN ONE'S BACK ON THE CAMERA    OOOUUFF!!!HIHI GGGGGGGGGOOOOOOOOODDDDDDD" +
    "DD     ^Cs1;IT'S ALL FOR DAY......         ^Cs0;REMEMBER YOU BARBARIAN 2 AND CANAL PLUS AND MY MASTER OF COURS" +
    "E........ HI TO : ALL MEMBERS OF DMA(ESPECIALLY LOCKBUSTER FOR ORIGINAL), DELTA FORCE, TEX, BLADE RUNNERS, CHO" +
    "N-CHON, ALDO, ST-CONNEXION, THE HOBBIT BROTHERS, ABC 85, THE BARBARIANS.......                 ^Cs0;          " +
    "    ";

function controlAt(t, i) {
    if (i + 4 >= t.length || t[i] !== "^") return null;
    const s = t.slice(i, i + 5);
    return s === "^Cs0;" ? 0 : s === "^Cs1;" ? 1 : s === "^Cs2;" ? 2 : s === "^Cs3;" ? 3 : null;
}
function tileOf(c) {
    return c < 32 || c > 90 ? 0 : c - 32;
}
const GLYPHS = (() => {
    let n = 0;
    for (let i = 0; i < SOURCE.length;) {
        if (controlAt(SOURCE, i) !== null) i += 5;
        else { n++; i++; }
    }
    return n;
})();
const CHANGES = (() => {
    const out = [];
    let pos = 0;
    for (let i = 0; i < SOURCE.length;) {
        const s = controlAt(SOURCE, i);
        if (s !== null) { out.push({ pos, size: s }); i += 5; }
        else { pos++; i++; }
    }
    return out;
})();
const TILES = Array.from({ length: 4 }, (_, size) => {
    const out = [];
    let active = size === 0;
    for (let i = 0; i < SOURCE.length;) {
        const s = controlAt(SOURCE, i);
        if (s !== null) { active = s === size; i += 5; continue; }
        const c = SOURCE.charCodeAt(i);
        out.push(active && c !== 32 ? tileOf(c) : -1);
        i++;
    }
    return out;
});

// ---------------- the model's state machine --------------------------------
const SCALE = [1, 2, 4, 8];
const SCALE_Y = [1, 2, 4, 12];
const BAND_Y = [2, 2, 1, 3];
const BAND_STEP = [18, 33, 67, 67];
const BAND_COUNT = [11, 6, 3, 1];
const BASE_SPEED = [4 << 16, 2 << 16, 1 << 16, 1 << 15];
const SPINC = [1 << 14, 1 << 15, 1 << 16, 2 << 16, 3 << 16, 4 << 16];

const M = {
    off1: 320 << 16,
    actSize: 0,
    spinc: 2,
    posY: 0,
    posY2: 200,
    stars: [],
    rng: demo.ikSeed(),
};
const offk = (s) => SCALE[s] * M.off1 - (SCALE[s] - 1) * 320 * 65536;
const speed = () => Math.trunc(BASE_SPEED[M.actSize] * SPINC[M.spinc] / 65536);

function rnd16() {
    let x = M.rng;
    x = (x ^ (x << 13)) >>> 0;
    x = (x ^ (x >>> 17)) >>> 0;
    x = (x ^ (x << 5)) >>> 0;
    M.rng = x;
    return (x >>> 16) & 0xFFFF;
}
const roundMul = (r, n) => Math.floor((r * n + 32768) / 65536);
function respawn(st, initial) {
    const x = rnd16(), y = rnd16(), d = rnd16();
    st.x = roundMul(x, 9) * 32;
    st.y = roundMul(y, 354) >> 1;
    st.div = roundMul(d, 4) + 4;
    st.phase = initial ? roundMul(rnd16(), 10) << 16 : 0;
}
for (let i = 0; i < 8; i++) { M.stars.push({ x: 0, y: 0, div: 4, phase: 0 }); respawn(M.stars[i], true); }

function step() {
    M.posY += 2;
    if (M.posY >= 654) M.posY = 0;
    M.posY2 -= 1;
    if (M.posY2 <= 0) M.posY2 = 200;
    for (const st of M.stars) {
        st.phase += Math.floor((65536 + Math.floor(st.div / 2)) / st.div);
        if (st.phase >= 9 << 16) respawn(st, false);
    }
    M.off1 -= speed();
    const total = GLYPHS * 20;
    if (M.off1 <= -(total * 65536)) M.off1 += (total + 320) * 65536;

    const s = M.actSize, tw = 20 * SCALE[s], off = offk(s);
    let left = 0;
    if (off < 0) left = Math.floor(-off / (tw * 65536));
    const visible = Math.ceil(320 / tw) + 1;
    let gp = left + visible;
    if (gp >= GLYPHS) gp = GLYPHS - 1;
    let size = 0;
    for (const c of CHANGES) { if (c.pos <= gp) size = c.size; else break; }
    M.actSize = size;
}

// ---------------- the model's picture --------------------------------------
const content = new Uint8Array(W * H);
function plot(x, y, v) {
    if (x >= 0 && x < W && y >= 0 && y < H) content[y * W + x] = v;
}
function drawContent() {
    content.fill(0);

    const s = M.actSize, kx = SCALE[s], ky = SCALE_Y[s], tw = 20 * kx;
    const off = offk(s);
    let first = 0;
    if (off < 0) first = Math.floor(-off / (tw * 65536));
    if (first < GLYPHS) {
        let xq = off + first * tw * 65536;
        for (let i = first; i < GLYPHS && xq < W * 65536; i++) {
            const g = TILES[s][i];
            if (g >= 0) {
                const x0 = Math.floor(xq / 65536);
                for (let c = 0; c < BAND_COUNT[s]; c++) {
                    const y0 = BAND_Y[s] + c * BAND_STEP[s];
                    for (let r = 0; r < 16; r++) {
                        const base = (g * 16 + r) * 20;
                        for (let cx = 0; cx < 20; cx++) {
                            if (!font[base + cx]) continue;
                            for (let dy = 0; dy < ky; dy++)
                                for (let dx = 0; dx < kx; dx++) plot(x0 + cx * kx + dx, y0 + r * ky + dy, 1);
                        }
                    }
                }
            }
            xq += tw * 65536;
        }
    }

    for (let r = 0; r < 62; r++)
        for (let c = 0; c < 320; c++)
            if (logo[r * 320 + c]) plot(c, 18 + r, 2);

    for (const st of M.stars) {
        const tile = Math.floor((st.phase + 32768) / 65536);
        if (tile >= 10) continue;
        for (let r = 0; r < 23; r++)
            for (let c = 0; c < 32; c++) {
                const v = starAtlas[r * 320 + tile * 32 + c];
                if (v) plot(st.x + c, st.y + r, v);
            }
    }
}

// The HBL's two registers, line by line (rasters.zig's formulas, in 2x units).
function bgColor(phys) {
    if (phys < OY || phys >= OY + H) return BLACK;
    const t = phys - OY;
    if (t === 0 || t === H - 1) return BLACK;
    const y2 = 2 * t;
    if (y2 < 2 || y2 >= 2 + 36 * 11) return BLACK;
    const j = Math.floor((y2 - 2) / 36);
    const index = Math.floor(M.posY / 2) + 2 * j;
    if (index >= 328) return BLACK;
    return RAST2[M.posY + y2 - 2 - 32 * j];
}
function rainbow(phys, shift = 0) {
    if (phys < OY || phys >= OY + H) return BLACK;
    const t = phys - OY;
    let idx = (2 * t - M.posY2 + shift) % 200;
    if (idx < 0) idx += 200;
    return RAST1[idx];
}

const pfb = new Uint32Array(memory.buffer, machine.hwPhysicalPtr(), PFB_W * PFB_H);
function expectedPFB(shift) {
    drawContent();
    const pal0 = new Uint32Array(PFB_H), pal1 = new Uint32Array(PFB_H);
    for (let y = 0; y < PFB_H; y++) { pal0[y] = bgColor(y); pal1[y] = rainbow(y, shift); }
    const out = new Uint32Array(PFB_W * PFB_H);
    for (let y = 0; y < PFB_H; y++) {
        for (let x = 0; x < PFB_W; x++) {
            const lx = x >> 1;
            const inWindow = y >= OY && y < OY + H && lx >= OX && lx < OX + W;
            const idx = inWindow ? content[(y - OY) * W + (lx - OX)] : 0;
            out[y * PFB_W + x] = idx === 0 ? pal0[y] : idx === 1 ? pal1[y] : idx === 2 ? LOGO_RGBA : STAR_RGBA[idx];
        }
    }
    return out;
}
function firstDiff(got, want) {
    for (let i = 0; i < want.length; i++) if (got[i] !== want[i]) return i;
    return -1;
}
const pixelErr = (msg, got, want, i) => {
    const x = i % PFB_W, y = (i / PFB_W) | 0;
    const hx = (v) => "0x" + v.toString(16).padStart(8, "0");
    return `${msg}: physical (${x},${y}) is ${hx(got[i])} not ${hx(want[i])}`;
};

// ---------------- 1. the compiled text --------------------------------------
{
    let bad = null;
    if (demo.ikGlyphCount() !== GLYPHS) bad = `${demo.ikGlyphCount()} glyphs, game.go says ${GLYPHS}`;
    if (!bad && demo.ikChangeCount() !== CHANGES.length) bad = `${demo.ikChangeCount()} changes, game.go says ${CHANGES.length}`;
    for (let i = 0; !bad && i < CHANGES.length; i++) {
        if (demo.ikChange(i, 0) !== CHANGES[i].pos || demo.ikChange(i, 1) !== CHANGES[i].size)
            bad = `change ${i} is (${demo.ikChange(i, 0)},${demo.ikChange(i, 1)}), game.go says (${CHANGES[i].pos},${CHANGES[i].size})`;
    }
    for (let s = 0; !bad && s < 4; s++)
        for (let i = 0; i < GLYPHS; i++)
            if (demo.ikTile(s, i) !== TILES[s][i]) { bad = `tile size ${s} slot ${i} is ${demo.ikTile(s, i)}, model says ${TILES[s][i]}`; break; }
    if (broke === "text") bad = "deliberate --break text";
    ok(!bad, bad ? `text: ${bad}` : `text: ${GLYPHS} glyphs, ${CHANGES.length} control codes and all four tile arrays equal game.go's getFullText()`);
}

// ---------------- 2. music --------------------------------------------------
{
    const pending = demo.pollSongRequest();
    const name = new TextDecoder().decode(new Uint8Array(memory.buffer, demo.songNamePtr(), demo.songNameLen()));
    // F1/F2 below change spinc, so pin the request before touching keys.
    ok(pending === 1 && name === "so_watt_no_crew.sndh" && demo.songTune() === 1,
        pending === 1 ? `music: asked for ${name} #${demo.songTune()}` : "music: no song requested at start");
}

// ---------------- 3. state every frame, pixels at checkpoints ---------------
function checkState(frame) {
    const bad = [];
    if (demo.ikOff() !== M.off1) bad.push(`off1 ${demo.ikOff()} != ${M.off1}`);
    if (demo.ikSize() !== M.actSize) bad.push(`actSize ${demo.ikSize()} != ${M.actSize}`);
    if (demo.ikPosY() !== M.posY) bad.push(`posY ${demo.ikPosY()} != ${M.posY}`);
    if (demo.ikPosY2() !== M.posY2) bad.push(`posY2 ${demo.ikPosY2()} != ${M.posY2}`);
    for (let i = 0; i < 8; i++) {
        const st = M.stars[i];
        const got = [demo.ikStar(i, 0), demo.ikStar(i, 1), demo.ikStar(i, 2), demo.ikStar(i, 3)];
        if (got[0] !== st.x || got[1] !== st.y || got[2] !== st.div || got[3] !== st.phase)
            bad.push(`star ${i} is ${got.join(",")}, model ${st.x},${st.y},${st.div},${st.phase}`);
    }
    if (broke === "state" && frame === 1) bad.push("deliberate --break state");
    return bad.length ? `state frame ${frame}: ${bad[0]}` : null;
}
function comparePixels(frame, shift = 0) {
    const want = expectedPFB(broke === "raster" ? 1 : shift);
    const d = firstDiff(pfb, want);
    if (d >= 0) return pixelErr(`frame ${frame}`, pfb, want, d);
    return null;
}

const EVERY = 300; // every frame to 6 s
const CHECK = [400, 500, 600, 700, 800, 1000, 1200, 1500, 2000, 2500, 3000, 3500, 4000, 4500, 5000, 6000, 7000, 8000, 9000, 10000];
const LAST = 10650; // past the song's loop point (10650 frames)

let compared = 0, distinctMax = 0, failure = null;
const t0 = performance.now();
for (let frame = 1; frame <= LAST; frame++) {
    machine.hwClear();
    step();
    demo.frame(TICK_MS);

    const se = checkState(frame);
    if (se) { failure = se; break; }

    if (frame <= EVERY || CHECK.includes(frame)) {
        machine.hwRenderPlane(0); // composite: this is when the plane's HBL runs
        const pe = comparePixels(frame);
        if (pe) { failure = pe; break; }
        compared++;
        if (frame === 300 || frame === 5000 || frame === 9000) {
            const seen = new Set();
            for (let i = 0; i < pfb.length; i++) seen.add(pfb[i]);
            if (seen.size > distinctMax) distinctMax = seen.size;
        }
        if (frame === 1 || frame === 300 || frame === 5000 || frame === LAST)
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
    ok(compared >= EVERY + CHECK.length, `${compared} frames compared pixel for pixel (every frame to ${EVERY}, plus ${CHECK.length} checkpoints to ${LAST})`);
    ok(distinctMax > 16, `the raster puts ${distinctMax} distinct colours on the 800x280 raster (a static six-entry palette gives at most 6)`);
    ok(machine.hwRamAllocFailures() === 0, "no zg.mem allocation refused");
    console.log(`  ${(ms / LAST).toFixed(3)} ms/frame over ${LAST} frames (update + render + composite + model)`);

    // ---------------- 4. keys -----------------------------------------------
    {
        // F1 steps up, F2 back down again.
        const base = demo.ikSpinc();
        demo.key(0xE001);
        demo.frame(TICK_MS);
        const up = demo.ikSpinc();
        demo.key(0xE002);
        demo.frame(TICK_MS);
        const back = demo.ikSpinc();
        demo.key(0xE002);
        demo.frame(TICK_MS);
        ok(up === base + 1 && back === base && demo.ikSpinc() === base - 1,
            `keys: F1 steps spinc ${base} -> ${up}, F2 back to ${back} and down to ${demo.ikSpinc()}`);

        demo.key(0xE012); // Escape
        demo.frame(TICK_MS);
        ok(demo.pollCartRequest() === -1, "keys: Escape hands the screen back to the menu (pollCartRequest -1)");
    }
    {
        // Back (direction 6) is the second way home; a fresh cart, since quitting
        // latches (declaring key() means the host cannot take Escape back).
        await startCart();
        demo.input(6);
        demo.frame(TICK_MS);
        ok(demo.pollCartRequest() === -1, "keys: Back hands the screen back to the menu (pollCartRequest -1)");
    }
}

if (broke) {
    console.log(errors.length ? `ikplus: PASS (--break ${broke} caught: ${errors[0]})` : `ikplus: FAILED -- --break ${broke} was not caught`);
    process.exit(errors.length ? 0 : 1);
}
console.log(errors.length ? `ikplus: FAILED -- ${errors.join("; ")}` : "ikplus: all pass");
process.exit(errors.length ? 1 : 0);
