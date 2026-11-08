// NATRIUM frames as PNGs, original or ZIG mode (Z pressed at $A0), one cart, one VBL a frame.
//   node prototypes/rno_natrium_re/zig_fullscreen/shots.mjs <outdir> <prefix> <0|1> <counter hex>...
// Run from the repository root (the boot reads docs/*.wasm). Each PNG is the 400x280 raster.
import { boot } from "../../../apps/rno_natrium_boot.mjs";
import { writePng } from "../../../apps/scene_png.mjs";

const [out, prefix, zig, ...at] = process.argv.slice(2);
const c = await boot();
let vbls = 0;
const step = () => {
    c.machine.hwClear();
    c.demo.frame(20);
    c.machine.hwRenderPlane(c.demo.isPlaneEnabled(0) ? 0 : 1);
    vbls++;
};
if (zig === "1") { while (vbls < 0xA0) step(); c.demo.key(122); }
for (const h of at) {
    const to = parseInt(h, 16);
    while (vbls < to) step();
    const p = new Uint8Array(c.memory.buffer, c.machine.hwPhysicalPtr(), 800 * 280 * 4), rgba = Buffer.alloc(400 * 280 * 4);
    for (let i = 0; i < 400 * 280; i++) { for (let k = 0; k < 3; k++) rgba[4 * i + k] = p[8 * i + k]; rgba[4 * i + 3] = 255; }
    writePng(`${out}/${prefix}-${h}.png`, rgba, 400, 280);
}
