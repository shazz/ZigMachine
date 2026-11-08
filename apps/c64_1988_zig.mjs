// 1988's ZIG mode (Z, apps/zig/scenes/c64_1988/zig_mode.zig), checked from outside. Two carts
// run in lockstep, one machine frame (60 Hz) a step: REF never sees Z, ZIG gets Z three times.
//   planes   ZIG shows plane 0 alone, as REF does
//   exact    on every ZIG frame that falls on a C64 frame (k = 0) the composed picture is REF's,
//            pixel for pixel, but for the lines where part 2 switches the border colour mid-line
//            (REF's BEAM write; ZIG keeps the line's starting colour): the same C64 frame
//   60 Hz    in part 1 (the logo moves every C64 frame) ZIG shows a new picture on every
//            machine frame, REF repeats one in six (the 50 Hz picture on a 60 Hz machine)
//   ops      CHISEL ops a ZIG frame <= OPS_MAX
//   back     Z again: once ZIG hands back (at the next C64 frame boundary) the next 90 frames
//            are REF's, pixel for pixel; three round trips: logo, grid, the logo's fade
//   node apps/c64_1988_zig.mjs [--break]
//     --break: REF runs one frame ahead during the round trips, so "back" must fail (exit 0)
import { boot } from "./c64_1988_boot.mjs";

const BROKE = process.argv.includes("--break");
const K_Z = 122, RW = 800, W = 400, H = 280, OPS_MAX = 160;
// [Z on, Z off] machine frames: part 1 (text 1), part 3 (cubes), part 1's fade into the wipe
const TRIPS = [[150, 700], [2150, 2450], [1900, 1990]];
let failed = 0, backFails = 0;
const ok = (c, m) => { if (!c) { console.log(`  FAIL ${m}`); failed++; if (m.startsWith("back")) backFails++; } return c; };

class Cart {
    constructor(b) { Object.assign(this, b); }
    step() { this.machine.hwClear(); this.demo.frame(1000 / 60); this.frame++; }
    /** The composed picture, 400 x 280 0xRRGGBB (un-doubled). */
    picture() {
        this.machine.hwClear();
        for (let p = 0; p < 4; p++) if (this.demo.isPlaneEnabled(p)) this.machine.hwRenderPlane(p);
        const px = new Uint32Array(this.memory.buffer, this.machine.hwPhysicalPtr(), RW * H), o = new Uint32Array(W * H);
        for (let i = 0; i < o.length; i++) o[i] = px[Math.floor(i / W) * RW + 2 * (i % W)] & 0xFFFFFF;
        return o;
    }
}

const ref = new Cart(await boot()), zig = new Cart(await boot());
const rows = (a, b) => { const d = []; for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) if (a[y * W + x] !== b[y * W + x]) { d.push(y); break; } return d; };
const same = (a, b) => a.every((v, i) => v === b[i]);
const WIPE = [Math.floor(1645 * 6 / 5), Math.ceil(1716 * 6 / 5)]; // part 2: the mid-line switches

let exact = 0, newPics = 0, part1 = 0, refRepeats = 0, lastZ = null, lastR = null;
for (const [on, off] of [...TRIPS].sort((a, b) => a[0] - b[0])) {
    while (zig.frame < on) { ref.step(); zig.step(); }
    zig.demo.key(K_Z);
    while (zig.frame < off) {
        ref.step(); zig.step();
        if (!zig.demo.c64Zig()) { ok(false, `zig: not on at ${zig.frame}`); break; }
        ok(zig.demo.isPlaneEnabled(0) && [1, 2, 3].every((p) => !zig.demo.isPlaneEnabled(p)), `planes at ${zig.frame}`);
        ok(zig.demo.c64ZigOps() <= OPS_MAX, `ops: ${zig.demo.c64ZigOps()} CHISEL ops at ${zig.frame}`);
        const z = zig.picture(), r = ref.picture();
        if (zig.demo.c64ZigK() === 0) {
            const d = rows(z, r), inWipe = zig.frame >= WIPE[0] && zig.frame <= WIPE[1];
            if (ok(d.length === 0 || (inWipe && d.length <= 2), `exact: frame ${zig.frame} (k 0) differs from REF on rows ${d.slice(0, 8)}`)) exact++;
        }
        if (on === 150 && zig.frame > on + 12) {
            part1++;
            newPics += lastZ !== null && !same(z, lastZ);
            refRepeats += lastR !== null && same(r, lastR);
        }
        lastZ = z; lastR = r;
    }
    lastZ = lastR = null;
    zig.demo.key(K_Z);
    while (zig.demo.c64Zig()) { ref.step(); zig.step(); if (zig.frame > off + 6) { ok(false, `back: ZIG still on at ${zig.frame}`); break; } }
    if (BROKE) ref.step();
    let back = 0;
    for (let i = 0; i < 90; i++) {
        if (i > 0) { ref.step(); zig.step(); }
        back += ok(same(zig.picture(), ref.picture()), `back: frame ${zig.frame} after Z off differs from REF`) ? 1 : 0;
        if (back !== i + 1) break;
    }
    console.log(`  trip ${on}-${off}: back ${back}/90 frames REF's`);
}
console.log(`  exact: ${exact} k=0 ZIG frames identical to REF (C64 frames)`);
console.log(`  60 Hz: part 1, ZIG new picture on ${newPics}/${part1 - 1} frames, REF repeated ${refRepeats}`);
ok(newPics >= part1 - 2 && refRepeats >= Math.floor(part1 / 6) - 1, "60 Hz: ZIG does not move every frame (or REF does)");
ok(exact > 50, `exact: only ${exact} k=0 frames checked`);

// exitCode, never process.exit() (node 24 deadlocks at exit: apps/mod_sfx_check.mjs).
if (BROKE) {
    console.log(backFails ? `c64_1988_zig: PASS (--break caught: ${backFails} back failures)` : "c64_1988_zig: FAILED -- --break not caught");
    process.exitCode = backFails ? 0 : 1;
} else {
    console.log(failed ? `c64_1988_zig: FAILED (${failed})` : "c64_1988_zig: all pass");
    process.exitCode = failed ? 1 : 0;
}
