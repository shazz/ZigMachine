// KOS GEMDOS's proof in a real program (docs/KOS_GEMDOS.md §6): GrafX2, started from GEM over its floppy as
// the machine starts it (apps/ports_gem.mjs), with docs/gemdos-c.img as C: (tools/gemdos_c_image.py: the
// card's HD folder, the page's ?c=, the native host's --c-image). Through GrafX2's own file selector:
//   F3 (Load picture), "Select drive": the drive list offers "/C" (C: mounted) beside "/" (the floppy)
//   /C            C:\ lists its folders (PICTURES, TEXTS) and ".." (GrafX2's way back to "/")
//   PICTURES      C:\PICTURES lists ZIGWAVES.PI1 and the folder PLASMA
//   PLASMA        C:\PICTURES\PLASMA, three levels down, lists ZIGPLASM.PI1 / .NEO
//   ZIGPLASM.PI1  double-clicked: the picture loads. The ORACLE: its frame equals, hash for hash, the frame
//                 of a second run that loads the floppy's own ZIGPLASM.PI1 (the same bytes, the same pointer)
// and the whole session asks C: at most MAX_TRIPS round trips (the board's cost: ~0.5 ms each).
// The selector's views are pinned (PINS=1 prints them). --break SABOTAGES and passes only if caught:
//   c      C: answers nothing (kosDriveRead 0, as a board whose glass does not serve): no "/C"
//   bytes  one byte of the picture on C: is changed: the loaded frame must differ from the floppy's
//   node apps/gemdos_grafx2_check.mjs [--break c|bytes] [--png <dir>]
import { readFile, mkdir } from "node:fs/promises";
import { machine, step, picture, sha, png } from "./ports_machine.mjs";
import { launchFromGem } from "./ports_gem.mjs";
import { makeCDrive } from "./scene_hash_disk.mjs";

const CART = "docs/demo-grafx2.wasm", DISK = "docs/demo-grafx2.zmd", C_IMAGE = "docs/gemdos-c.img";
const PICTURE = "apps/ports/grafx2/ownpics/ZIGPLASMA.PI1"; // on the floppy and on C: as ZIGPLASM.PI1
const F3 = 0xe003, MAX_TRIPS = 16;
const PINS = {
    drives: "1d2820e89d020e67bf3eef207e98e9be942cf9ed8a800a0ac091c326b7061bd8", // frame 188: the drive list, "/" and "/C"
    root: "e98ad114c637814b5f052bd96b77e9ad7f32868a1c7f83599e4e1fda08618bb7", // 228: C:\ (.., PICTURES, TEXTS)
    pictures: "b703131764859cdb892d7250d318a32883b9a991cfd4e2517980ca43fb56f9eb", // 258: C:\PICTURES
    plasma: "9562d77d68b8d02f1bb89152725fb30818ffbbb78301c45fe48b0d9230debf6f", // 288: C:\PICTURES\PLASMA
};
// pointer() takes the visible window's x (doubled); rows of the selector's list are 8 lines apart.
const at = (f, x, y, b) => [f, (d) => d.pointer(x * 2, y, b)];
const click = (f, x, y) => [at(f - 1, x, y, 0), at(f, x, y, 1), at(f + 6, x, y, 0)];
const twice = (f, x, y) => [at(f - 1, x, y, 0), at(f, x, y, 1), at(f + 1, x, y, 0), at(f + 3, x, y, 1), at(f + 4, x, y, 0)];
const key = (f, k) => [[f, (d) => d.key(k)], [f + 2, (d) => d.keyUp(k)]];
const START = [...click(100, 160, 163), ...key(130, F3)]; // OK on the read-only warning, then Load picture
const VIA_C = [...START, ...click(160, 37, 28), ...twice(190, 30, 107), ...twice(230, 30, 105), ...twice(260, 30, 106), ...twice(290, 30, 114)];
const VIA_FLOPPY = [...START, ...twice(160, 30, 114)]; // the floppy's listing: ZIGPLASM.PI1 is its third row
const SHOTS_C = { drives: 188, root: 228, pictures: 258, plasma: 288, loaded: 338 }, LOADED_FLOPPY = 338;

const args = process.argv.slice(2);
const opt = (name) => { const i = args.indexOf(name); return i >= 0 ? args[i + 1] : ""; };
const broke = opt("--break"), pngDir = opt("--png");
if (broke && !["c", "bytes"].includes(broke)) throw new Error(`--break ${broke}: c or bytes`);

let failures = 0;
function check(name, ok, detail = "") {
    if (!ok) failures++;
    console.log(`  ${ok ? "ok  " : "FAIL"}  ${name}${detail ? ": " + detail : ""}`);
}

// One session: GEM over the floppy, GrafX2 launched off it, the events, a picture at each frame asked.
async function session(events, shots, image) {
    const m = await machine(await readFile(DISK));
    let trips = 0;
    if (image) {
        const serve = makeCDrive(m.memory, image);
        m.env.kosDriveRead = (...a) => { trips++; return serve(...a); };
    }
    const gem = await launchFromGem(m, CART);
    trips = 0; // GEM's own walk of C: is the desktop's, not GrafX2's
    const last = Math.max(...Object.values(shots)), pics = {};
    for (let f = 1; f <= last; f++) {
        for (const [ef, fn] of events) if (ef === f) fn(m.demo);
        step(m);
        for (const [name, sf] of Object.entries(shots)) if (sf === f) pics[name] = picture(m);
    }
    return { gem, pics, trips };
}

async function cImage() {
    const img = new Uint8Array(await readFile(C_IMAGE));
    if (broke === "c") return null;
    if (broke === "bytes") {
        const pic = new Uint8Array(await readFile(PICTURE));
        const off = Buffer.from(img).indexOf(Buffer.from(pic.subarray(0, 64)));
        if (off < 0) throw new Error(`${PICTURE} is not on ${C_IMAGE}`);
        img[off + 4000] ^= 0xff; // a byte of its bitplanes
    }
    return img;
}

console.log(`gemdos_grafx2: GrafX2 off ${DISK}, C: = ${C_IMAGE}${broke ? ` (--break ${broke})` : ""}`);
const viaC = await session(VIA_C, SHOTS_C, await cImage());
const viaFloppy = await session(VIA_FLOPPY, { loaded: LOADED_FLOPPY }, new Uint8Array(await readFile(C_IMAGE)));
check("GEM runs BOOT.WSM, the committed cart", viaC.gem.name === "BOOT.WSM" && viaC.gem.same);
const h = Object.fromEntries(Object.entries(viaC.pics).map(([k, p]) => [k, sha(p.px)]));
if (process.env.PINS) for (const k of Object.keys(PINS)) console.log(`  pin ${k}: ${h[k]}`);
for (const k of Object.keys(PINS)) check(`selector view ${k} (frame ${SHOTS_C[k]})`, h[k] === PINS[k], h[k] === PINS[k] ? `${h[k].slice(0, 16)}...` : `got ${h[k]}`);
const fromFloppy = sha(viaFloppy.pics.loaded.px);
check("the picture loaded from C:\\PICTURES\\PLASMA equals the floppy's", h.loaded === fromFloppy && h.loaded !== h.plasma,
    `frame ${SHOTS_C.loaded} ${h.loaded.slice(0, 16)}... vs ${fromFloppy.slice(0, 16)}...`);
check(`C: asked at most ${MAX_TRIPS} round trips`, viaC.trips > 0 && viaC.trips <= MAX_TRIPS, `${viaC.trips} (mount, three folders, a 32 KB picture)`);
if (pngDir) {
    await mkdir(pngDir, { recursive: true });
    for (const [k, p] of Object.entries(viaC.pics)) await png(p, `${pngDir}/gemdos_${k}.png`);
}
if (broke) {
    console.log(failures ? `\ngemdos_grafx2: PASS (--break ${broke} was caught)` : `\ngemdos_grafx2: FAILED - --break ${broke} was not caught`);
    process.exit(failures ? 0 : 1);
}
console.log(failures ? `\ngemdos_grafx2: ${failures} FAILED` : "\ngemdos_grafx2: PASS");
process.exit(failures ? 1 : 0);
