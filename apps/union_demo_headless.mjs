// Headless Union Demo menu driver: boots the sealed machine + demo-union_demo.wasm
// the way docs/sealed-loader.js does, walks Charly through a scripted timeline and
// dumps the visible 320x200 screen as PPMs, plus the frame cost. Then it CHECKS:
//
//   wrap   teleport to the last door (key 0), walk right with F1 but NO fire until
//          Charly must be past the street's end, then hold fire: the view keeps
//          scrolling across the seam, no door is entered before it, the first door
//          entered is the lowest-x ported one (derived from doors.zig, menu_map.zig
//          and charly.zig: see expectedWrapDoor), and the hub's ROM note puts
//          Charly below the start, inside that door: he really wrapped.
//   stop   a key held like a browser auto-repeats it (press, 500 ms, then every
//          33 ms), released anywhere from 550 to 1500 ms, on a 60 Hz and on a
//          144 Hz display: the street always stops moving within STOP_MS (the
//          60 ms input window + the original's 9-step friction tail + a frame).
//   ease   walk left from the spawn, where the view is clamped at 0 like the
//          remake's, across the seam: when the clamp lets go the view eases onto
//          Charly (his screen x moves at most EASE_PX a step) and ends centred.
//   keyup  with the host's key-up (demo.inputRelease), a 100 ms tap stops as fast.
//          docs/sealed-loader.js sends it from its keyup listener (and releases
//          every held direction on blur); `stop` models an older host without it.
//          Both FAIL on a cart built before inputRelease existed.
//   esc    Escape and Back ask the host for NOTHING (they used to ask for the
//          menu disk), while the doors still open: the hub is left through a door.
//   return the hub fires at door 9 (it leaves a note in the ROM's scratch bytes),
//          the door's disk boots, then a FRESH hub cart over the same memory and
//          ROM, as the page swaps back: Charly stands where he left and the
//          scroller resumes its text. The note is used once, and a fresh page
//          (new memory + ROM) starts at the spawn.
//   door   the hub -> door swap in the page's order (disk, ROM unpack, instantiate,
//          romReset, hwInit, boot, skipBoot) shows the TEX loader panel.
//
// The timeline is the one the ORIGINAL remake was traced with in Chrome (one
// requestAnimationFrame per step), so shot N here is comparable to reference
// frame N: the reference had run 3 frames before its frame 0, so we pre-roll 3,
// after the menu's graphics depack behind menuloader.js's TEX panel.
// A held range sends an event every frame and stops HOLD_TAIL frames early: the
// scene keeps a repeating direction held for 60 ms after its last event.
//
//   node apps/union_demo_headless.mjs [outdir] [cart.wasm]
//   node apps/union_demo_headless.mjs --break return [outdir]   # must FAIL `return`
//   node apps/union_demo_headless.mjs --break wrap [outdir]     # fire from the start: must FAIL `wrap`
import { readFile, writeFile, mkdir } from "node:fs/promises";
import { performance } from "node:perf_hooks";
import { cartRam, romRam } from "../docs/wasm_hiwater.js";

const PAGES = 112; // SHARED_PAGES in machine/sdk/memmap.zig
const PREROLL = 3;
const HOLD_TAIL = 3; // frames held after the last event: 3 x 16.6 ms < 60 ms
const DT = 16.6;
const TEX_INK = [0xc0, 0xa0, 0x00]; // the TEX loader panel's ink
const DIR = { up: 0, down: 1, left: 2, right: 3, fire: 5, back: 6 };
const K_F1 = 0xe001;
const K_ESC = 0xe012; // host KEY_CODES.Escape
const STREET = [116, 159]; // screen rows of pavement: only Charly and the view change them
const EASE_PX = 32; // screen px a step: the 8-step ease moves ~20-25, a snap 161
const STOP_MS = 250; // 60 ms window + 9 x 16.7 ms of friction (0.5 a step from 5 px) + a frame
const TIMELINE = {
    frames: 900,
    hold: [["right", 60, 130], ["up", 150, 200], ["fire", 230, 231], ["right", 260, 700], ["down", 720, 760], ["left", 780, 860]],
    shots: { 1: "start", 100: "walking", 210: "at-door", 231: "door-entered", 400: "scrolled", 600: "scroller", 760: "down", 850: "walking-left" },
};
// --break return: the fail proof. The ROM scratch is wiped between the door's cart
// and the swap back, as a host or ROM that lost the note would; only `return`
// runs, and it must FAIL (exit 0 when it does, 1 when the check cannot tell).
const BREAK = process.argv.includes("--break") ? process.argv[process.argv.indexOf("--break") + 1] : null;
const POS = process.argv.slice(2).filter((a, i, all) => a !== "--break" && all[i - 1] !== "--break");
const outDir = POS[0] || "/tmp/union_demo";
const CART = POS[1] || "docs/demo-union_demo.wasm";

async function boot(loaded = true) {
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
    const env = { memory, ...rom };
    for (const k of Object.keys(machine)) if (k.startsWith("hw")) env[k] = machine[k];
    const m = { memory, machine, rom, env, demo: null, cost: { frame: [], render: [] } };
    // demo.hblDispatch must reach the CURRENT cart after a swap
    Object.defineProperty(m, "demo", { get: () => demo, set: (d) => { demo = d; } });
    await load(m, await readFile(CART), false);
    if (loaded) await ready(m);
    return m;
}

// The hub's graphics depack behind menuloader.js's TEX panel on EVERY start, a
// return from a screen included; its first street step runs on the frame the
// depack ends, which is also when it asks for its music. Returns the frame count.
async function ready(m, onFrame = () => {}) {
    for (let f = 1; f <= 400; f++) {
        step(m);
        await onFrame(f);
        if (m.demo.pollSongRequest()) return f;
    }
    throw new Error("the hub never finished loading");
}

// instantiateCart + the swap's hwInit/boot/skipBoot, with any import this cart
// needs that the harness does not provide stubbed (the loader's tolerantEnv).
async function load(m, bytes, packed) {
    if (packed) {
        const src = m.machine.hwRomRamBase() + m.machine.hwRomRamUsed();
        new Uint8Array(m.memory.buffer, src, bytes.length).set(bytes);
        const n = m.rom.romDepack(src, bytes.length, m.machine.hwRamBase(), m.machine.hwRamSize());
        bytes = new Uint8Array(m.memory.buffer.slice(m.machine.hwRamBase(), m.machine.hwRamBase() + n));
    }
    for (const imp of WebAssembly.Module.imports(new WebAssembly.Module(bytes)))
        if (imp.module === "env" && !(imp.name in m.env)) m.env[imp.name] = () => 0;
    m.demo = (await WebAssembly.instantiate(bytes, { env: m.env })).instance.exports;
    m.machine.hwSetCartHigh(cartRam(bytes).high ?? 0);
    m.rom.romReset();
    m.machine.hwInit();
    m.demo.boot();
    m.demo.skipBoot();
}

function step(m, dt = DT) {
    m.machine.hwClear();
    let t = performance.now();
    m.demo.frame(dt);
    m.cost.frame.push(performance.now() - t);
    t = performance.now();
    for (let p = 0; p < m.machine.hwPlanesNumber(); p++) if (m.demo.isPlaneEnabled(p)) m.machine.hwRenderPlane(p);
    m.cost.render.push(performance.now() - t);
}

// The visible window of the physical frame, (80, 40) with x doubled, as RGB.
function visible(m, rows = [0, 200]) {
    const w = m.machine.hwPhysWidth();
    const pfb = new Uint8Array(m.memory.buffer, m.machine.hwPhysicalPtr(), w * m.machine.hwPhysHeight() * 4);
    const out = new Uint8Array(320 * (rows[1] - rows[0]) * 3);
    for (let y = rows[0]; y < rows[1]; y++)
        for (let x = 0; x < 320; x++) {
            const s = ((40 + y) * w + 80 + 2 * x) * 4, d = ((y - rows[0]) * 320 + x) * 3;
            out[d] = pfb[s]; out[d + 1] = pfb[s + 1]; out[d + 2] = pfb[s + 2];
        }
    return out;
}
const same = (a, b) => a.length === b.length && a.every((v, i) => v === b[i]);
const tag = (m) => new TextDecoder().decode(new Uint8Array(m.memory.buffer, m.demo.getCartTagPtr(), m.demo.getCartTagLen()));

async function timeline() {
    await mkdir(outDir, { recursive: true });
    const m = await boot(false);
    // The traced timeline starts with the street. The frame the depack ends is the
    // street's first update, so it counts as one pre-roll frame.
    let midInk = 0;
    const loadFrames = await ready(m, async (f) => {
        if (f !== 50) return;
        const px = visible(m);
        for (let i = 0; i < px.length; i += 3) if (px[i] === TEX_INK[0] && px[i + 1] === TEX_INK[1] && px[i + 2] === TEX_INK[2]) midInk++;
        await writeFile(`${outDir}/loader-0050.ppm`, Buffer.concat([Buffer.from("P6\n320 200\n255\n"), px]));
    });
    if (midInk < 500) throw new Error(`mid-load the TEX loader panel shows ${midInk} ink px`);
    console.log(`menu loader: ${loadFrames} frames behind menuloader.js's TEX panel (${midInk} ink px at frame 50)`);
    for (let i = 1; i < PREROLL; i++) step(m);
    for (let f = 0; f < TIMELINE.frames; f++) {
        for (const [key, from, to] of TIMELINE.hold) {
            const last = key === "fire" ? from : to - HOLD_TAIL;
            if (f >= from && f <= last) m.demo.input(DIR[key]);
        }
        step(m);
        const name = TIMELINE.shots[f];
        if (!name) continue;
        const path = `${outDir}/${String(f).padStart(4, "0")}-${name}.ppm`;
        await writeFile(path, Buffer.concat([Buffer.from("P6\n320 200\n255\n"), visible(m)]));
        console.log(`  shot: ${path}`);
    }
    return m.cost;
}

// The door `wrap` must reach is DERIVED from the hub's own tables, not written
// here: every Union screen ported moves the first ported door (a hard-coded tag
// broke the gate each time). Charly starts at teleport '0' (charly.zig
// TELEPORTS[9], x 5436) and crosses the seam before fire is held, so the door is
// the tagged one (doors.zig ROUTES `.tag`) with the smallest x (menu_map.zig
// DOORS). Picking "the first door at or ahead of the start" instead passed
// vacuously once COPIER TEX (x 5442, under the start) got its tag: it was
// entered at frame 0 and the seam was never crossed. null when no door is tagged.
async function expectedWrapDoor() {
    const routes = await readFile("apps/zig/scenes/union_demo/doors.zig", "utf8");
    const tags = new Map([...routes.matchAll(/\.demo_name = "(\w+)"[^\n]*?\.tag = "(\w+)"/g)].map((r) => [r[1], r[2]]));
    const map = await readFile("apps/zig/assets/screens/union_demo/menu_map.zig", "utf8");
    const doors = [...map.matchAll(/\.x = ([\d.]+), \.y = [\d.]+, \.w = ([\d.]+), \.h = [\d.]+, \.demo_name = "(\w+)"/g)]
        .map((d) => ({ x: Number(d[1]), w: Number(d[2]), tag: tags.get(d[3]) }))
        .filter((d) => d.tag)
        .sort((a, b) => a.x - b.x);
    const charly = await readFile("apps/zig/scenes/union_demo/charly.zig", "utf8");
    const teleports = [...charly.slice(charly.indexOf("TELEPORTS")).matchAll(/\.\{ ([\d.]+), [\d.]+ \}/g)];
    if (teleports.length < 10) throw new Error("charly.zig TELEPORTS: fewer than 10 entries parsed");
    const startX = Number(teleports[9][1]);
    const num = (re, what) => {
        const r = charly.match(re);
        if (!r) throw new Error(`charly.zig: ${what} not parsed`);
        return r.slice(1).map(Number);
    };
    const [tiles, tileW] = num(/MAP_W: f32 = (\d+) \* (\d+)/, "MAP_W");
    const [walk] = num(/const WALK = \[2\]f32\{ ([\d.]+),/, "WALK");
    const [fast] = num(/const FAST = \[2\]f32\{ ([\d.]+),/, "FAST");
    if (!doors.length) return null;
    return { ...doors[0], startX, mapW: tiles * tileW, walk, fast };
}

const SEAM_MARGIN = 5; // steps beyond the slowest crossing (WALK x) before fire is held

// wrap: from the last door (x 5436), right + F1 with NO fire until Charly must be
// past the seam, then fire too, until a door asks for a cart. `fireEarly` (the
// --break wrap fail proof) holds fire from the start, as the vacuous check did.
async function checkWrap(fireEarly = false) {
    const want = await expectedWrapDoor();
    if (want === null) return "FAIL wrap: no door in doors.zig ROUTES has a .tag, so there is no ported door to walk into";
    // Fire is held after `seamSteps` at the slowest speed; at F1's speed Charly is
    // at most this far past the seam then, so the door must lie beyond it to be
    // walked into rather than already passed.
    const seamSteps = Math.ceil((want.mapW - want.startX) / want.walk) + SEAM_MARGIN;
    const reach = seamSteps * want.fast - (want.mapW - want.startX);
    if (want.x <= reach) return `FAIL wrap: the lowest ported door (${want.tag}, x ${want.x}) is within ${reach} px of the seam: move the start or the check can't walk into it`;
    const m = await boot();
    step(m);
    m.demo.key("0".charCodeAt(0)); step(m); // teleport to x 5436
    m.demo.key(K_F1); step(m);
    let prev = visible(m, STREET), still = 0, f = 0;
    for (; f < 600; f++) {
        m.demo.input(DIR.right);
        if (fireEarly || f >= seamSteps) m.demo.input(DIR.fire);
        step(m);
        const street = visible(m, STREET);
        still = same(street, prev) ? still + 1 : 0;
        prev = street;
        if (still > 30) return `FAIL wrap: walking right, the street has not scrolled for 30 frames (frame ${f}): the view is held at the map's end`;
        if (m.demo.pollCartRequest() === 1) break;
    }
    if (f >= 600) return `FAIL wrap: no door asked for a cart within 600 frames (expected ${want.tag})`;
    const t = tag(m);
    if (f < seamSteps) return `FAIL wrap: ${t} was entered at frame ${f}, before Charly could cross the seam (${seamSteps} steps from x ${want.startX})`;
    if (t !== want.tag) return `FAIL wrap: expected ${want.tag}, the lowest ported door beyond the seam, got ${t}`;
    // The hub's own record of where Charly stood when the door launched.
    const ptr = m.rom.romScratchPtr ? m.rom.romScratchPtr() : 0;
    if (!ptr || new TextDecoder().decode(new Uint8Array(m.memory.buffer, ptr, 4)) !== "UNI1")
        return `FAIL wrap: ${t} launched but the hub left no note, so the wrap can't be confirmed`;
    const x = new DataView(m.memory.buffer, ptr, 20).getFloat32(8, true);
    // Charly's collision box reaches ~77 px right of his x (deltaforce: x 1235.5 at a
    // door from 1312), so allow 128 px; the wrap itself is proven by x < startX.
    if (!(x < want.startX && x > want.x - 128 && x < want.x + want.w))
        return `FAIL wrap: ${t} was entered with Charly at x ${x}, not past the seam inside its door (x ${want.x}..${want.x + want.w}, start ${want.startX})`;
    return `ok   wrap: no fire until past the seam (${seamSteps} steps from x ${want.startX}), then the lowest ported door (${t}) at Charly x ${x} after ${f} frames`;
}

// A key the browser way: a press at 0, repeats from 500 ms every 33.3 ms while
// held, released at `upMs` (and reported with inputRelease when `keyup`), on a
// `hz` display. Returns how many ms after the release the street last moved.
async function stopAfter(upMs, keyup, hz) {
    const m = await boot();
    for (let i = 0; i < PREROLL; i++) step(m);
    const events = [0];
    for (let k = 0; 500 + (k * 1000) / 30 < upMs; k++) events.push(500 + (k * 1000) / 30);
    const frameMs = 1000 / hz, total = Math.ceil((upMs + 1000) / frameMs);
    let next = 0, released = false, prev = visible(m, STREET), last = -1;
    for (let f = 0; f < total; f++) {
        const now = f * frameMs;
        while (next < events.length && events[next] <= now) { m.demo.input(DIR.right); next++; }
        if (keyup && !released && upMs <= now) { m.demo.inputRelease(DIR.right); released = true; }
        step(m, frameMs);
        const street = visible(m, STREET);
        if (!same(street, prev)) last = now;
        prev = street;
    }
    return Math.round(last - upMs);
}

// Charly's screen x: the mean column of his brown pixels (the street is grey).
function charlyX(m) {
    const px = visible(m, [95, 140]);
    let sum = 0, n = 0;
    for (let i = 0; i < px.length; i += 3)
        if (px[i] > 120 && px[i + 1] < px[i] - 40 && px[i + 2] < px[i + 1]) { sum += (i / 3) % 320; n++; }
    return n ? sum / n : null;
}

// ease: left from the spawn, across the seam, then on: no step moves him far on
// screen, and he ends in the middle of it (the view follows him again).
async function checkEase() {
    const m = await boot();
    for (let i = 0; i < PREROLL; i++) step(m);
    let prev = charlyX(m), worst = 0, at = 0;
    for (let f = 0; f < 150; f++) {
        m.demo.input(DIR.left);
        step(m);
        const x = charlyX(m);
        if (x === null || prev === null) return `FAIL ease: Charly not found on screen at frame ${f}`;
        if (Math.abs(x - prev) > worst) { worst = Math.abs(x - prev); at = f; }
        prev = x;
    }
    if (worst > EASE_PX) return `FAIL ease: at frame ${at} Charly jumped ${worst.toFixed(1)} px on screen (limit ${EASE_PX})`;
    return prev > 130 && prev < 210 ? `ok   ease: across the seam from the clamped start, at most ${worst.toFixed(1)} px a step, ends centred (x ${prev.toFixed(0)})`
        : `FAIL ease: after walking left 150 steps Charly is at screen x ${prev.toFixed(0)}, not centred: the view never let go of the clamp`;
}

async function checkStop(hz) {
    let worst = -Infinity, at = 0;
    for (let up = 550; up <= 1500; up += 25) {
        const after = await stopAfter(up, false, hz);
        if (after > worst) { worst = after; at = up; }
    }
    return worst <= STOP_MS ? `ok   stop ${hz} Hz: releases 550..1500 ms, the street stops at worst ${worst} ms later`
        : `FAIL stop ${hz} Hz: released at ${at} ms, the street kept moving ${worst} ms (limit ${STOP_MS})`;
}

async function checkKeyup() {
    const probe = await boot();
    if (!probe.demo.inputRelease) return "FAIL keyup: the cart has no inputRelease export";
    const after = await stopAfter(100, true, 60);
    return after <= STOP_MS ? `ok   keyup: a 100 ms tap released by key-up stops ${after} ms later`
        : `FAIL keyup: a 100 ms tap released by key-up kept moving ${after} ms (limit ${STOP_MS})`;
}

// Boot the cart of the disk a door asked for, as swapCart does.
async function loadDisk(m, t) {
    const disk = new Uint8Array(await readFile(`docs/demo-${t}.zmd`));
    const dv = new DataView(disk.buffer, disk.byteOffset);
    const start = dv.getUint32(0x0e, true) * dv.getUint16(0x08, true);
    await load(m, disk.slice(start, start + dv.getUint32(0x12, true)), true);
}

// return: see the header. STREET_ROWS is wall, pavement and Charly, below the
// 60-row door rasters and the banner (both restart on a new hub); the HUD
// (scroller) is checked apart.
const STREET_ROWS = [64, 155];
const HUD_ROWS = [165, 200];
async function checkReturn() {
    const fails = [];
    const m = await boot();
    const spawn = visible(m, STREET_ROWS); // the street's first step
    for (let i = 0; i < 200; i++) step(m); // the scroller moves past its first characters
    m.demo.key("9".charCodeAt(0)); step(m); // teleport in front of door 9
    m.demo.input(DIR.fire); step(m);
    const left = visible(m, STREET_ROWS);
    if (m.demo.pollCartRequest() !== 1 || tag(m) !== "union_multifake")
        return "FAIL return: fire at door 9 did not ask for union_multifake";
    const ptr = m.rom.romScratchPtr ? m.rom.romScratchPtr() : 0;
    const note = ptr ? new DataView(m.memory.buffer, ptr, 20) : null;
    const noted = note && new TextDecoder().decode(new Uint8Array(m.memory.buffer, ptr, 4)) === "UNI1";
    if (!noted) fails.push("the hub left no note in the ROM scratch");
    else if (note.getFloat32(8, true) !== 4236 || note.getFloat32(12, true) !== 127 || note.getUint32(16, true) <= 12)
        fails.push(`the note says x ${note.getFloat32(8, true)} y ${note.getFloat32(12, true)} scroll ${note.getUint32(16, true)}, not door 9 and a moved scroller`);
    await loadDisk(m, "union_multifake");
    for (let i = 0; i < 30; i++) step(m); // the door's cart runs over the cart window
    if (BREAK === "return" && ptr) new Uint8Array(m.memory.buffer, ptr, m.rom.romScratchLen()).fill(0);
    const hub = await readFile(CART);
    await load(m, hub, false); // swapCart back to the hub: romReset, hwInit, boot, skipBoot
    await ready(m); // its menuloader depack first; the note is read when it ends
    if (!same(visible(m, STREET_ROWS), left))
        fails.push(same(visible(m, STREET_ROWS), spawn) ? "the hub came back at the spawn (START_X), not at door 9" : "the hub came back somewhere else than door 9");
    if (ptr && new Uint8Array(m.memory.buffer, ptr, 4).some((b) => b !== 0)) fails.push("the note was not spent");
    for (let i = 0; i < 160; i++) step(m); // letters reach the screen
    const scroller = visible(m, HUD_ROWS);
    // A new page: new memory, new ROM. Both hubs have run ready() (its last frame
    // is the street's first step) and then the same 160 steps, so their letters
    // stand at the same x and only the characters can differ.
    const fresh = await boot();
    for (let i = 0; i < 160; i++) step(fresh);
    if (same(scroller, visible(fresh, HUD_ROWS))) fails.push("the scroller restarted from its first character");
    const page = await boot();
    if (!same(visible(page, STREET_ROWS), spawn)) fails.push("a fresh page did not start at the spawn");
    await load(m, hub, false); // the hub again, with no door in between
    await ready(m);
    if (!same(visible(m, STREET_ROWS), spawn)) fails.push("a second return without a door did not start at the spawn: the note was reused");
    return fails.length ? `FAIL return: ${fails.join("; ")}` : "ok   return: door 9 -> union_multifake -> a fresh hub: Charly and the scroller where they were, note spent, a new page at the spawn";
}

// esc: the hub SWALLOWS Escape and Back. Both used to ask for cart -1 (the menu
// disk), so one mistyped key — Escape sits right by the 1-9/0/H door teleports —
// threw the whole walk away. The hub is left through a door, not through Escape.
// The -1 path itself must survive: a hub whose disk fails to load still bails.
async function checkEsc() {
    const fails = [];
    const m = await boot();
    for (const [what, press] of [["Escape", () => m.demo.key(K_ESC)], ["Back", () => m.demo.input(DIR.back)]]) {
        press();
        step(m);
        const req = m.demo.pollCartRequest();
        if (req !== 0) fails.push(`${what} asked for cart ${req}${req === -1 ? " (the menu disk)" : ""}, wanted 0`);
    }
    // Swallowing Escape must not have cost the hub its other keys: H still
    // teleports to the hidden door, and fire there still leaves through it.
    m.demo.key("h".charCodeAt(0));
    step(m);
    m.demo.input(DIR.fire);
    step(m);
    if (m.demo.pollCartRequest() !== 1) fails.push("after Escape, fire at the hidden door no longer leaves the hub");
    return fails.length ? `FAIL esc: ${fails.join("; ")}`
        : "ok   esc: Escape and Back ask for nothing; the doors still open";
}

// The hub's door request followed through the shelf's disks, page order.
async function checkDoor() {
    const m = await boot();
    m.demo.key("h".charCodeAt(0)); step(m); // in front of the hidden door
    m.demo.input(DIR.fire); step(m);
    if (m.demo.pollCartRequest() !== 1) return "FAIL door: fire in front of the hidden door asked for nothing";
    await loadDisk(m, tag(m));
    let ink = 0;
    for (let f = 0; f < 60; f++) {
        step(m);
        const px = visible(m);
        for (let i = 0; i < px.length; i += 3) if (px[i] === 0xc0 && px[i + 1] === 0xa0 && px[i + 2] === 0) { ink++; break; }
    }
    return ink >= 50 ? `ok   door: the TEX loader panel shows on ${ink} of the first 60 frames after the swap`
        : `FAIL door: the TEX loader panel shows on only ${ink} of the first 60 frames after the swap`;
}

if (BREAK === "wrap") {
    const r = await checkWrap(true);
    console.log(r);
    const caught = r.startsWith("FAIL wrap") && r.includes("before Charly could cross the seam");
    console.log(caught ? "=> PASS ✅ fail proof: fire from the start enters the door under the start, and `wrap` refuses it"
        : "=> FAIL ❌ fail proof: `wrap` accepted a door entered before the seam");
    process.exit(caught ? 0 : 1);
}
if (BREAK !== null) {
    if (BREAK !== "return") { console.log(`=> FAIL ❌ --break ${BREAK}: only "return" and "wrap" can be broken`); process.exit(1); }
    const r = await checkReturn();
    console.log(r);
    const caught = r.startsWith("FAIL return") && r.includes("spawn");
    console.log(caught ? "=> PASS ✅ fail proof: a lost ROM note brings the hub back at the spawn, and `return` says so"
        : "=> FAIL ❌ fail proof: `return` did not notice the lost note");
    process.exit(caught ? 0 : 1);
}

const cost = await timeline();
const results = [await checkWrap(), await checkEase(), await checkStop(60), await checkStop(144), await checkKeyup(), await checkEsc(), await checkReturn(), await checkDoor()];
for (const r of results) console.log(r);

const stats = (a) => {
    const s = [...a].sort((x, y) => x - y);
    return `mean ${(a.reduce((x, y) => x + y, 0) / a.length).toFixed(3)} ms, p99 ${s[Math.floor(s.length * 0.99)].toFixed(3)} ms, max ${s[s.length - 1].toFixed(3)} ms`;
};
console.log(`frames: ${cost.frame.length}`);
console.log(`  cart update+render: ${stats(cost.frame)}`);
console.log(`  hwRenderPlane     : ${stats(cost.render)}`);
const worst = Math.max(...cost.frame.map((v, i) => v + cost.render[i]));
console.log(worst < 16.7 ? `=> PASS within the 60 fps budget (worst ${worst.toFixed(3)} ms of 16.7)` : `=> OVER budget: worst ${worst.toFixed(3)} ms`);
const failed = results.filter((r) => r.startsWith("FAIL")).length;
console.log(failed ? `=> ${failed} check(s) FAILED` : "=> all checks pass");
process.exit(failed || worst >= 16.7 ? 1 : 0);
