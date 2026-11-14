// ARE YOU SITTING COMFORTABLY? (cart "falcon_ays", apps/zig/scenes/falcon_ays.zig): Reservoir Gods'
// Falcon intro, its parts fired by the MOD's 8xx script on the song's clock. Boots the committed cart
// over the real machine + ROM, runs the show frame by frame (60 Hz, no sound: the frame clock) and
// renders plane 0 through the machine (hwClear + hwRenderPlane) at checkpoints.
//   setup    plane 0 is the only plane enabled, FB_MODE 5 (true colour, 320x200 window); the cart
//            asks for falcon_ays.mod on its first frame
//   script   black before the first blob command (8xx 0B at 17.92 s) and in the gap the 807 at
//            17.08 s opens; blobs after it: colours, lines doubled by the copper list (mode 805),
//            pixels paired; the blobs move frame to frame; each blob variant (80B, 80D, 810, 80F,
//            80E) shows a different picture at its time
//   art      the original's data is what is drawn (apps/zig/assets/screens/falcon_ays/, ripped by
//            tools/falcon_ays_art.py): the text at 10 s only in the text palette's colours, the
//            80B blobs at 18.5 s only in the purple LUT's, the ship at 38.5 s (the bounce over) the
//            ripped picture pixel for pixel, the credits' CODE plaque at 75 s (>= 95 %: particles
//            fly over it), the flames at 130 s on plane 1 alone (8-bit, CHISEL MAP), every pixel of
//            the 150 lines a colour of the fireball texture
//   escape   Escape asks to leave (pollCartRequest -1)
//   node apps/falcon_ays_headless.mjs [outdir]   (outdir: a PPM per checkpoint)
//   node apps/falcon_ays_headless.mjs --break script   the blob checkpoints moved 3 s early must fail
//   node apps/falcon_ays_headless.mjs --break art      the ship compared one pixel off must fail
import { readFile, writeFile } from "node:fs/promises";
import { boot, at, W, H } from "./falcon_ays_boot.mjs";

const REG_FB_MODE = 0x54;
const ART = "apps/zig/assets/screens/falcon_ays";
const BRK = process.argv.includes("--break") ? process.argv[process.argv.indexOf("--break") + 1] : null;
const outdir = process.argv.slice(2).find((a, i, all) => !a.startsWith("--") && all[i - 1] !== "--break");

const lit = (img) => img.reduce((n, v) => n + (v !== 0), 0);
const colours = (img) => new Set(img).size;
const same = (a, b) => a.every((v, i) => v === b[i]);
function linesDoubled(img) {
    for (let y = 0; y < H; y += 2) for (let x = 0; x < W; x++) if (img[y * W + x] !== img[(y + 1) * W + x]) return false;
    return true;
}
function pixelsPaired(img) {
    for (let i = 0; i < W * H; i += 2) if (img[i] !== img[i + 1]) return false;
    return true;
}
async function ppm(name, img) {
    if (!outdir) return;
    const head = Buffer.from(`P6 ${W} ${H} 255\n`);
    const body = Buffer.alloc(W * H * 3);
    img.forEach((v, i) => { body[i * 3] = v & 255; body[i * 3 + 1] = (v >> 8) & 255; body[i * 3 + 2] = v >> 16; }); // RGBA bytes: R low
    await writeFile(`${outdir}/falcon_ays_${name}.ppm`, Buffer.concat([head, body]));
}

const errors = [];
const want = (ok, msg) => { if (!ok) errors.push(msg); };
const m = await boot();

// setup
m.demo.frame(1000 / 60); m.frame++;
const song = m.demo.pollSongRequest() ? new TextDecoder().decode(new Uint8Array(m.memory.buffer, m.demo.songNamePtr(), m.demo.songNameLen())) : null;
want(song === "falcon_ays.mod", `setup: first frame asked for ${song}, not falcon_ays.mod`);
const dv = new DataView(m.memory.buffer);
want(dv.getUint8(m.video + REG_FB_MODE) === 5, `setup: plane 0 FB_MODE ${dv.getUint8(m.video + REG_FB_MODE)}, not 5 (true colour window)`);
for (let p = 1; p < 8; p++) want(!m.demo.isPlaneEnabled(p), `setup: plane ${p} enabled`);

// script: the blob variants at their times (s), black before and in the 807 gap
const early = BRK === "script" ? 3 : 0;
const black = [5, 17.2].map((t) => [t, at(m, t)]);
for (const [t, img] of black) { want(lit(img) === 0, `script: ${lit(img)} lit pixels at ${t} s, before the blobs`); await ppm(`black_${t}`, img); }
const blobT = [18.5, 23.0, 27.5, 33.0, 54.5].map((t) => t - early); // 80B, 80D, 810, 80F, 80E
const pics = [];
for (const t of blobT) {
    const img = at(m, t);
    pics.push(img);
    await ppm(`blobs_${t}`, img);
    want(lit(img) > 50 && colours(img) > 4, `script: blobs at ${t} s: ${lit(img)} lit pixels, ${colours(img)} colours`);
    want(linesDoubled(img), `script: blobs at ${t} s: lines not doubled (mode 805)`);
    want(pixelsPaired(img), `script: blobs at ${t} s: pixels not paired (160 wide)`);
    const next = at(m, t + 0.1);
    want(!same(img, next), `script: blobs frozen at ${t} s`);
}
for (let i = 1; i < pics.length; i++) want(!same(pics[i - 1], pics[i]), `script: blob variants ${i - 1} and ${i} draw the same picture`);
console.log(`  blobs: ${pics.map((p) => `${lit(p)} px/${colours(p)} col`).join(", ")}`);

// art: the original's data on screen (a second machine: the checkpoints run forwards again)
const be565 = (buf, i) => (buf[i * 2] << 8) | buf[i * 2 + 1];
const set565 = (buf, from, n) => new Set(Array.from({ length: n }, (_, k) => be565(buf, from + k)));
const to565 = (v) => (((v & 255) >> 3) << 11) | ((((v >> 8) & 255) >> 2) << 5) | ((v >> 16) >> 3);
const outside = (img, set, rows = [0, H]) => {
    let n = 0;
    for (let y = rows[0]; y < rows[1]; y++) for (let x = 0; x < W; x++) n += !set.has(to565(img[y * W + x]));
    return n;
};
const a = await boot();
const textPal = set565(await readFile(`${ART}/text_pal.bin`), 0, 128);
const purple = set565(await readFile(`${ART}/blob_luts.bin`), 0x400, 256); // 0x800 bytes in
const ship = await readFile(`${ART}/ship.bin`);
const plaque = await readFile(`${ART}/plaque_code.bin`);
const fire = set565(await readFile(`${ART}/flame_tex_a.bin`), 0, 65536);
fire.add(0); fire.add(0xFFFF);
let img = at(a, 10);
want(lit(img) > 1000 && outside(img, textPal) === 0, `art: text at 10 s: ${outside(img, textPal)} pixels off the text palette`);
img = at(a, 18.5);
want(lit(img) > 500 && outside(img, purple) === 0, `art: blobs at 18.5 s: ${outside(img, purple)} pixels off the purple LUT`);
img = at(a, 38.5);
const shift = BRK === "art" ? 1 : 0;
let off = 0;
for (let y = 0; y < H; y++) for (let x = 0; x < W - 1; x++) off += to565(img[y * W + x]) !== be565(ship, y * W + x + shift);
want(off === 0, `art: ship at 38.5 s: ${off} pixels differ from the ripped picture`);
await ppm("ship", img);
img = at(a, 75);
const pw = (plaque[2] << 8) | plaque[3], ph = (plaque[4] << 8) | plaque[5];
let hit = 0;
for (let y = 0; y < ph; y++) for (let x = 0; x < pw; x++) hit += to565(img[(H - ph + y) * W + W - pw + x]) === be565(plaque, 3 + y * pw + x);
want(hit >= 0.95 * pw * ph, `art: credits at 75 s: the CODE plaque matches ${hit} of ${pw * ph} pixels`);
await ppm("credits", img);
img = at(a, 130);
want(a.demo.isPlaneEnabled(1) && !a.demo.isPlaneEnabled(0), "art: flames at 130 s: not plane 1 alone");
want(lit(img) > 10000 && outside(img, fire, [25, 175]) === 0, `art: flames at 130 s: ${outside(img, fire, [25, 175])} pixels off the texture's colours`);
await ppm("flames", img);
console.log("  art: text palette, purple LUT, the ship picture, the CODE plaque, the fireball's colours");

// escape
m.demo.key(0xE012);
want(m.demo.pollCartRequest() === -1, "escape: Escape did not ask to leave");

// exitCode, never process.exit() (node 24 deadlocks at exit: apps/mod_sfx_check.mjs).
if (BRK) {
    const hit = errors.find((e) => e.startsWith(`${BRK}:`));
    console.log(hit ? `falcon_ays: PASS (--break ${BRK} caught: ${hit})` : `falcon_ays: FAILED -- --break ${BRK} not caught`);
    process.exitCode = hit ? 0 : 1;
} else {
    console.log(errors.length ? `falcon_ays: FAILED -- ${errors.join("; ")}` : "falcon_ays: all pass");
    process.exitCode = errors.length ? 1 : 0;
}
