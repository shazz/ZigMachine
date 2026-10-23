// Headless REPLICANTS ARKANOID 2 driver (cart 106, CODEF screen 33). Boots the
// sealed machine + the cart the way sealed-loader.js does and holds every frame
// it checks to a model written from the remake's screen.js, not from the Zig:
//
//   music   the cart asks for pro_bmx_simulator_a.sndh (the remake's
//           'Pro BMX Simulator A.ym' as its SNDH), once, at start
//   pixels  the visible 320x200 equals the model's, pixel for pixel, on 1 frame
//           in 3 over 2200 frames: bg.png; the scrolltext ring (22 letters,
//           speed 2/2, 'source-in' bg2.png) straight while go()'s frame counter
//           is <= 500 and waving (fx.sinx, amp 2.5/2, inc 0.22, offset 0.2,
//           rounded to whole pixels) above it; HOFA / SHOGUN / A-TEAM along
//           mycurve (letters 10 entries apart, sprpos += 2, next word past 700).
//           That covers both scroller modes, all three words, the hidden
//           stretch where bg must be back exactly, and a whole 1000-frame cycle.
//   ink     font.png's own red (128,0,0) never reaches the screen
//
//   node apps/replicants_arkanoid2_headless.mjs [outdir]
//   node apps/replicants_arkanoid2_headless.mjs --break skipframe|music   (each must FAIL)
//
// --break skipframe skips the cart for one frame (the model goes on): every
// later picture is one frame off. --break music expects another tune.
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { performance } from "node:perf_hooks";
import { cartRam, romRam } from "../docs/wasm_hiwater.js";

const PAGES = 112; // SHARED_PAGES in machine/sdk/memmap.zig
const ASSETS = "apps/zig/assets/screens/replicants_arkanoid2/";
const BREAKS = ["skipframe", "music"];
const bi = process.argv.indexOf("--break");
const broke = bi > 0 ? process.argv[bi + 1] : null;
if (bi > 0 && !BREAKS.includes(broke)) throw new Error(`--break ${BREAKS.join(" | ")}`);
const OUT = process.argv.slice(2).find((a, i, all) => !a.startsWith("--") && all[i - 1] !== "--break") || "/tmp/replicants_arkanoid2";
await mkdir(OUT, { recursive: true });

// ---------------- boot ------------------------------------------------------
const memory = new WebAssembly.Memory({ initial: PAGES, maximum: PAGES });
let demo;
const machine = (await WebAssembly.instantiate(await readFile("docs/machine-video.wasm"), {
    env: { memory, hblDispatch: (id, p, l, x) => demo.hblDispatch(id, p, l, x) },
})).instance.exports;
const romBytes = await readFile("docs/rom.wasm");
const romEnv = { memory, hwVideoBase: machine.hwVideoBase, hwBlit: machine.hwBlit };
const rom = (await WebAssembly.instantiate(romBytes, { env: romEnv })).instance.exports;
machine.hwSetRomHigh(romRam(romBytes).high ?? 0);
const cartBytes = await readFile("docs/demo-replicants_arkanoid2.wasm");
const env = { ...romEnv, ...rom };
for (const k of Object.keys(machine)) if (k.startsWith("hwRam") || k.startsWith("hwRomRam")) env[k] = machine[k];
const noop = () => {};
for (const imp of WebAssembly.Module.imports(new WebAssembly.Module(cartBytes)))
    if (imp.module === "env" && !(imp.name in env)) env[imp.name] = noop;
demo = (await WebAssembly.instantiate(cartBytes, { env })).instance.exports;
machine.hwSetCartHigh(cartRam(cartBytes).high ?? 0);
machine.hwInit();
demo.boot();
demo.skipBoot();

const errors = [];
const passes = [];
const ok = (cond, msg) => (cond ? passes : errors).push(msg);

// ---------------- music -----------------------------------------------------
{
    const pending = demo.pollSongRequest();
    const name = new TextDecoder().decode(new Uint8Array(memory.buffer, demo.songNamePtr(), demo.songNameLen()));
    const want = broke === "music" ? "pro_bmx_simulator_b.sndh" : "pro_bmx_simulator_a.sndh";
    ok(pending === 1 && name === want, pending === 1 ? `music: asked for ${name}` : "music: no song requested at start");
}

// ---------------- the model (screen.js, halved) -----------------------------
const W = 320, H = 200;
const bg = await readFile(ASSETS + "bg.raw");
const bg2 = await readFile(ASSETS + "bg2.raw");
const font = await readFile(ASSETS + "font.raw");
const pal = await readFile(ASSETS + "palette.dat");
const words = [["hofa", 4, 60], ["shogun", 6, 90], ["ateam", 6, 90]];
const tiles = await Promise.all(words.map(([n]) => readFile(ASSETS + n + ".raw")));
const curveSrc = await readFile("apps/zig/scenes/replicants_arkanoid2/curve.zig", "utf8");
const mycurve = curveSrc.split("const SRC = [_]i16{")[1].split("};")[0].match(/-?\d+/g).map(Number);
if (mycurve.length !== 752) throw new Error(`mycurve: ${mycurve.length} values`);
const TEXT = " THE REPLICANTS PRESENT ARKANOID II (REVENGE OF DOH) . CRACKIND TIME : 40 SECONDS CHRONO, BY  < R.AL > FROM HOFA ON 19.07.88. MEMBERS OF THE REPLICANTS ARE : HOFA ( < R.AL >, DOM, SNAKE, COBRA, GO HAINE !, KNIGHT 2001), A-TEAM (RANK XEROX, HANNIBAL, EXCALIBUR, GOLDORAK), SHOGUN (NINJA). SPECIAL THANX TO MAD MAX AND ES OF TEX FOR THE FANTASTIC MUSIC. GREETINGS TO : THE UNION, B.O.S.S., WAS (NOT WAS), TSUNOO, THE BLADE RUNNERS, ELWOOD, THE LOCKBUSTER. THIS INTRO WAS CODED BY < R.AL >, MUSIC WRITTEN BY MAD MAX AND GRAPHIC BY HOFA. SEE YOU A NEXT TIME.....                        ";

// scrolltext_horizontal: wide = ceil(640/32)+1, letters 0..wide at wide*32 + i*32
const m = { x: [], c: [], off: 0, frame: 0, n: 0, sprpos: 0, name: 0 };
for (let i = 0; i <= 21; i++) { m.x.push((21 * 32 + i * 32) / 2); m.c.push(TEXT.charCodeAt(m.off++)); }

/** One go(): returns what it draws. */
function modelStep() {
    for (let i = 0; i < m.x.length; i++) {
        m.x[i] -= 1;
        if (m.x[i] <= -16) {
            m.x[i] = 21 * 16 + (m.x[i] + 16);
            m.c[i] = TEXT.charCodeAt(m.off++);
            if (m.off > TEXT.length - 1) m.off = 0;
        }
    }
    // fx.sinx row 2r of value 0.2*n; candidates where 1.25*sin sits on a .5
    const shifts = [];
    for (let r = 0; r < 16; r++) {
        const v = Math.sin(0.2 * m.n + 0.22 * 2 * r) * 2.5 / 2;
        const a = Math.round(v) + 0; // + 0: no -0
        const onHalf = Math.abs(Math.abs(v - Math.trunc(v)) - 0.5) < 1e-3;
        const b = onHalf ? (a === Math.floor(v) ? Math.ceil(v) : Math.floor(v)) : a;
        shifts.push([a, b]);
    }
    m.n++;
    m.frame++;
    if (m.frame >= 1000) m.frame = 0;
    const waving = m.frame > 500;
    const draw = { letters: m.x.map((x, i) => [x, m.c[i]]), waving, shifts, sprpos: m.sprpos, name: m.name };
    m.sprpos += 2;
    if (m.sprpos > 700) { m.sprpos = 0; if (++m.name > 2) m.name = 0; }
    return draw;
}

function stripRow(img, d, r, shift) {
    const y = 184 + r;
    for (let x = 0; x < W; x++) img[y * W + x] = bg[y * W + x];
    for (const [lx, c] of d.letters) {
        const nb = c - 32, gx = (nb % 10) * 16, gy = Math.floor(nb / 10) * 16;
        for (let i = 0; i < 16; i++) {
            const x = lx + i + (d.waving ? shift : 0);
            if (x < 0 || x >= W || !font[(gy + r) * 160 + gx + i]) continue;
            img[y * W + x] = bg2[r * W + x];
        }
    }
}

function sprites(img, d) {
    const [, n, tw] = words[d.name];
    for (let i = 0; i < n; i++) {
        const k = (d.sprpos + 10 * (n - 1 - i)) % 710;
        const sx = mycurve[k] / 2, sy = mycurve[k + 1] / 2;
        for (let y = 0; y < 15; y++) for (let x = 0; x < 15; x++) {
            const p = tiles[d.name][y * tw + i * 15 + x];
            const dx = sx + x, dy = sy + y;
            if (p && dx >= 0 && dx < W && dy >= 0 && dy < H) img[dy * W + dx] = p;
        }
    }
}

function picture(d, alt) {
    const img = Uint8Array.from(bg);
    for (let r = 0; r < 16; r++) stripRow(img, d, r, d.shifts[r][alt]);
    sprites(img, d);
    return img;
}

// ---------------- run and compare -------------------------------------------
const pfb = () => new Uint8Array(memory.buffer, machine.hwPhysicalPtr(), machine.hwPhysWidth() * machine.hwPhysHeight() * 4);
const PW = machine.hwPhysWidth();
const rgb = (i) => (pal[i * 4] << 16) | (pal[i * 4 + 1] << 8) | pal[i * 4 + 2];
const screenAt = (b, x, y) => { const o = ((40 + y) * PW + 80 + 2 * x) * 4; return (b[o] << 16) | (b[o + 1] << 8) | b[o + 2]; };

function compare(f, d) {
    const b = pfb();
    const want = [picture(d, 0), picture(d, 1)];
    for (let y = 0; y < H; y++) {
        const rowOk = (img) => { for (let x = 0; x < W; x++) if (screenAt(b, x, y) !== rgb(img[y * W + x])) return x; return -1; };
        const x = rowOk(want[0]);
        if (x >= 0 && rowOk(want[1]) >= 0) return `frame ${f} (${d.waving ? "waving" : "straight"}, ${words[d.name][0]} at sprpos ${d.sprpos}): (${x},${y}) is #${screenAt(b, x, y).toString(16)}, model #${rgb(want[0][y * W + x]).toString(16)}`;
    }
    for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) if (screenAt(b, x, y) === 0x800000) return `frame ${f}: font red at (${x},${y})`;
    return null;
}

async function shot(path) {
    const b = pfb();
    const hdr = new TextEncoder().encode(`P6\n${W} ${H}\n255\n`);
    const buf = new Uint8Array(hdr.length + W * H * 3);
    buf.set(hdr);
    for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) {
        const c = screenAt(b, x, y), o = hdr.length + (y * W + x) * 3;
        buf[o] = c >> 16; buf[o + 1] = (c >> 8) & 255; buf[o + 2] = c & 255;
    }
    await writeFile(path, buf);
}

const FRAMES = 2200;
const SHOTS = new Set([60, 330, 600, 760, 1100]);
let checked = 0, waved = 0, hidden = 0;
const t0 = performance.now();
for (let f = 1; f <= FRAMES; f++) {
    machine.hwClear();
    if (!(broke === "skipframe" && f === 40)) demo.frame(1000 / 60);
    machine.hwRenderPlane(0);
    const d = modelStep();
    if (f % 3 === 0 || (f >= 495 && f <= 510)) {
        const err = compare(f, d);
        if (err) { errors.push(err); break; }
        checked++;
        if (d.waving) waved++;
        if (d.sprpos >= 612) hidden++;
    }
    if (SHOTS.has(f)) await shot(`${OUT}/${String(f).padStart(4, "0")}.ppm`);
}
const ms = (performance.now() - t0) / FRAMES;
ok(errors.length === 0 && waved > 0 && hidden > 0,
    `pixels: ${checked} frames equal the model (${waved} waving, ${hidden} with every letter parked off screen)`);

if (broke) {
    if (errors.length === 0) { console.log(`replicants_arkanoid2: FAIL, --break ${broke} was NOT caught`); process.exit(1); }
    console.log(`replicants_arkanoid2: PASS (--break ${broke} caught: ${errors[0]})`);
    process.exit(0);
}
if (errors.length) {
    console.log("replicants_arkanoid2: WRONG");
    for (const e of errors.slice(0, 12)) console.log("  " + e);
    process.exit(1);
}
console.log(`replicants_arkanoid2: ${passes.join("; ")}; ${ms.toFixed(3)} ms/frame incl. checks; shots in ${OUT}`);
