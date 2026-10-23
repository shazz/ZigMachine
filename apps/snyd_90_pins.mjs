// Every frame of SWEDISH NEW YEAR 89-90 (apps/zig/scenes/snyd_90.zig) pinned to the
// cart as it was before the KESTREL speed-up (perf/snyd90-screens): the intro, the
// menu and each F-key part, at the board's 60 Hz host rate (so frames that run no
// VBL and frames that run two are both covered), every frame's plane indices and
// physical RGB frame (the per-line colours from the plane's HBL, the borders from
// the global HBL) hashed. apps/snyd_90_headless.mjs checks the shots against the
// REAL demo; this checks that a faster shifter shows exactly what the old one did
// on every frame between those shots, including F3..F6, which it only checks by look.
//
//   node apps/snyd_90_pins.mjs            compare with apps/snyd_90_pins.json
//   node apps/snyd_90_pins.mjs --record   (re)write the pins (only from a cart known good)
//   node apps/snyd_90_pins.mjs --break    one frame's plane altered: must be caught
import { readFile, writeFile } from "node:fs/promises";
import { createHash } from "node:crypto";
import { boot, PW, PH } from "./snyd_90_machine.mjs";

const PINS = "apps/snyd_90_pins.json";
const DT = 1000 / 60;
const K = { space: 32, f: (n) => 0xe000 + n };
const FRAMES = 420; // a part's frames: past F1's first letter ($140 VBLs), F4/F6's set-up
// F3's panel takes keys: a few presses and arrows while it runs (frame -> key)
const F3_KEYS = { 100: 0xe002, 140: 0xf001, 160: 0xf003, 200: 65, 260: 0xe001 };
const record = process.argv.includes("--record");
const brk = process.argv.includes("--break");

const m = await boot();
const sha = (b) => createHash("sha256").update(b).digest("hex").slice(0, 10);
const pw = m.machine.hwPhysWidth(), ph = m.machine.hwPhysHeight();
let n = 0;

function step() {
    m.machine.hwClear();
    m.demo.frame(DT);
    m.machine.hwRenderPlane(0);
    if (brk && n === 1000) m.plane()[PW * 100 + 200] ^= 1; // a pixel the next frame may not rewrite
    n++;
    const phys = new Uint8Array(m.memory.buffer, m.machine.hwPhysicalPtr(), pw * ph * 4);
    return sha(m.plane()) + sha(phys);
}

const got = {};
const run = (name, frames, keys = {}) => {
    got[name] = [];
    for (let j = 0; j < frames; j++) {
        if (keys[j] !== undefined) m.demo.key(keys[j]);
        got[name].push(step());
    }
};
run("intro", 60);
m.demo.key(K.space);
run("menu", 900);
for (let p = 1; p <= 6; p++) {
    m.demo.key(K.f(p));
    run(`f${p}`, FRAMES, p === 3 ? F3_KEYS : {});
    m.demo.key(K.space);
    run(`menu-after-f${p}`, 30);
}

if (record) {
    await writeFile(PINS, JSON.stringify(got) + "\n");
    console.log(`snyd_90_pins: recorded ${n} frames (${Object.keys(got).join(", ")})`);
    process.exit(0);
}
const want = JSON.parse(await readFile(PINS, "utf8"));
let bad = 0;
for (const [name, list] of Object.entries(want)) {
    const have = got[name] ?? [];
    const j = list.findIndex((h, i) => h !== have[i]);
    if (j < 0 && have.length === list.length) { console.log(`  ${name}: ${list.length} frames identical`); continue; }
    bad++;
    console.log(`  FAIL ${name}: frame ${j} differs (plane+physical ${have[j]}, pinned ${list[j]})`);
}
if (brk) {
    console.log(bad ? `snyd_90_pins: PASS (--break caught in ${bad} part(s))` : "snyd_90_pins: FAILED -- --break was not caught");
    process.exit(bad ? 0 : 1);
}
console.log(bad ? `snyd_90_pins: FAILED (${bad} parts differ)` : `snyd_90_pins: all ${n} frames identical`);
process.exit(bad ? 1 : 0);
