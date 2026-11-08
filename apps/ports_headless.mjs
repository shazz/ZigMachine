// Headless gate for the C program ports (apps/ports): each port is a GEM program on a DATA disk. The
// machine boots GEM over the committed floppy docs/demo-<tag>.zmd, GEM's FLOPPY window lists the disk,
// a double-click runs BOOT.WSM (request 3: apps/ports_gem.mjs, as docs/sealed-loader.js), and the
// program is driven through the input exports the browser and the board call. Per port:
//   gem       the disk is a data disk whose block 0 is the "SDL" boot sector (docs/boot-sdl.wasm), which asks
//             for request 2 (GEM next); GEM is handed every file of its FAT (<= its cap), and the program
//             it runs depacks to the committed cart docs/demo-<tag>.wasm byte for byte
//   boot      the cart instantiates with nothing but the host's env imports, boot() and every
//             frame run without a trap, plane 0 is enabled
//   ui        the program's screen is there: at least N colours on the physical frame and, at a
//             pinned frame, the frame's sha256 equals the pin (the program's own UI, pixel for pixel)
//   use       one real interaction, checked by what it changes:
//     pt2        DISK OP (a click), then a click on the first file: HYBRID.MOD loads off the floppy
//                (the song-name row changes to its name), then PLAY: the module is heard
//     grafx2     OK closes the read-only-device warning (Asyncify'd modal loop), then a freehand
//                stroke paints pixels in the picture
//     klystrack  the pointer moves over the idle UI; F5 plays STARPRT2.KT (opened off the floppy at boot) on the
//                machine's .kt player: the song is handed over as a .kt that the audio modules play, cyd's stream stops;
//                a note typed while it plays (edit mode on before Play: Space) re-sends it from the row playing
//     chipnomad  X (the A button) on the song screen's first cell puts chain 00 there; then chain 00 gets
//                phrase 00, the phrase a C-4, instrument 00 becomes AY Classic (a fresh project's
//                instruments are type None: silent), and START (Space) plays it: the stream is not silent
//   quit      the program's own quit (pt2 Esc Esc, GrafX2 Q + Discard, klystrack Esc, ChipNomad
//             Settings > Quit) asks for request 4, and GEM's desktop comes back exactly as it was
//   keys      the owner-only key codes (Tab, Home, End, PageUp, PageDown) are pressed before the pinned frame:
//             a port that does not bind them leaves its picture as pinned
//
//   node apps/ports_headless.mjs <pt2|grafx2|klystrack|chipnomad|sidwizard> [--break <x>] [--png <dir>]
//   node apps/ports_headless.mjs pt2 --clock <us>   the board's case: hostMicros advances <us> a frame while
//             dt stays 16.6 ms (a slow frame); the audio feed must follow the clock, not dt (kestrel_audio.h)
// --break SABOTAGES the interaction and passes only if a check notices:
//   pt2 load (the file is never clicked), grafx2 stroke (the stroke is never drawn) or disk (the
//   drive emptied as GEM starts the program: no skin, no font, and GrafX2 stops in boot),
//   klystrack silent (F5 is never pressed), edit (no note typed while it plays) or pointer (the mouse never moves), chipnomad key (X is never pressed) or silent (START is never
//   pressed); every port: quit (the quit is never asked for).
// Pins: re-bless only for a deliberate change to a cart (print them with PINS=1).
import { readFile, mkdir } from "node:fs/promises";
import { machine, step, picture, colours, sha, rows, png, DT } from "./ports_machine.mjs";
import { launchFromGem, serviceQuit } from "./ports_gem.mjs";
import { drainSongs, playKt } from "./ports_kt.mjs";

const QUIT_FRAMES = 120; // after the port's own frames: its quit, and GEM coming back

const F_KEY5 = 0xe005, KEY_X = 0x78, KEY_SPACE = 0x20, SHIFT_LEFT = 0xe015, ESC = 0xe012, DOWN = 1, LEFT = 2, RIGHT = 3;
// Coordinates are each program's own; pointer() takes the visible window's (x doubled), and the
// port's kestrel_input_origin maps them back (pt2: its 320x255 screen starts 28 rows above the window).
const click = (x, y, b, dy = 0) => (d) => d.pointer(x * 2, y + dy, b);
const SPECS = {
    pt2: {
        cart: "docs/demo-pt2.wasm", disk: "docs/demo-pt2.zmd", frames: 300, minColours: 10, breaks: ["load", "quit"],
        pinAt: 90, pin: "0dda0e9b1204ccf6338165770335f77684ec7d0c3ed527584773c85e6bd2aa41",
        // ProTracker blocks input for a second after boot (an error pointer from its startup); then:
        // DISK OP (182..243, 33..43), the first row of the file list (rows of 6 from y 34), PLAY (120..181, 0..10)
        events: (brk) => [
            ...press(100, 212, 38, -28),
            ...(brk === "load" ? [] : press(130, 100, 36, -28)),
            ...press(200, 150, 5, -28),
        ],
        // Esc on the main screen (DISK OP closed itself on the load): "PRESS AGAIN: QUIT", then Esc confirms
        // (kestrel_confirm_quit, split_main.py). ONE_ESC=1 sends only the first: pt2 must not quit.
        quit: (f) => [...tap(f + 5, key(ESC), keyUp(ESC)), ...(process.env.ONE_ESC ? [] : tap(f + 15, key(ESC), keyUp(ESC)))],
        use: usePt2,
    },
    grafx2: {
        cart: "docs/demo-grafx2.wasm", disk: "docs/demo-grafx2.zmd", frames: 240, minColours: 12, breaks: ["stroke", "disk", "quit"],
        pinAt: 90, pin: "611b4ddbec32564355038967a60f34544ccef3cdf5bd7c6a91d29d0c75912a55",
        // OK of the warning box at (160, 163); then a freehand stroke along y = 50 from x 100 to 150
        events: (brk) => [...press(100, 160, 163), ...(brk === "stroke" ? [] : stroke(150, 100, 150, 50)), [200, click(10, 10, 0)]],
        // Q (Quit), then D: "Discard (Quit)" on the box the painted picture raises
        quit: (f) => [...tap(f + 5, key(0x71), keyUp(0x71)), ...tap(f + 20, key(0x64), keyUp(0x64))],
        use: useGrafx2,
    },
    klystrack: {
        cart: "docs/demo-klystrack.wasm", disk: "docs/demo-klystrack.zmd", frames: 280, minColours: 24, breaks: ["silent", "pointer", "edit", "quit"],
        pinAt: 20, pin: "c535877893c812bf1cb6e491a9e6ebe27c5aecf5258c8e661d630fe6e9608d5b",
        // the UI is idle by frame 70 (no repaints: kestrel_sdl.c) and the pointer must still move; F5 at 160,
        // after cyd went quiet (QUIET_AFTER_MS 2.2 s of silence in kestrel_sdl.c = frame ~133 here), so playing also
        // proves the synth wakes up: raise QUIET_AFTER_MS past ~2.6 s and F5 must move later
        events: (brk) => [
            ...(brk === "pointer" ? [] : [[70, click(150, 100, 0)]]),
            ...(brk === "silent" ? [] : [[160, (d) => d.key(F_KEY5)], [163, (d) => d.keyUp(F_KEY5)]]),
            ...(brk === "edit" ? [] : [...tap(150, key(32), keyUp(32)), ...tap(206, key(0x7a), keyUp(0x7a))]),
        ],
        // Esc: Quit; the edit made it "Save song?": Right (No), Return
        quit: (f) => [...tap(f + 5, key(ESC), keyUp(ESC)), ...tap(f + 25, (d) => d.input(RIGHT), (d) => d.inputRelease(RIGHT)), ...tap(f + 35, key(13), keyUp(13))],
        use: useKlystrack,
    },
    chipnomad: {
        cart: "docs/demo-chipnomad.wasm", disk: "docs/demo-chipnomad.zmd", frames: 180, minColours: 5, breaks: ["key", "silent", "quit"],
        pinAt: 20, pin: "a56c75e3bd11582f4b55e0d0e5098a883bc6bdc8bfd5caa1d3b4df0a227f052c",
        // LSDJ keys (README): X = A edits, SELECT (Left Shift) + Right goes song -> chain -> phrase ->
        // instrument, A held + Right steps a value. Each X below puts the next thing in its first cell.
        events: (brk) => [
            ...(brk === "key" ? [] : tap(30, (d) => d.key(KEY_X), (d) => d.keyUp(KEY_X))),
            ...nextScreen(40), ...tap(55, (d) => d.key(KEY_X), (d) => d.keyUp(KEY_X)), // chain: phrase 00
            ...nextScreen(65), ...tap(80, (d) => d.key(KEY_X), (d) => d.keyUp(KEY_X)), // phrase: C-4, instr 00
            ...nextScreen(90), // instrument 00: type None -> AY Classic (A held, Right)
            [105, (d) => d.key(KEY_X)], ...tap(108, (d) => d.input(RIGHT), (d) => d.inputRelease(RIGHT)), [113, (d) => d.keyUp(KEY_X)],
            ...(brk === "silent" ? [] : tap(130, (d) => d.key(KEY_SPACE), (d) => d.keyUp(KEY_SPACE))),
        ],
        // SELECT + Left back to the song screen (from the instrument's), SELECT + Down to SETTINGS, Down to
        // its last row, "Quit ChipNomad", and A on it
        quit: (f) => [...selectTo(f + 5, LEFT), ...selectTo(f + 15, LEFT), ...selectTo(f + 25, LEFT), ...selectTo(f + 35, DOWN),
            ...Array.from({ length: 7 }, (_, i) => tap(f + 45 + 4 * i, (d) => d.input(DOWN), (d) => d.inputRelease(DOWN))).flat(),
            ...tap(f + 80, key(KEY_X), keyUp(KEY_X))],
        use: useChipnomad,
    },
    sidwizard: {
        cart: "docs/demo-sidwizard.wasm", disk: "docs/demo-sidwizard.zmd", frames: 420, minColours: 12, breaks: ["silent", "tab", "quit"],
        pinAt: 300, pin: "e9288624d85a5c035e7ff54990e3744dc62fafa7b8e33c06f923c0a489159193", bindsOwnerKeys: true,
        // FLASHBAK.SWM opens off the floppy at start (the cart's key simulator, as upstream's command line: ~frame
        // 250); Tab (an owner-only code: C64 CONTROL) steps the cursor to track 2; F1 plays
        events: (brk) => [
            ...(brk === "tab" ? [] : tap(262, key(0xe019), keyUp(0xe019))),
            [309, (d, m) => { m.audio.peak = 0; }], // what is heard after F1 (the start-up menu clicks before)
            ...(brk === "silent" ? [] : tap(310, key(0xe001), keyUp(0xe001))),
        ],
        // Shift+F8: SIDwizard.c's exit dialog, Y
        quit: (f) => [[f + 5, key(SHIFT_LEFT)], ...tap(f + 8, key(0xe008), keyUp(0xe008)), [f + 12, keyUp(SHIFT_LEFT)], ...tap(f + 20, key(0x79), keyUp(0x79))],
        use: useSidwizard,
    },
};

// The owner-only key codes (sealed-loader.js OWNER_KEY_CODES: Tab, Home, End, PageUp, PageDown, 2026-11-07, for
// SID-Wizard) pressed and released just before each port's pinned frame: a port that does not know them must
// ignore them, so the pin holds (sidwizard binds them: its pin is taken with them as C64 keys).
const ownerKeys = (f) => [[f, (d) => { for (const c of [0xe019, 0xe01a, 0xe01b, 0xe01c, 0xe01d]) d.key(c); }],
    [f + 1, (d) => { for (const c of [0xe019, 0xe01a, 0xe01b, 0xe01c, 0xe01d]) d.keyUp(c); }]];
// A key or button at frame f, released 2 frames later; SELECT + Right (the next screen) at frame f.
const tap = (f, down, up) => [[f, down], [f + 2, up]];
const selectTo = (f, dir) => [[f, (d) => d.key(SHIFT_LEFT)], ...tap(f + 2, (d) => d.input(dir), (d) => d.inputRelease(dir)), [f + 6, (d) => d.keyUp(SHIFT_LEFT)]];
const nextScreen = (f) => selectTo(f, RIGHT);
const key = (c) => (d) => d.key(c), keyUp = (c) => (d) => d.keyUp(c);

// A left click at frame f: move there the frame before, press, release 6 frames later.
function press(f, x, y, dy = 0) {
    return [[f - 1, click(x, y, 0, dy)], [f, click(x, y, 1, dy)], [f + 6, click(x, y, 0, dy)]];
}
// A drag at frame f: press at (x0, y), move to x1 two pixels a frame, release.
function stroke(f, x0, x1, y) {
    const ev = [[f - 1, click(x0, y, 0)], [f, click(x0, y, 1)]];
    let t = f;
    for (let x = x0 + 2; x <= x1; x += 2) ev.push([++t, click(x, y, 1)]);
    ev.push([t + 1, click(x1, y, 0)]);
    return ev;
}

const args = process.argv.slice(2);
const tag = args[0];
const spec = SPECS[tag];
if (!spec) throw new Error(`usage: node apps/ports_headless.mjs <${Object.keys(SPECS).join("|")}> [--break <x>] [--png <dir>]`);
const opt = (name) => { const i = args.indexOf(name); return i >= 0 ? args[i + 1] : ""; };
const broke = opt("--break"), pngDir = opt("--png"), clockUs = Number(opt("--clock") || 0);
if (broke && !spec.breaks.includes(broke)) throw new Error(`--break ${broke}: ${tag} has ${spec.breaks.join(", ")}`);

let failures = 0;
function check(name, ok, detail = "") {
    if (!ok) failures++;
    console.log(`  ${ok ? "ok  " : "FAIL"}  ${name}${detail ? ": " + detail : ""}`);
}

// Run the cart as the machine does (apps/ports_gem.mjs): GEM over the port's data disk, a double-click
// on BOOT.WSM; then every frame through step(), the scripted events at their frames, a picture kept at
// each frame the checks ask for; then the program's quit and the frames after it (GEM, back). A trap
// (in boot or a frame) ends the run and fails it.
async function run() {
    const quitting = !clockUs && broke !== "disk"; // --break disk pulls the drive: no desktop to come back to
    const events = [...(spec.bindsOwnerKeys ? [] : ownerKeys(spec.pinAt - 4)), ...spec.events(broke), ...(quitting && broke !== "quit" ? spec.quit(spec.frames) : [])];
    const frames = spec.frames + (quitting ? QUIT_FRAMES : 0), shots = new Map(), audio = { peak: 0, n: 0, rate: 0 };
    let trap = "", m = { demo: { isPlaneEnabled: () => 0 }, audio, songs: [] }, gem = null, plane0 = 0, last = "";
    try {
        m = await machine(await readFile(spec.disk), clockUs);
        m.songs = [];
        gem = await launchFromGem(m, spec.cart, broke === "disk"); // --break disk: the drive pulled as it starts
        for (let f = 1; f <= frames; f++) {
            if (!m.backs) for (const [ef, fn] of events) if (ef === f) fn(m.demo, m); // the program's events, until it quits
            step(m);
            drainSongs(m, f);
            if (f === spec.frames) plane0 = m.demo.isPlaneEnabled(0);
            serviceQuit(m);
            if (spec.keep(f)) shots.set(f, picture(m));
        }
        last = sha(picture(m).px);
    } catch (e) { trap = String(e) + (m.log?.length ? ` (the cart's last words: ${m.log.slice(-3).join(" / ")})` : ""); }
    return { m, shots, trap, gem, plane0, last, quitting };
}

// The disk is a GEM data disk, GEM lists all of it, and what it runs is the committed cart; the program's
// quit brings the desktop back exactly as it was (request 4).
function useGem(r) {
    const g = r.gem;
    if (!g) return check("GEM launches the program", false, r.trap);
    check("data disk: GEM boots for it", g.dataDisk);
    check("block 0 is the SDL boot sector (docs/boot-sdl.wasm), $1234", g.sector.ours);
    check("the sector asks for request 2, no cart named: GEM boots after it", g.sector.chains, `after ${g.sector.frames} frames`);
    check("GEM lists every file", g.files.length <= g.max, `${g.files.length} of ${g.max}: ${g.files.join(" ")}`);
    check("GEM runs BOOT.WSM, the committed cart", g.name === "BOOT.WSM" && g.same, `${g.name}${g.same ? " = " : " != "}${spec.cart}`);
    if (!r.quitting) return;
    check("quit returns to the desktop", r.m.backs === 1 && r.last === g.desk, `${r.m.backs} request 4, desktop ${r.last === g.desk ? "as it was" : "differs"}`);
}

function useCommon(r) {
    check("boot and frames", !r.trap, r.trap || `${spec.frames} frames, no trap`);
    check("plane 0 enabled", r.plane0 === 1);
    const ui = r.shots.get(spec.pinAt);
    if (!ui) return check("ui", false, `no picture at frame ${spec.pinAt}`);
    const n = colours(ui), h = sha(ui.px);
    check("ui colours", n >= spec.minColours, `${n} colours at frame ${spec.pinAt} (>= ${spec.minColours})`);
    if (process.env.PINS) console.log(`  pin ${tag} @${spec.pinAt}: ${h}`);
    check("ui pin", h === spec.pin, h === spec.pin ? `frame ${spec.pinAt} = ${h.slice(0, 16)}...` : `got ${h}`);
}

// pt2's song-name row is its line y 99..109, at 12 + y on the physical frame.
function usePt2(r) {
    const name = (f) => r.shots.get(f) && sha(rows(r.shots.get(f), 111, 121));
    check("pt2 DISK OP opens", r.shots.get(120) && sha(r.shots.get(120).px) !== sha(r.shots.get(90).px), "the screen changed after the click");
    check("pt2 module loads off the floppy", name(190) && name(190) !== name(90), "the song-name row changed (HYBRID.MOD's 'setup2')");
    check("pt2 module plays", r.m.audio.peak > 8, `peak |s8| ${r.m.audio.peak} after PLAY, ${r.m.audio.n} samples fed`);
}
SPECS.pt2.keep = (f) => [90, 120, 190, 300].includes(f);

// The stroke's line: y 50 is physical row 90, x 100..150 physical 280..380 (low res doubled).
function useGrafx2(r) {
    const before = r.shots.get(90), after = r.shots.get(120), drawn = r.shots.get(240);
    check("grafx2 warning closes on OK", before && after && sha(before.px) !== sha(after.px));
    check("grafx2 main screen", after && colours(after) >= 40, `${after ? colours(after) : 0} colours: tool bar, palette (>= 40)`);
    let lit = 0;
    if (drawn) {
        const line = rows(drawn, 90, 90);
        for (let x = 284; x < 376; x += 2) if (line[x * 4] | line[x * 4 + 1] | line[x * 4 + 2]) lit++;
    }
    check("grafx2 freehand stroke paints", lit >= 40, `${lit} of 46 pixels along the stroke lit`);
}
SPECS.grafx2.keep = (f) => [90, 120, 240].includes(f);

// F5 plays the song on the machine's .kt player (apps/ports/klystrack/kestrel_bard.c): the cart hands it over
// as a .kt (requestSongBytes, kind 5, row 0) that the audio modules play; cyd's stream stops.
const sameBytes = (a, b) => a.length === b.length && a.every((v, i) => v === b[i]);

async function useKlystrack(r) {
    const kt = r.m.songs.find((s) => s.kind === 5);
    check("klystrack hands STARPRT2.KT to the .kt player", kt && kt.row === 0 && kt.bytes.length > 1000,
        kt ? `frame ${kt.frame}: ${kt.bytes.length} B from row ${kt.row}` : `no song image asked for (${r.m.songs.length} requests)`);
    const p = kt ? await playKt(kt.bytes, kt.row) : { ok: false };
    check("the .kt player plays it", p.ok && p.mode === 1 && p.rms > 0.01 && p.peak <= 1,
        p.ok ? `mode ${p.mode}, rms ${p.rms.toFixed(3)}, peak ${p.peak.toFixed(3)}` : `refused (error ${p.error})`);
    check("cyd's stream stops while it plays", (r.m.audio.stops || 0) >= 1, `${r.m.audio.stops || 0} stream stop(s)`);
    // An edit while it plays (Space, then z at frame 206) re-sends the song, from the row playing.
    const again = kt && r.m.songs.find((s) => s.kind === 5 && s.frame > 206);
    check("an edit while it plays re-sends it", !!again && again.row > 0 && !sameBytes(again.bytes, kt.bytes),
        again ? `frame ${again.frame} (${again.frame - 206} frames after the key), from row ${again.row}, ${again.bytes.length} B` : "not re-sent");
    // (Esc's quit needs no "none": the host resets the players when the next program starts, GEM here.)
    const a = r.shots.get(20), b = r.shots.get(270);
    check("klystrack screen follows play", a && b && sha(a.px) !== sha(b.px));
    const p0 = r.shots.get(65), p1 = r.shots.get(75);
    check("klystrack pointer moves over the idle UI", p0 && p1 && sha(p0.px) !== sha(p1.px), "frame 75 differs from 65 (no repaint between)");
}
SPECS.klystrack.keep = (f) => [20, 65, 75, 270].includes(f);

function useChipnomad(r) {
    const a = r.shots.get(20), b = r.shots.get(38);
    check("chipnomad X puts a chain in the song", a && b && sha(rows(a, 70, 79)) !== sha(rows(b, 70, 79)), "row 00 of the song changed");
    check("chipnomad plays the note", r.m.audio.peak > 8, `peak |s8| ${r.m.audio.peak}, ${r.m.audio.n} samples at ${r.m.audio.rate} Hz`);
}
SPECS.chipnomad.keep = (f) => [20, 38].includes(f);

// A rectangle of the physical picture (x0..x1, y0..y1 inclusive), for a region hash.
function rect(pic, x0, y0, x1, y1) {
    const out = [];
    for (let y = y0; y <= y1; y++) out.push(pic.px.subarray((y * pic.W + x0) * 4, (y * pic.W + x1 + 1) * 4));
    return Buffer.concat(out);
}

// SID-Wizard (apps/ports/sidwizard): its C64 picture sits at (30,13) of the 400x280 plane, text row k at y 36 + 8k,
// column c at x 40 + 8c (x doubled on the physical frame). Track 2's first row is columns 10..19 of row 0 (the
// cursor is on track 1 until Tab).
function useSidwizard(r) {
    check("sidwizard opens FLASHBAK.SWM off the floppy at start", r.m.log.includes("sidwizard: song opened"), r.m.log.slice(-2).join(" / "));
    const a = r.shots.get(258), b = r.shots.get(270), row0 = (p) => sha(rect(p, 240, 36, 399, 43));
    check("sidwizard Tab (an owner-only key code) steps the cursor to track 2", a && b && row0(a) !== row0(b), "the cursor sprite is over track 2, row 0");
    check("sidwizard F1 plays the song", r.m.audio.peak > 8, `peak |s8| ${r.m.audio.peak} after F1, ${r.m.audio.n} samples at ${r.m.audio.rate} Hz`);
}
SPECS.sidwizard.keep = (f) => [258, 270, 300].includes(f);

// The feed follows the host clock: every frame but the first (no clock yet: its dt) owes clockUs of
// audio, on top of the lead the stream starts with (pt2: 125 ms). Fixed rate/60 a frame fails this.
function useClock(r) {
    check("boot and frames", !r.trap, r.trap || `${spec.frames} frames, no trap`);
    const a = r.m.audio, lead = Math.floor(a.rate * spec.leadMs / 1000);
    const want = Math.floor(a.rate * (DT / 1000 + (spec.frames - 1) * clockUs / 1e6)) + lead;
    check("audio follows the host clock", Math.abs(a.n - want) <= 2, `${a.n} samples fed at ${a.rate} Hz for ${spec.frames} frames of ${clockUs} us (want ${want})`);
}
SPECS.pt2.leadMs = 125; // kestrel_sdl.c AUDIO_LEAD_MS

console.log(`${tag}: ${spec.cart} + ${broke === "disk" ? "an EMPTY drive" : spec.disk}${broke ? ` (--break ${broke})` : ""}`);
const r = await run();
useGem(r);
if (clockUs) useClock(r);
else {
    useCommon(r);
    await spec.use(r);
}
if (pngDir) {
    await mkdir(pngDir, { recursive: true });
    for (const [f, p] of r.shots) await png(p, `${pngDir}/${tag}_${f}.png`);
}
if (broke) {
    console.log(failures ? `\n${tag}: PASS (--break ${broke} was caught)` : `\n${tag}: FAILED - --break ${broke} was not caught`);
    process.exit(failures ? 0 : 1);
}
console.log(failures ? `\n${tag}: ${failures} FAILED` : `\n${tag}: PASS`);
process.exit(failures ? 1 : 0);
