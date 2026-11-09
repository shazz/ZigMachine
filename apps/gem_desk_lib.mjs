// What GEM's desk-mode harnesses share (gem_desk_check.mjs, gem_desk_flip_check.mjs): the
// machine's registers, Set Preferences' buttons, and the desk picture the page shows.
export const W = 640, H = 480, HALF = W * (H / 2) * 4;
export const REG_RES = 0x00, REG_FB_BASE = 0x44, OFF_PAL = 0x100, OFF_VRAM = 0x1100, VRAM_BYTES = 1 << 20;
export const RES_DESK = 3;

// Where Set Preferences' buttons are on a screen (rom/gem/desktop/prefs.zig: a 256x152 box,
// centred; resButton i at hspread over the 3-cell content width, row 13; OK on row 16).
export function prefsAt(sw, sh) {
    const dx = (sw - 256) >> 1, dy = (sh - 152) >> 1, x0 = dx + 24, cw = 256 - 48;
    const gap3 = Math.trunc((cw - 3 * 56) / 4), gap2 = Math.trunc((cw - 2 * 64) / 3);
    const res = (i) => [x0 + gap3 * (i + 1) + 56 * i + 28, dy + 13 * 8 + 6];
    return { low: res(0), medium: res(1), desk: res(2), ok: [x0 + gap2 + 32, dy + 16 * 8 + 7], dx, dy };
}

export const dv = (gem) => new DataView(gem.memory.buffer, gem.machine.hwVideoBase());
export const res = (gem) => dv(gem).getUint8(REG_RES);
export const fbBase = (gem) => dv(gem).getUint32(REG_FB_BASE, true);
export const settle = (gem, n = 4) => { for (let i = 0; i < n; i++) gem.frame(); };

// Options > Set Preferences > `which` > OK, through `click(x, y)` in the desktop's coordinates.
export function pickRes(gem, click, which, sw, sh) {
    click(180, 8); // Options (the host's x 360 in low res)
    click(210, 15); // Set Preferences...
    settle(gem);
    const p = prefsAt(sw, sh);
    click(...p[which]);
    click(...p.ok);
    settle(gem, 6);
    return p;
}

// The desk picture (hwRenderDesk's two 640x240 halves), RGBA.
export function deskPicture(gem) {
    const out = new Uint8Array(2 * HALF);
    for (let half = 0; half < 2; half++) {
        gem.machine.hwRenderDesk(half);
        out.set(new Uint8Array(gem.memory.buffer, gem.machine.hwPhysicalPtr(), HALF), half * HALF);
    }
    return out;
}

// Plane 0's bytes at a region offset (a desk buffer: W x H indices).
export const bufferAt = (gem, off) => new Uint8Array(gem.memory.buffer, gem.machine.hwVideoBase() + off, W * H);
