// BAD APPLE!! (carts 166 spans, 167 tiles) end to end on the sealed machine + ROM, against a Python REFERENCE
// decoder (tools/badapple/{zx0,spans,tiles}.py: its own ZX0 depacker and format readers, none of the cart's code).
//   1. the cart's plane = the reference's frame, pixel for pixel, at fixed frames (first, block starts and ends,
//      the hard cut, the all-white / all-black frames, the last), the film frame following the clock (hostMicros);
//   2. a long stall (1.5 s in one host frame): the plane = the reference frame the clock owes (deltas skipped
//      across a block change and the cut are still applied), and the last frame holds when the film is over;
//   3. no clock (hostMicros 0): the film follows the 60 Hz VBLs at 30 fps;
//   4. a block whose ZX0 magic is broken: the frames before it play, the picture goes red when it is reached
//      (fail loud), no exception, no refused zg.mem allocation; the shipped cart asks for no song (silent);
//   5. Escape asks to leave.
//   node apps/harness/badapple_headless.mjs [--variant spans|tiles] [--break] [--spans <stream>]
//   (--spans: a LOCAL real film of that variant, with its own .zmd in BADAPPLE_ZMD, built by
//   prototypes/cards/build_badapple.sh; the pins then follow its frame count)
// --break shifts the plane one pixel before every comparison: that must be caught.
import { readFile } from "node:fs/promises";
import { spawnSync } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { boot } from "./stniccc_machine.mjs";

const argv = process.argv.slice(2);
const BRK = argv.includes("--break");
const VARIANT = argv.includes("--variant") ? argv[argv.indexOf("--variant") + 1] : "spans";
if (!["spans", "tiles"].includes(VARIANT)) { console.error(`badapple: unknown variant ${VARIANT}`); process.exit(2); }
const TAG = VARIANT === "spans" ? "badapple" : `badapple_${VARIANT}`;
const SPANS = argv.includes("--spans") ? argv[argv.indexOf("--spans") + 1] : `apps/zig/assets/screens/badapple/test_${VARIANT}.bin`;
const WASM = `site/carts/demo-${TAG}.wasm`, ZMD = process.env.BADAPPLE_ZMD || `site/carts/demo-${TAG}.zmd`;
const W = 320, H = 200, FPS = 30, HOST_US = 16667;
const errors = [];
const fail = (m) => errors.push(m);

// ---- the stream's header and the reference frames
const stream = new Uint8Array(await readFile(SPANS));
const total = new DataView(stream.buffer, stream.byteOffset).getUint16(10, true);
const pins = [...new Set([0, 1, 14, 29, 30, 31, 44, 45, 46, 59, 60, 61, 74, 75, 76, 88, 89, total - 1])].filter((f) => f >= 0 && f < total).sort((a, b) => a - b);
const tmp = mkdtempSync(`${tmpdir()}/badapple-`);
const ref = spawnSync("python3", ["-I", "tools/badapple/ref_decode.py", SPANS, `${tmp}/ref.raw`, pins.join(",")], { encoding: "utf8" });
if (ref.status !== 0) { console.error(`badapple: the reference decoder failed: ${ref.stderr}`); process.exit(1); }
const refRaw = readFileSync(`${tmp}/ref.raw`);
rmSync(tmp, { recursive: true });
const refFrame = (f) => refRaw.subarray(pins.indexOf(f) * W * H, (pins.indexOf(f) + 1) * W * H);

// ---- the cart's visible 320x200 plane (0 black, 1 white, 2 anything else: the error red)
function plane(memory, machine) {
    machine.hwClear();
    machine.hwRenderPlane(0);
    const pw = machine.hwPhysWidth(), ph = machine.hwPhysHeight();
    const px = new Uint32Array(memory.buffer, machine.hwPhysicalPtr(), pw * ph);
    const xs = pw / 400, ys = ph / 280; // the 320x200 picture sits 40 px in from the 400x280 screen's edges
    const out = new Uint8Array(W * H);
    for (let y = 0; y < H; y++) {
        for (let x = 0; x < W; x++) {
            const rgb = px[Math.round((40 + y) * ys) * pw + Math.round((40 + x) * xs)] & 0xFFFFFF;
            out[y * W + x] = rgb === 0 ? 0 : rgb === 0xFFFFFF ? 1 : 2;
        }
    }
    if (BRK) out.copyWithin(1, 0, out.length - 1); // one pixel to the right
    return out;
}
function same(a, b) { for (let i = 0; i < a.length; i++) if (a[i] !== b[i]) return false; return true; }

async function start(clock, disk = null) {
    const bytes = disk ?? new Uint8Array(await readFile(ZMD));
    const m = await boot(WASM, bytes, { hostMicros: () => clock.us });
    m.clock = clock;
    return m;
}
const step = (m, us) => { if (m.clock.us) m.clock.us += us; m.demo.frame(1000 / 60); };
const dueIndex = (elapsed) => Math.min(total, Math.floor(elapsed * FPS / 1e6) + 1) - 1; // the cart's frame, 0-based

function expectPlane(m, tag, f) {
    if (!pins.includes(f)) return;
    if (!same(plane(m.memory, m.machine), refFrame(f))) fail(`${tag}: plane != reference frame ${f}`);
}

// 1. clock-driven, every host frame: the plane equals the reference wherever the frame is pinned
{
    const m = await start({ us: 5_000_000 });
    for (let h = 1; h <= total * 2 + 20; h++) {
        step(m, HOST_US);
        expectPlane(m, `clock h=${h}`, dueIndex(h * HOST_US));
    }
    if (m.machine.hwRamAllocFailures() !== 0) fail("a zg.mem allocation was refused");
    if (m.demo.pollSfx() !== 0 || m.demo.pollSongRequest() !== 0) fail("the shipped cart asked for a song (it must be silent)");
    m.demo.key(0xE012);
    if (m.demo.pollCartRequest() !== -1) fail("Escape did not ask to leave");
}
// 2. a stall: 1.5 s (45 film frames, across a block change and the cut) in one host frame, then on to the end and past it
{
    const m = await start({ us: 5_000_000 });
    let elapsed = 0;
    for (const gap of [HOST_US * 10, 1_500_000, HOST_US, 3_000_000, Math.ceil(total / FPS) * 1_000_000 + 5_000_000]) {
        step(m, gap);
        elapsed += gap;
        expectPlane(m, `stall at ${elapsed} us`, dueIndex(elapsed));
    }
    if (!same(plane(m.memory, m.machine), refFrame(total - 1))) fail("past the end the last frame does not hold");
}
// 3. no clock: 30 fps from the 60 Hz VBLs
{
    const m = await start({ us: 0 });
    for (let h = 1; h <= total * 2 + 4; h++) {
        step(m, 0);
        expectPlane(m, `no clock h=${h}`, Math.min(total, (h + 1) >> 1) - 1);
    }
}
// 4. a broken second block: the first one plays, then the picture is red
{
    const disk = new Uint8Array(await readFile(ZMD));
    const view = new DataView(stream.buffer, stream.byteOffset);
    const block1 = 16 + 10 + view.getUint32(16, true); // header, block 0's header and packed bytes
    const at = Buffer.from(disk.buffer).indexOf(stream.subarray(0, 32)) + block1 + 10;
    if (String.fromCharCode(...disk.subarray(at, at + 4)) !== "ZX0!") fail("harness: block 1's ZX0 magic not found on the disk");
    disk[at] ^= 0xFF;
    const m = await start({ us: 5_000_000 }, disk);
    for (let h = 1; h <= 59; h++) step(m, HOST_US); // film frame 29, the last of block 0
    if (!same(plane(m.memory, m.machine), refFrame(29))) fail("before the broken block: plane != reference frame 29");
    for (let h = 0; h < 3; h++) step(m, HOST_US); // frame 30 is due: the broken block is reached
    if (!plane(m.memory, m.machine).every((v) => v === 2)) fail("a broken block did not turn the picture red");
}

if (BRK) {
    console.log(errors.length ? `${TAG}: PASS (--break caught: ${errors[0]})` : `${TAG}: FAIL (--break was NOT caught)`);
    process.exit(errors.length ? 0 : 1);
}
if (errors.length) { for (const e of errors.slice(0, 12)) console.error(`  ${e}`); console.log(`${TAG}: FAIL (${errors.length} errors)`); process.exit(1); }
console.log(`${TAG}: PASS (${total} frames, ${pins.length} pinned, clock / stall / no clock / broken block)`);
