// Every frame of STNICCC 2000 (apps/zig/scenes/stniccc.zig) pinned to the cart as it
// was before the KESTREL speed-up (c77c6c2e; the speed-up: CPU word-store spans instead
// of ~2,000 CHISEL fills a frame, a two-chain filler, word-compared keyframes, no
// whole-plane clear in the zoom): the small act, the slow-down, the rewind (keyframe
// seeks), the blinking message, the zoom and the whole fullscreen flight, disk
// streaming included, 3,300 host frames at 60 Hz. Each frame's physical RGB picture
// (plane 0 through its palette, the opened borders included) is hashed.
//
//   node apps/stniccc_pins.mjs                    compare with apps/stniccc_pins.json
//   node apps/stniccc_pins.mjs --record [cart]    (re)write the pins (only from a cart known good)
//   node apps/stniccc_pins.mjs --break            one frame's pixel altered: must be caught
import { readFile, writeFile } from "node:fs/promises";
import { createHash } from "node:crypto";
import { boot } from "./stniccc_machine.mjs";

const PINS = "apps/stniccc_pins.json";
const FRAMES = 3300; // past the end of the fullscreen flight's first pass (it starts ~1170)
const BREAK_AT = 2000;
const record = process.argv.includes("--record");
const brk = process.argv.includes("--break");
const cart = (record && process.argv[process.argv.indexOf("--record") + 1]) || "docs/demo-stniccc.wasm";

const disk = new Uint8Array(await readFile("docs/demo-stniccc.zmd"));
const { memory, machine, demo } = await boot(cart, disk);
const pw = machine.hwPhysWidth(), ph = machine.hwPhysHeight();
const sha = (b) => createHash("sha256").update(b).digest("hex").slice(0, 12);

const got = [];
for (let f = 1; f <= FRAMES; f++) {
    machine.hwClear();
    demo.frame(1000 / 60);
    machine.hwRenderPlane(0);
    const phys = new Uint8Array(memory.buffer, machine.hwPhysicalPtr(), pw * ph * 4);
    if (brk && f === BREAK_AT) phys[(pw * 140 + 200) * 4] ^= 1;
    got.push(sha(phys));
}
if (machine.hwRamAllocFailures()) {
    console.log(`stniccc pins: FAIL -- ${machine.hwRamAllocFailures()} zg.mem allocation(s) refused`);
    process.exit(1);
}

if (record) {
    await writeFile(PINS, JSON.stringify(got) + "\n");
    console.log(`stniccc pins: recorded ${got.length} frames from ${cart}`);
    process.exit(0);
}
const want = JSON.parse(await readFile(PINS, "utf8"));
const bad = got.findIndex((h, i) => h !== want[i]);
const distinct = new Set(got).size;
if (want.length !== got.length || bad >= 0) {
    const why = `frame ${bad + 1} differs from the pinned cart (${want.length} pinned, ${got.length} run)`;
    if (brk) { console.log(`stniccc pins --break: caught: ${why}`); process.exit(0); }
    console.log(`stniccc pins: FAIL -- ${why}`);
    process.exit(1);
}
if (brk) { console.log("stniccc pins --break: FAIL -- an altered frame was NOT caught"); process.exit(1); }
console.log(`stniccc pins: all ${got.length} frames identical to the pinned cart (${distinct} distinct pictures)`);
