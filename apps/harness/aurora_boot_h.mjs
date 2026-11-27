// AURORA BOOT H (cart 169, apps/zig/scenes/aurora_boot_h.zig): what aurora_boot_check.mjs --h adds to cart 161's
// checks. H puts the picture over the whole 400x280 raster: plane 0 is TRUECOLOR_FULL (FB_MODE 6, borders open with
// nothing to earn), plane 1 is OVERSCAN (FB_MODE 4) whose borders a copper FLICK on every line opens, and the
// aurora's masks are read off the disk (AURORA.MSK). So the harness mounts the cart's disk, checks the modes and
// the list, that the borders show the sky and the stars that fly through them, and adds three mutants.
import { readFile } from "node:fs/promises";
import { makeDrive } from "./scene_hash_disk.mjs";

const REG_FB_MODE = 0x54, REG_FB_COPPER = 0x78, OFF_VRAM = 0x1100, FB_MODE_TC_FULL = 6, FB_MODE_OVERSCAN = 4;
const W = 400, H = 280, BX = 40, BY = 40; // the raster and its borders (the 320x200 window starts at 40, 40)
export const DISK = "site/carts/demo-aurora_boot_h.zmd";
export const MUTANTS = ["window", "shut", "baddisk"];

const inBorder = (x, y) => x < BX || x >= W - BX || y < BY || y >= H - BY;

// The disk image, with one byte in the middle of AURORA.MSK flipped for the "baddisk" mutant. The FAT is where
// libs/zig/disk.zig looks: v2 (magic at $400) count $4F4, entries $800; v1 count $2E4, entries $300.
async function diskBytes(brk) {
    const buf = new Uint8Array(await readFile(DISK));
    if (brk !== "baddisk") return buf;
    const v2 = new TextDecoder().decode(buf.subarray(0x400, 0x406)) === "ZMDISK";
    const dv = new DataView(buf.buffer), n = dv.getUint16(v2 ? 0x4F4 : 0x2E4, true), fat = v2 ? 0x800 : 0x300;
    for (let i = 0; i < n; i++) {
        const e = fat + 32 * i, name = new TextDecoder().decode(buf.subarray(e, e + 16)).replace(/\0.*$/, "");
        if (name === "AURORA.MSK") { buf[dv.getUint32(e + 16, true) + (dv.getUint32(e + 20, true) >> 1)] ^= 0x5A; return buf; }
    }
    throw new Error(`${DISK}: no AURORA.MSK`);
}

export async function drive(memory, brk) {
    return makeDrive(memory, { buf: await diskBytes(brk) });
}

// After the cart's frame, before the planes are rendered: the mutants that change what the machine is told.
export function mutate(dv, video, brk) {
    if (brk === "window") dv.setUint8(video + REG_FB_MODE, 5); // the TC plane back in the 320x200 window
    if (brk === "shut") dv.setUint16(video + REG_FB_COPPER + 2, 0); // plane 1 without its FLICK list
}

// What one frame shows of H: the two modes, plane 1's list (FLICK on every line), the lit border pixels of the
// composed raster, and plane 1's own rendered alpha (to see the stars in the borders). The raster is doubled
// horizontally (hwPhysWidth 800 for 400 pixels): a pixel (x, y) is raster pixel (x * sx, y).
export function look(m, dv, comp, p1) {
    const v = m.video, modes = [dv.getUint8(v + REG_FB_MODE), dv.getUint8(v + REG_FB_MODE + 1)];
    const rw = m.machine.hwPhysWidth(), sx = rw / W;
    let border = 0;
    for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) if (inBorder(x, y) && (comp[y * rw + x * sx] & 0xFFFFFF)) border++;
    return { modes, flicks: flicks(dv, v), border, p1, rw, sx };
}

function flicks(dv, v) {
    const c = dv.getUint16(v + REG_FB_COPPER + 2, true);
    if (!c) return 0;
    let at = v + OFF_VRAM + 16 * c, n = 0;
    for (let line = 0; line < 600; line++) {
        const head = dv.getUint32(at, true);
        if (head >>> 28 !== 0xF || ((head >>> 19) & 511) === 511) break;
        const body = head & 0x7FFFF;
        for (let k = 1; k <= body; k++) n += dv.getUint32(at + 4 * k, true) >>> 28 === 3;
        at += 4 * (body + 1);
    }
    return n;
}

export function checks(shots, ref, need) {
    const s = shots[10].h;
    need(s.modes[0] === FB_MODE_TC_FULL && s.modes[1] === FB_MODE_OVERSCAN, `modes: planes ${s.modes} (6 TRUECOLOR_FULL, 4 OVERSCAN expected)`);
    need(s.flicks === H, `borders: plane 1's copper list flickers ${s.flicks} lines (all ${H} expected)`);
    const full = (W - 2 * BX) * BY * 2 + 2 * BX * H; // every border pixel
    need(shots[90].h.border > 0.95 * full, `borders: ${shots[90].h.border} of ${full} border pixels lit at frame 90 (the sky is full screen)`);
    let out = 0, shown = 0;
    for (const [rec, xy] of Object.entries(ref.stars_xy)) {
        const { p1, rw, sx } = shots[2 * +rec].h;
        for (const [x, y] of xy) if (x >= 0 && x < W && y >= 0 && y < H && inBorder(x, y)) { out++; shown += p1[y * rw + x * sx] !== 0; }
    }
    need(out > 0 && shown === out, `borders: ${shown} of ${out} baked stars in the borders are on plane 1's raster`);
}
