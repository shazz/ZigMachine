// A plane's copper list (HW 1.9.0, machine/copper.zig), read back for a harness: what palette
// entry `e` holds on raster line `line` once the list has been applied. A cart that plays its
// rasters from zg.copper no longer installs an HBL handler, so a harness that dispatched the
// handler and read the palette now reads the list -- the words the machine itself applies.
const OFF_VRAM = 0x1100, REG_FB_COPPER = 0x78; // machine/sdk/memmap.zig

/** The list's records in raster order: [{ line, pal: Map(entry -> rgba), flick }]; null if none. */
export function copperRecords(memory, vb, plane) {
    const v = new DataView(memory.buffer, vb).getUint16(REG_FB_COPPER + 2 * plane, true);
    if (v === 0) return null;
    const word = (off) => new DataView(memory.buffer, vb).getUint32(off, true);
    const recs = [];
    let at = OFF_VRAM + 16 * v, last = -1;
    for (;;) {
        const head = word(at);
        if (head >>> 28 !== 0xF) throw new Error(`copper list: no HEAD at 0x${at.toString(16)}`);
        const line = (head >>> 19) & 0x1FF, n = head & 0x3FF;
        if (line === 511) return recs;
        if (line <= last) throw new Error(`copper list: line ${line} after ${last} (the list stops)`);
        const rec = { line, pal: new Map(), flick: false };
        for (let i = 0; i < n; i++) {
            const w = word(at + 4 + 4 * i), op = w >>> 28, first = (w >>> 20) & 0xFF, k = (w >>> 12) & 0xFF;
            if (op === 0) continue;
            else if (op === 3) rec.flick = true;
            else if (op === 2) continue; // HSCROLL: not a palette word
            else if (op === 1) { for (let j = 0; j < k; j++) rec.pal.set(first + j, word(at + 8 + 4 * (i + j))); i += k; }
            else if (op === 4) { const src = word(at + 8 + 4 * i); for (let j = 0; j < k; j++) rec.pal.set(first + j, word(src + 4 * j)); i += 1; }
            else throw new Error(`copper list: op ${op} on line ${line} (the list stops)`);
        }
        recs.push(rec);
        last = line;
        at += 4 + 4 * n;
    }
}

/** Entry `e` on raster line `line`: the latest record at or above it that writes `e`, else `base`. */
export function copperColour(recs, line, e, base) {
    let c = base;
    for (const r of recs) { if (r.line > line) break; if (r.pal.has(e)) c = r.pal.get(e); }
    return c;
}
