// Headless RACER camera zones (R82 Kestrel Racing M5 finish, apps/zig/scenes/racer/zone.zig, docs/ports/kestrel_racing/M5.md):
// Neon Docks' warehouse is a roofed run of its racing line (the Track Kit's CAM_NEAR). Under it the race's FAR chase camera
// blends to the near one, so two machines racing the same race (the recorded pilot, warp), one in the far POV (the default)
// and one switched to the near POV on the grid, show:
//   - different views on the way to the warehouse (far is not near), and
//   - the SAME view for a run of frames under its roof (the far camera there IS the near one);
// and the lap's physics is the same on both (racer,cars CRCs: a camera never moves a car).
// --break zone (key K: no zone anywhere) must be caught: the far camera stays far under the roof, no frame matches.
//   node apps/harness/racer_zone.mjs [--break zone]
import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";
import { diskHook, ZMD } from "./racer_disk.mjs";
import { bootObj, key } from "./obj_machine.mjs";

const argv = process.argv.slice(2);
const BREAK = argv.includes("--break") ? argv[argv.indexOf("--break") + 1] : null;
if (BREAK !== null && BREAK !== "zone") { console.error(`racer_zone: unknown --break ${BREAK}`); process.exit(1); }
const W = 320, H = 200, Y0 = 12, Y1 = 188, REG_FB_BASE = 0x44, OFF_PAL = 0x0100, FRAMES = 400, NEON_TAPS = 3, MIN_SAME = 4;
const errors = [];
const fail = (m) => errors.push(m);

async function racer(near) {
    const img = new Uint8Array(await readFile(ZMD));
    const log = [];
    const S = await bootObj("site/carts/demo-racer.wasm", (s) => log.push(s), diskHook(img));
    const run = (n) => { for (let i = 0; i < n; i++) S.frame(); };
    const shown = () => [0, 1].filter((p) => S.demo.isPlaneEnabled(p))[0] ?? 0;
    const view = () => {
        const vb = S.machine.hwVideoBase(), dv = new DataView(S.memory.buffer, vb, OFF_PAL);
        const at = vb + dv.getUint32(REG_FB_BASE + 4 * shown(), true);
        return createHash("sha256").update(new Uint8Array(S.memory.buffer, at + Y0 * W, (Y1 - Y0) * W)).digest("hex").slice(0, 16);
    };
    if (BREAK) key(S, "K");
    for (let i = 0; i < NEON_TAPS; i++) { key(S, "t"); run(3); }
    key(S, "e"); run(2); // the race on NEON (the AI's pilot flies the player there)
    key(S, "a"); key(S, "w"); run(2);
    if (near) key(S, "v"); // the near chase camera
    run(70); // the POV move (60 frames) done on the grid on both
    key(S, "s"); // the countdown
    return { S, log, run, view };
}

const far = await racer(false), near = await racer(true);
if (!far.log.some((l) => l.startsWith("racer,load,NEON"))) fail("NEON was not loaded (the shelf disk's 4th track)");
const same = [];
let before = 0;
for (let f = 0; f < FRAMES; f++) {
    far.run(1); near.run(1);
    const eq = far.view() === near.view();
    if (eq) same.push(f);
    else if (same.length === 0) before += 1;
}
const crcs = (r) => r.log.filter((l) => l.startsWith("racer,cars,")).join(" ");
if (crcs(far) !== crcs(near) || !crcs(far)) fail("the far and the near race's racer,cars CRCs differ (a camera moved a car)");
if (before < 20) fail(`only ${before} frames differ before the first identical one: far = near outside the warehouse?`);
let run = 0, best = 0;
for (let k = 0; k < same.length; k++) { run = k && same[k] === same[k - 1] + 1 ? run + 1 : 1; best = Math.max(best, run); }
if (best < MIN_SAME) fail(`under the warehouse roof the far camera is not the near one: the longest run of identical frames is ${best} (want >= ${MIN_SAME})`);

if (BREAK) {
    if (!errors.some((e) => e.includes("roof"))) { console.error(`racer_zone: --break zone was NOT caught (${errors.join("; ") || "no errors"})`); process.exit(1); }
    console.log(`racer_zone PASS (--break zone caught: ${errors.find((e) => e.includes("roof"))})`);
} else if (errors.length) {
    console.error(errors.map((e) => `racer_zone: ${e}`).join("\n"));
    process.exit(1);
} else console.log(`racer_zone PASS (NEON race: far != near for ${before} frames, then far = near for ${best} frames in a row under the warehouse; the cars' CRCs the same)`);
