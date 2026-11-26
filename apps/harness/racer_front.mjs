// Headless RACER front end (R82 Kestrel Racing M5 step 4, apps/zig/scenes/racer/front.zig, docs/ports/kestrel_racing/M5.md):
//   1. the cart boots on the TITLE (racer,front,title): the logo's three colours drawn over the attract flyby, the screen pinned;
//      Backspace there is refused (no state change); a debug key (t) leaves it for the bare benchmark view (racer,front,off);
//   2. fire: the track SELECT lists OVAL CITY SALT NEON GLACIER MYTRACK (the disk's, then C:\RACER\'s); NOTES.KTR (not a
//      track, refused at the scan) is ON SCREEN by name with its reason, in red; down to GLACIER (its file corrupted here):
//      the loader refuses it, and the screen names it with REFUSED and the loader's reason; CITY says NO RACE (bench only);
//   3. SALT: its outline, its lap length and its own race clock (computed from its line: CLOCK 107S +15S) on screen,
//      the screen pinned; fire races it: grid, then (recorded pilot, warp) countdown ... results;
//   4. the RESULTS screen: RESULTS SALT, the player's row, pinned; fire: the select again, with SALT's best lap now set;
//      Backspace: the title; from a grid, Backspace: the select;
//   5. --break refuse (key J: the scan's refusals not listed), clock (key U: every computed clock back to 75 s + 10 s),
//      fsm (key V: the results' fire goes to the title): each must be caught.
//   node apps/harness/racer_front.mjs [<shot dir>] [--break refuse|clock|fsm] [--print-pins]
import { mkdir, readFile } from "node:fs/promises";
import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { diskHook, fatEntry, ZMD } from "./racer_disk.mjs";
import { bootObj, key } from "./obj_machine.mjs";
import { makeCDrive } from "./scene_hash_disk.mjs";
import { png } from "./skystrike_zig_frame.mjs";

const argv = process.argv.slice(2);
const BREAK = argv.includes("--break") ? argv[argv.indexOf("--break") + 1] : null;
const BREAK_KEY = { refuse: "J", clock: "U", fsm: "V" };
if (BREAK !== null && !BREAK_KEY[BREAK]) { console.error(`racer_front: unknown --break ${BREAK}`); process.exit(1); }
const PRINT = argv.includes("--print-pins");
const OUT = argv[0] && !argv[0].startsWith("--") ? argv[0] : null;
if (OUT) await mkdir(OUT, { recursive: true });
const W = 320, H = 200, Y0 = 12, Y1 = 188, REG_FB_BASE = 0x44, OFF_PAL = 0x0100;
const INK = 3, LOGO = [5, 6, 7], PANEL = 9, HILITE = 10, ALERT = 11; // palette.zig / menu.zig
const PINS = { title: "467ce13b116a", select: "e34ee00efee9", results: "78b10ba937c6" };
const FONT = new Uint8Array(await readFile("libs/zig/assets/fonts/system_font_atari_1bit.raw"));
const errors = [];
const fail = (m) => errors.push(m);
const sha = (px) => createHash("sha256").update(px).digest("hex").slice(0, 12);

const CIMG = `
import sys; sys.path[:0] = ["tools", "fpga/tools"]
import sd_layout; from kos_fat_fixture import Image
img = Image("SD CARD", 2048); hd = sd_layout.HD
img.mkdir(hd); img.mkdir(hd + "/RACER")
img.write(hd + "/RACER/MYTRACK.KTR", open("apps/zig/assets/screens/racer/salt.ktrk", "rb").read())
img.write(hd + "/RACER/NOTES.KTR", b"not a track\\r\\n")
sys.stdout.buffer.write(img.bytes())`;

async function boot() {
    const img = new Uint8Array(await readFile(ZMD));
    const e = fatEntry(img, "GLACIER.KTR");
    img[e.start + (e.len >> 1)] ^= 0xa5; // a byte in the middle of the packed track: the loader refuses it
    const cimg = new Uint8Array(execFileSync("python3", ["-I", "-c", CIMG], { maxBuffer: 8 << 20 }));
    const log = [];
    const S = await bootObj("site/carts/demo-racer.wasm", (s) => log.push(s), (env) => { diskHook(img)(env); env.kosDriveRead = makeCDrive(env.memory, cimg); });
    const shown = () => [0, 1].filter((p) => S.demo.isPlaneEnabled(p))[0] ?? 0;
    const view = () => {
        const vb = S.machine.hwVideoBase(), dv = new DataView(S.memory.buffer, vb, OFF_PAL);
        return new Uint8Array(S.memory.buffer, vb + dv.getUint32(REG_FB_BASE + 4 * shown(), true), W * H).slice();
    };
    const run = (n) => { for (let i = 0; i < n; i++) S.frame(); };
    const tap = (dir) => { S.demo.input(dir); S.demo.inputRelease(dir); run(3); };
    const fronts = () => log.filter((l) => l.startsWith("racer,front,")).map((l) => l.split(",")[2]);
    const until = (want, max) => { for (let i = 0; i < max; i++) { S.frame(); if (fronts().at(-1) === want) return true; } return false; };
    return { S, log, view, run, tap, fronts, until };
}

/** Is `text` on screen in the 8x8 font, ink `ink` on the panels' colour, anywhere (rows Y0..Y1)? */
function onScreen(px, text, ink) {
    for (let y = Y0; y + 8 <= Y1; y++) {
        for (let x = 0; x + 8 * text.length <= W; x++) {
            let ok = true;
            for (let k = 0; ok && k < text.length; k++) {
                const g = FONT.subarray(text.charCodeAt(k) * 64, text.charCodeAt(k) * 64 + 64);
                for (let i = 0; ok && i < 64; i++) if (px[(y + (i >> 3)) * W + x + 8 * k + (i & 7)] !== (g[i] ? ink : PANEL)) ok = false;
            }
            if (ok) return true;
        }
    }
    return false;
}
const viewHash = (px) => sha(px.subarray(Y0 * W, Y1 * W));

async function shot(B, name) {
    if (!OUT) return;
    const vb = B.S.machine.hwVideoBase(), pal = new Uint32Array(B.S.memory.buffer, vb + OFF_PAL, 256).slice();
    await png(`${OUT}/${name}`, Uint32Array.from(B.view(), (v) => (v ? pal[v] : 0xff000000)), W, H);
}

function pin(name, px) {
    const h = viewHash(px);
    if (PRINT) console.log(`PIN ${name} = "${h}"`);
    else if (h !== PINS[name]) fail(`the ${name} screen hashes ${h}, not the pin ${PINS[name]}`);
}

async function title(B) {
    B.run(4);
    if (B.fronts().join(" ") !== "title") fail(`boot: screens ${B.fronts()}, want the title`);
    const px = B.view();
    for (const c of LOGO) if (px.filter((v) => v === c).length < 200) fail(`title: logo colour ${c} has under 200 pixels`);
    pin("title", px);
    await shot(B, "racer_front_title.png");
    key(B.S, "\b");
    B.run(2);
    if (B.fronts().length !== 1) fail(`title: Backspace changed the screen (${B.fronts()})`);
}

async function select(B) {
    B.tap(5);
    if (B.fronts().at(-1) !== "select") return fail(`fire on the title: ${B.fronts()}, want the select`);
    let px = B.view();
    for (const n of ["OVAL", "CITY", "SALT", "NEON", "MYTRACK"]) if (!onScreen(px, n, n === "OVAL" ? HILITE : INK)) fail(`select: ${n} is not listed on screen`);
    if (!onScreen(px, "NOTES", ALERT) || !onScreen(px, "INVALID", ALERT)) fail("select: NOTES.KTR (refused at the scan) is not named on screen with its reason");
    B.tap(1); // CITY: loaded, benchmark only
    if (!onScreen(B.view(), "NO RACE HERE", ALERT)) fail("select: CITY does not say it cannot be raced");
    B.tap(5);
    if (B.fronts().at(-1) !== "select") fail("select: fire on CITY left the select");
    B.tap(1); // SALT
    B.tap(1); // NEON
    B.tap(1); // GLACIER (corrupted): refused by the loader
    px = B.view();
    if (!B.log.some((l) => l.startsWith("racer,track,refused,GLACIER")) || !onScreen(px, "REFUSED:", ALERT) || !onScreen(px, "GLACIER", ALERT))
        fail("select: the corrupted GLACIER is not refused on screen by name");
    B.tap(0); B.tap(0); // back to SALT
    px = B.view();
    if (!onScreen(px, "CLOCK 107S +15S", INK)) fail("select: SALT's own race clock (107 s + 15 s) is not on screen");
    if (!onScreen(px, "LAP 684 M  3 LAPS", INK)) fail("select: SALT's lap length is not on screen");
    pin("select", px);
    await shot(B, "racer_front_select.png");
}

async function race(B) {
    B.tap(5); // pick SALT: the grid
    if (B.fronts().at(-1) !== "off") return fail(`fire on SALT: ${B.fronts()}, want the race (off)`);
    key(B.S, "a"); key(B.S, "w");
    B.tap(5); // fire on the grid starts the countdown
    if (!B.until("results", 3000)) return fail("race: the results screen never shows");
    B.run(2);
    const px = B.view();
    if (!onScreen(px, "RESULTS  SALT", HILITE) || !onScreen(px, "YOU", HILITE)) fail("results: the heading or the player's row is not on screen");
    pin("results", px);
    await shot(B, "racer_front_results.png");
    B.tap(5);
    if (B.fronts().at(-1) !== "select") fail(`fire on the results: ${B.fronts().at(-1)}, want the select`);
    if (onScreen(B.view(), "BEST LAP -:--.-", INK)) fail("select after the race: SALT's best lap was not kept");
    key(B.S, "\b"); B.run(2);
    if (B.fronts().at(-1) !== "title") fail(`Backspace on the select: ${B.fronts().at(-1)}, want the title`);
    B.tap(5); B.tap(5); // the select, then race the cursor's track (SALT): its grid
    key(B.S, "\b"); B.run(2);
    if (B.fronts().slice(-2).join(" ") !== "off select") fail(`Backspace on a grid: ${B.fronts().slice(-3)}, want the select`);
    key(B.S, "t"); B.run(2);
    if (B.fronts().at(-1) !== "off") fail("a debug key (t) on the select did not leave the front end");
}

const B = await boot();
if (BREAK) key(B.S, BREAK_KEY[BREAK]);
await title(B);
await select(B);
await race(B);
if (BREAK) {
    const want = { refuse: "NOTES", clock: "clock", fsm: "results" }[BREAK];
    if (!errors.some((e) => e.includes(want))) { console.error(`racer_front: --break ${BREAK} was NOT caught (${errors.join("; ") || "no errors"})`); process.exit(1); }
    console.log(`racer_front PASS (--break ${BREAK} caught: ${errors.find((e) => e.includes(want))})`);
} else if (errors.length) {
    console.error(errors.map((e) => `racer_front: ${e}`).join("\n"));
    process.exit(1);
} else console.log("racer_front PASS (title -> select -> SALT -> results -> select -> title; refused files named on screen; the per-track clock)");
