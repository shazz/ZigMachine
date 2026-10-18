// The waste detectors' planted patterns (waste.mjs, waste_report.mjs): carts with a REAL
// plane 0 in VRAM (fixture.mjs `plane`), each pattern against a twin that does the same
// amount of work but only modifies what changes. frame() locals: 1-4 i32 (4 = a frame
// counter where `counter` runs first); boot() locals: 0-1 i32.
import { I, loop, PLANE, BUF2, HW_BLIT } from "./fixture.mjs";

const VB = 0x300000;
const counter = [...I.i32(0), ...I.i32(0), ...I.load(BUF2 + 64), ...I.i32(1), ...I.add, ...I.tee(4), ...I.store(BUF2 + 64)];
const word = (i) => [...I.get(i), ...I.i32(2), ...I.shl];            // byte offset of word i
const frameWord = [...I.get(4), ...I.i32(0x01010101), ...I.mul];     // this frame's colour, 4 pixels
const page = (n, v) => loop(1, n, [...word(1), ...v, ...I.store(PLANE)]);
const fill = (n) => [...I.i32(PLANE), ...I.i32(0), ...I.i32(n), ...I.fill];
const P = { plane: true };

// a FILL of w x h at x on plane 0
const blit = (w, h, x) => [
    ...I.i32(VB + 0x80), ...I.i32(2), ...I.store8(0), ...I.i32(VB + 0x82), ...I.i32(0), ...I.store8(0),
    ...I.i32(VB + 0x87), ...I.i32(0), ...I.store8(0), ...I.i32(VB + 0x84), ...I.i32(7), ...I.store8(0),
    ...I.i32(VB + 0xa0), ...I.i32(0x1100), ...I.store(0), ...I.i32(VB + 0xa4), ...I.i32(320), ...I.store16(0),
    ...I.i32(VB + 0xa8), ...I.i32(w), ...I.store16(0), ...I.i32(VB + 0xaa), ...I.i32(h), ...I.store16(0),
    ...I.i32(VB + 0xac), ...x, ...I.store16(0), ...I.i32(VB + 0xae), ...I.i32(0), ...I.store16(0), ...I.call(HW_BLIT),
];
const BAND = 50 * 320, BAND_LEN = 20 * 320;

export const WASTE_CASES = [
    { pattern: "redundant_store", waste: true, opts: P, // the same page redrawn every frame, vs a page that changes
        with: page(16000, I.i32(0x01020304)), without: [...counter, ...page(16000, frameWord)] },
    { pattern: "clear_then_redraw", waste: true, opts: P, // cleared, then all of it drawn back as it was
        with: [...fill(64000), ...page(16000, I.i32(0x01010101))], without: [...counter, ...page(100, frameWord)] },
    { pattern: "static_plane", waste: true, // drawn once at boot, never touched again
        opts: { ...P, boot: loop(1, 16000, [...word(1), ...I.i32(0x05060708), ...I.store(PLANE)]) },
        with: [], without: [...counter, ...page(100, frameWord)] },
    { pattern: "lines_changed", metric: (r) => r.waste.lines, opts: P, // one row a frame vs every row
        withIs: (n) => n <= 3, withoutIs: (n) => n >= 150,
        with: [...counter, ...page(80, frameWord)], without: [...counter, ...page(16000, frameWord)] },
    { pattern: "tiny_blits", waste: true, opts: P, // 200 4x4 fills vs one 320x200 fill
        with: loop(1, 200, blit(4, 4, [...I.get(1), ...I.i32(31), ...I.and, ...I.i32(8), ...I.mul])),
        without: blit(320, 200, I.i32(0)) },
    { pattern: "scroll_band", waste: true, // a 20-row band moved 1 px left by the CPU, vs redrawn with new content
        opts: { ...P, boot: loop(1, BAND_LEN, [...I.get(1), ...I.get(1), ...I.i32(7), ...I.mul, ...I.store8(PLANE + BAND)]) },
        with: loop(1, BAND_LEN, [...I.get(1), ...I.get(1), ...I.load8(PLANE + BAND + 1), ...I.store8(PLANE + BAND)]),
        without: [...counter, ...loop(1, BAND_LEN, [...I.get(1), ...I.get(1), ...I.i32(13), ...I.mul, ...I.get(4),
            ...I.i32(29), ...I.mul, ...I.add, ...I.store8(PLANE + BAND)])] },
].map((c) => ({ dynamicOnly: true, ...c }));
