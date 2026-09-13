// The blitter's SOURCE contract (HW 1.4.0), driven straight through the register
// block of the sealed machine, with no cart and no ZigOS in the way.
//
// Before 1.4.0 every channel BASE was an offset from HW_VIDEO_BASE, so a cart's
// own assets (which live below it, in the cart window) were unreachable. CON2.SRC_ABS
// makes A/B absolute addresses, checked per blit against the readable windows. This
// proves both halves: what must work (plane offsets unchanged, cart RAM, ROM
// window, video region, keyed copies) and what must be refused without writing a
// single byte (machine RAM, a rect straddling two windows, the gap below the ROM,
// a stride x height large enough to wrap).
//
// Usage: node apps/blitter_check.mjs        (exit 1 on any failure)
import { readFile } from "node:fs/promises";

const PAGES = 112;               // memmap.SHARED_PAGES
const VIDEO = 0x300000;          // HW_VIDEO_BASE
const CART_BASE = 0x100000;      // CART_RAM_BASE
const CART_TOP = VIDEO;          // CART_RAM_TOP
const REGION_BYTES = 1948768;    // OFF_PFB + PFB_BYTES
const ROM_BASE = 0x500000;       // ROM_RAM_BASE
const OFF_BLIT = 0x80;
const P0 = 0x1100;               // plane 0 framebuffer (OFF_VRAM)
const P1 = 0x1100 + 64000;       // plane 1
const STRIDE = 320;
const CANARY = 0x5a;

const memory = new WebAssembly.Memory({ initial: PAGES, maximum: PAGES });
const machine = (await WebAssembly.instantiate(
    await readFile(process.env.MACHINE || "docs/machine-video.wasm"),
    { env: { memory, hblDispatch: () => {} } })).instance.exports;
machine.hwInit();

const u8 = () => new Uint8Array(memory.buffer);
const dv = () => new DataView(memory.buffer);
const R = (o) => VIDEO + OFF_BLIT + o;

function blit({ con2 = 0, base, stride, w, h, x, y, key }) {
    const m = u8(), d = dv();
    m[R(0x07)] = con2;                       // CON2
    d.setUint32(R(0x20), P0, true);          // D_BASE (video offset)
    d.setUint16(R(0x24), STRIDE, true);      // D_STRIDE
    d.setUint32(R(0x10), base, true);        // B_BASE
    d.setUint16(R(0x14), stride, true);      // B_STRIDE
    m[R(0x02)] = 0x02 | (key === undefined ? 0 : 0x08); // CON: USEB (+ KEY_EN)
    m[R(0x01)] = 0xcc;                       // MINTERM: D = B
    m[R(0x06)] = key ?? 0;                   // COLOR_KEY
    d.setInt16(R(0x2c), x, true);
    d.setInt16(R(0x2e), y, true);
    d.setUint16(R(0x28), w, true);
    d.setUint16(R(0x2a), h, true);
    m[R(0x00)] = 1;                          // COMMAND: BLIT
    machine.hwBlit();
    return d.getUint32(R(0x60), true);       // CYCLES
}

const plane0 = () => u8().subarray(VIDEO + P0, VIDEO + P0 + 64000);
const resetPlane0 = () => plane0().fill(CANARY);
const at = (x, y) => plane0()[y * STRIDE + x];

// A w x h test image whose bytes are 1 + (index % 250), optionally with holes.
function image(addr, w, h, stride = w, holes = false) {
    const m = u8();
    for (let j = 0; j < h; j++)
        for (let i = 0; i < w; i++)
            m[addr + j * stride + i] = holes && (i + j) % 3 === 0 ? 0 : 1 + ((j * w + i) % 250);
}
function matches(addr, w, h, stride, x, y, key) {
    const m = u8();
    for (let j = 0; j < h; j++)
        for (let i = 0; i < w; i++) {
            const s = m[addr + j * stride + i];
            const want = key !== undefined && s === key ? CANARY : s;
            if (at(x + i, y + j) !== want) return `pixel (${x + i},${y + j}) is ${at(x + i, y + j)}, wants ${want}`;
        }
    return null;
}
const untouched = () => plane0().every((v) => v === CANARY) ? null : "plane 0 was written";

let failed = 0;
function check(name, fn) {
    resetPlane0();
    let why;
    try { why = fn(); } catch (e) { why = `threw ${e}`; }
    console.log(`${why ? "FAIL" : "ok  "}  ${name}${why ? ": " + why : ""}`);
    if (why) failed++;
}

check("relative: plane 1 -> plane 0, as before 1.4.0", () => {
    image(VIDEO + P1, 16, 8, STRIDE);
    const cyc = blit({ base: P1, stride: STRIDE, w: 16, h: 8, x: 10, y: 10 });
    return matches(VIDEO + P1, 16, 8, STRIDE, 10, 10) ?? (cyc === 128 ? null : `CYCLES ${cyc}`);
});
check("SRC_ABS: an image in cart RAM", () => {
    image(0x200000, 24, 5, 24);
    const cyc = blit({ con2: 1, base: 0x200000, stride: 24, w: 24, h: 5, x: 40, y: 3 });
    return matches(0x200000, 24, 5, 24, 40, 3) ?? (cyc === 120 ? null : `CYCLES ${cyc}`);
});
check("SRC_ABS: keyed cookie-cut from cart RAM", () => {
    image(0x210000, 12, 12, 12, true);
    blit({ con2: 1, base: 0x210000, stride: 12, w: 12, h: 12, x: 100, y: 50, key: 0 });
    return matches(0x210000, 12, 12, 12, 100, 50, 0);
});
check("SRC_ABS: last bytes of the cart window", () => {
    const base = CART_TOP - 10 * 4; // 10x4, ends exactly at CART_TOP
    image(base, 10, 4, 10);
    blit({ con2: 1, base, stride: 10, w: 10, h: 4, x: 0, y: 0 });
    return matches(base, 10, 4, 10, 0, 0);
});
check("SRC_ABS: the ROM window", () => {
    image(0x600000, 8, 8, 8);
    blit({ con2: 1, base: 0x600000, stride: 8, w: 8, h: 8, x: 300, y: 190 });
    return matches(0x600000, 8, 8, 8, 300, 190);
});
check("SRC_ABS: the video region by absolute address", () => {
    image(VIDEO + P1, 16, 4, STRIDE);
    blit({ con2: 1, base: VIDEO + P1, stride: STRIDE, w: 16, h: 4, x: 5, y: 150 });
    return matches(VIDEO + P1, 16, 4, STRIDE, 5, 150);
});
check("SRC_ABS: clipped at the destination edge still reads only in-window", () => {
    image(0x220000, 32, 32, 32);
    blit({ con2: 1, base: 0x220000, stride: 32, w: 32, h: 32, x: 300, y: -10 });
    return at(300, 0) === u8()[0x220000 + 10 * 32] ? null : "clipped copy wrong";
});

const refusals = [
    ["machine RAM below the cart window", { base: 0x1000, stride: 16, w: 16, h: 16 }],
    ["address 0", { base: 0, stride: 16, w: 16, h: 16 }],
    ["rect straddling cart RAM into the video region", { base: CART_TOP - 8, stride: 16, w: 16, h: 1 }],
    ["rect running off the cart window downward", { base: CART_TOP - 100, stride: 64, w: 16, h: 4 }],
    ["the gap between the video region and the ROM", { base: VIDEO + REGION_BYTES + 16, stride: 16, w: 16, h: 16 }],
    ["past the ROM window (end of memory)", { base: 0x700000 - 8, stride: 16, w: 16, h: 1 }],
    ["stride x height large enough to wrap 32 bits", { base: 0x200000, stride: 65535, w: 16, h: 65535 }],
];
for (const [name, r] of refusals) {
    check(`SRC_ABS refuses ${name}`, () => {
        const cyc = blit({ con2: 1, x: 0, y: 0, ...r });
        return untouched() ?? (cyc === 0 ? null : `CYCLES ${cyc}`);
    });
}

// Relative mode and the destination were unchecked before 1.4.0: a bad BASE read
// or wrote past the end of memory and trapped the machine, and D_BASE = 0x200000
// wrote straight into the ROM's RAM. Both are now refused without a trap.
const romGuard = () => u8().subarray(ROM_BASE, ROM_BASE + 4096);
check("relative source past the video region is refused, no trap", () => {
    const cyc = blit({ base: 0x3ff000, stride: 320, w: 64, h: 64, x: 0, y: 0 });
    return untouched() ?? (cyc === 0 ? null : `CYCLES ${cyc}`);
});
check("relative source rect running off the region's end is refused", () => {
    const cyc = blit({ base: REGION_BYTES - 100, stride: 320, w: 64, h: 2, x: 0, y: 0 });
    return untouched() ?? (cyc === 0 ? null : `CYCLES ${cyc}`);
});
function destBlit(cmd, dBase, dStride, coords) {
    const m = u8(), d = dv();
    m[R(0x07)] = 0;
    d.setUint32(R(0x20), dBase, true);
    d.setUint16(R(0x24), dStride, true);
    m[R(0x02)] = 0;                          // CON: no channels, no clip
    m[R(0x01)] = 0xcc;
    m[R(0x04)] = 0x77;                       // COLOR
    const [x0, y0, x1, y1, x2, y2, w, h] = coords;
    d.setInt16(R(0x2c), x0, true); d.setInt16(R(0x2e), y0, true);
    d.setInt16(R(0x30), x1, true); d.setInt16(R(0x32), y1, true);
    d.setInt16(R(0x34), x2, true); d.setInt16(R(0x36), y2, true);
    d.setUint16(R(0x28), w, true); d.setUint16(R(0x2a), h, true);
    m[R(0x00)] = cmd;
    machine.hwBlit();
    return d.getUint32(R(0x60), true);
}
for (const [name, cmd] of [["FILL", 2], ["LINE", 3], ["TRIANGLE", 4]]) {
    check(`${name} with D_BASE in the ROM's RAM is refused`, () => {
        romGuard().fill(CANARY);
        const cyc = destBlit(cmd, ROM_BASE - VIDEO, 320, [0, 0, 50, 50, 0, 50, 50, 50]);
        return romGuard().every((v) => v === CANARY) ? (cyc === 0 ? null : `CYCLES ${cyc}`) : "ROM RAM was written";
    });
}
check("FILL whose box runs off the end of memory is refused, no trap", () => {
    const cyc = destBlit(2, 0x3fff00, 320, [0, 0, 0, 0, 0, 0, 320, 200]);
    return cyc === 0 ? null : `CYCLES ${cyc}`;
});
check("a huge-stride view that only writes its first rows still works", () => {
    // blitter_demo's DELAY ring: plane 1 viewed with a 62400-byte stride
    plane0().fill(CANARY);
    const cyc = destBlit(2, P0, 62400, [4, 0, 0, 0, 0, 0, 8, 1]);
    return at(4, 0) === 0x77 && at(11, 0) === 0x77 && cyc === 8 ? null : `FILL wrote ${at(4, 0)}, CYCLES ${cyc}`;
});

check("hwInit clears CON2, so pre-1.4.0 carts keep relative sources", () => {
    u8()[R(0x07)] = 1;
    machine.hwInit();
    return u8()[R(0x07)] === 0 ? null : "CON2 survived hwInit";
});
check("the machine reports HW 1.4.0", () =>
    machine.hwVersion() === 0x00010400 ? null : `hwVersion 0x${machine.hwVersion().toString(16)}`);

console.log(failed ? `blitter_check: ${failed} FAILED` : "blitter_check: all pass ✅");
process.exit(failed ? 1 : 0);
