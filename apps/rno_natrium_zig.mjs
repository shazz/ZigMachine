// RNO / NATRIUM's ZIG mode (Z, apps/zig/scenes/rno_natrium/zig_*.zig), checked from outside.
// Two carts run in lockstep, one VBL a frame: REF never sees Z, ZIG gets Z at $6F0 and
// keeps it through every part. Every check is an independent re-derivation
// (apps/rno_natrium_zig_model.mjs: the assets and fixtrig, not the cart's numbers):
//   planes   ZIG mode shows plane 1 alone (overscan, borders open: the side and top
//            border pixels reach the raster in their palette colour), plane 0 is off
//   tunnel   every plane-1 pixel is the MAP's texel at the original's pan and scroll,
//            and the map itself is the original's formula (atan2, 1024 / r) within a texel
//   wobble   every pixel is the face at the original's two displacements (3x3 cells)
//   env      off the object, the girl picture; on it, >= 8 of the 13 true-colour
//            levels (no dither) and a new picture EVERY VBL (the original: every 3)
//   roto     every pixel is the skin at the original's matrix, over the whole window
//   classic  the parts with no ZIG version show the original's frame at (40, 40)
//   back     Z off (mid-cube at $D30, and at $1C30): the next 48 frames are REF's,
//            pixel for pixel; Z on again at $D60 needs no new memory
//   ops      CHISEL ops a frame <= 3; Escape leaves (the cart now owns the keys)
//   node apps/rno_natrium_zig.mjs [outdir] [--break]
//     --break: REF runs one VBL ahead during the round trips, so "back" must fail (exit 0)
import { mkdir, writeFile } from "node:fs/promises";
import { boot } from "./rno_natrium_boot.mjs";
import * as Z from "./rno_natrium_zig_model.mjs";

const BROKE = process.argv.includes("--break");
const OUT = process.argv.slice(2).find((a) => !a.startsWith("--")) || "/tmp/rno_natrium";
const K_Z = 122, K_ESC = 0xE012, PART = ["classic", "tunnel", "wobble", "env", "roto"];
let failed = 0, backFails = 0;
const ok = (c, m) => { console.log(`  ${c ? "ok  " : "FAIL"} ${m}`); if (!c) { failed++; if (m.startsWith("back")) backFails++; } };

class Cart {
    constructor(b) { Object.assign(this, b); this.vbls = 0; }
    step() {
        this.machine.hwClear();
        this.demo.frame(20);
        this.machine.hwRenderPlane(this.demo.isPlaneEnabled(0) ? 0 : 1);
        this.vbls++;
    }
    /** The raster as 0xRRGGBB, 400 x 280 (un-doubled). */
    raster() {
        const p = new Uint8Array(this.memory.buffer, this.machine.hwPhysicalPtr(), 800 * 280 * 4), o = new Uint32Array(Z.W * Z.H);
        for (let i = 0; i < o.length; i++) { const k = 8 * i; o[i] = p[k] << 16 | p[k + 1] << 8 | p[k + 2]; }
        return o;
    }
    window() { const r = this.raster(), o = []; for (let y = 40; y < 240; y++) o.push(...r.subarray(y * 400 + 40, y * 400 + 360)); return o; }
    plane(p) { return new Uint8Array(this.memory.buffer, this.demo.natPlanePtr(p), Z.W * Z.H).slice(); }
    u16(ptr, n) { return new Uint16Array(this.memory.buffer, ptr, n).slice(); }
}

const ref = new Cart(await boot()), zig = new Cart(await boot());
const both = (to) => { while (ref.vbls < to) { ref.step(); zig.step(); } };
const same = (a, b) => a.length === b.length && a.every((v, i) => v === b[i]);

/** Run to `to` with ZIG on; `check(idx, t)` on every `every`-th frame; returns frames checked. */
function zigRun(to, part, every, check) {
    let n = 0;
    while (ref.vbls < to) {
        ref.step(); zig.step();
        if (zig.demo.natZig() !== 1 || zig.demo.isPlaneEnabled(0) || !zig.demo.isPlaneEnabled(1)) return ok(false, `planes at $${zig.vbls.toString(16)}`), n;
        if (zig.demo.natZigOps() > 3) return ok(false, `${zig.demo.natZigOps()} CHISEL ops at $${zig.vbls.toString(16)}`), n;
        if (check && zig.vbls % every === 0 && PART[zig.demo.natZigPart()] === part) { check(zig.plane(1), zig.demo.natZigTime()); n++; }
    }
    return n;
}

/** Every window pixel against a model (-1 = not the effect's pixel); the misses. */
function against(idx, f) {
    let bad = 0, first = "";
    for (let y = 0; y < Z.H; y++) for (let x = 0; x < Z.W; x++) {
        const want = f(x, y);
        if (want >= 0 && idx[y * Z.W + x] !== want) { if (!bad++) first = `(${x},${y}) ${idx[y * Z.W + x]} != ${want}`; }
    }
    return [bad, first];
}

/** Z off for 48 frames from `at`: REF's frame, every one. */
function roundTrip(at) {
    both(at);
    zig.demo.key(K_Z);
    if (BROKE) ref.step();
    let diff = 0;
    for (let i = 0; i < 48; i++) { ref.step(); zig.step(); if (!same(ref.window(), zig.window())) diff++; }
    ok(diff === 0 && zig.demo.natZig() === 0 && zig.demo.isPlaneEnabled(0), `back from ZIG at $${at.toString(16)}: 48 frames are the original's, pixel for pixel (${diff} differ)`);
    if (BROKE) zig.step(); // in step again for what follows
}

await mkdir(OUT, { recursive: true });
async function shot(name) {
    const r = zig.raster(), b = Buffer.alloc(Z.W * Z.H * 3);
    r.forEach((c, i) => { b[3 * i] = c >> 16; b[3 * i + 1] = (c >> 8) & 255; b[3 * i + 2] = c & 255; });
    await writeFile(`${OUT}/zig-${name}.ppm`, Buffer.concat([Buffer.from("P6\n400 280\n255\n"), b]));
}

console.log("rno_natrium ZIG mode");
both(0x6F0);
zig.demo.key(K_Z);
const ram0 = zig.machine.hwRamUsed();
await (await import("./rno_natrium_zig_parts.mjs")).checkParts({ ref, zig, both, zigRun, against, roundTrip, ok, shot, same, ram0, K_Z });
zig.demo.key(K_ESC);
zig.step();
ok(zig.demo.pollCartRequest() === -1, "Escape hands the screen back to the menu (pollCartRequest -1)");
ok(zig.machine.hwRamAllocFailures() === 0, "no zg.mem allocation refused");
// exitCode, never process.exit() (node 24 deadlocks at exit).
if (BROKE) {
    const caught = backFails === 2 && failed === 2;
    console.log(caught ? "rno_natrium ZIG: PASS (--break caught: a VBL apart is not the original's frame)" : `rno_natrium ZIG: FAILED -- --break not caught (${backFails}/${failed})`);
    process.exitCode = caught ? 0 : 1;
} else {
    console.log(failed ? `rno_natrium ZIG: FAILED (${failed})` : "rno_natrium ZIG: PASS");
    process.exitCode = failed ? 1 : 0;
}
