// The XM test song (apps/xm_check.mjs): generated here, not ripped, so there is
// no licence to carry. 8 channels, 2 patterns of 16 rows, 2 instruments: an 8-bit
// sawtooth with a forward loop, a volume envelope and fadeout, and a 16-bit sine
// with a ping-pong loop. Its cells cover the effects the player implements (arpeggio,
// portamento, vibrato, volume slide, tone portamento, retrigger, sample offset,
// fine slides, note cut, note delay, pattern delay, speed, jump and break), and
// packed as well as unpacked cells, so the reader's both forms are exercised.
// Delta-coded PCM, as FastTracker 2 writes it.

const u16 = (v) => [v & 255, (v >> 8) & 255];
const u32 = (v) => [v & 255, (v >>> 8) & 255, (v >>> 16) & 255, (v >>> 24) & 255];
const pad = (bytes, n) => bytes.concat(new Array(Math.max(0, n - bytes.length)).fill(0));
const text = (s, n) => pad([...s].map((c) => c.charCodeAt(0)), n);
const name = (s) => text(s, 22);

/** A 16-bit sample is two bytes a frame: its value's delta from the frame before. */
export function deltas8(values) {
    let prev = 0;
    return values.map((x) => {
        const d = (x - prev) & 255;
        prev = x;
        return d;
    });
}
export function deltas16(values) {
    let prev = 0;
    return values.flatMap((x) => {
        const d = (x - prev) & 0xffff;
        prev = x;
        return [d & 255, d >> 8];
    });
}

const SAW = Array.from({ length: 64 }, (_, i) => ((i * 4) % 128) - 64);
const SINE = Array.from({ length: 128 }, (_, i) => Math.round(8000 * Math.sin((2 * Math.PI * i) / 64)));

/** The 263-byte instrument header with its one sample: a volume envelope and fadeout. */
function instrument8() {
    const h = new Array(263).fill(0);
    const put = (o, bytes) => bytes.forEach((b, k) => (h[o + k] = b));
    put(0, u32(263));
    put(4, name("saw"));
    put(27, u16(1));
    put(29, u32(40));
    // volume envelope: (0,0) (4,64) (40,64) (64,0), sustain on point 2, on + sustain
    put(129, [0, 0, 0, 0, 4, 0, 64, 0, 40, 0, 64, 0, 64, 0, 0, 0]);
    put(225, [4, 0, 2, 0, 0, 0, 0, 0, 3, 0, 0, 0, 0, 0]);
    put(239, u16(2000));
    return h;
}

function instrument16() {
    const h = new Array(263).fill(0);
    const put = (o, bytes) => bytes.forEach((b, k) => (h[o + k] = b));
    put(0, u32(263));
    put(4, name("sine"));
    put(27, u16(1));
    put(29, u32(40));
    return h;
}

/** A 40-byte sample header. `type`: loop kind | 0x10 for 16-bit. */
function sampleHeader(bytes, loopStart, loopLen, type, volume) {
    return pad([...u32(bytes), ...u32(loopStart), ...u32(loopLen), volume, 0, type, 0, 0, 0, ...name("s")], 40);
}

/** One cell: packed (flag byte, then only the fields present) when any is 0. */
function cell([note = 0, inst = 0, vol = 0, eff = 0, param = 0]) {
    const f = [note, inst, vol, eff, param];
    if (f.every((x) => x !== 0)) return f;
    const flag = 0x80 | (note ? 1 : 0) | (inst ? 2 : 0) | (vol ? 4 : 0) | (eff ? 8 : 0) | (param ? 16 : 0);
    return [flag, ...f.filter((x) => x !== 0)];
}

/** A pattern from `rows`: each row a list of 8 cells, [] = empty. */
function pattern(rows) {
    const packed = rows.flatMap((row) => Array.from({ length: 8 }, (_, ch) => cell(row[ch] ?? [])).flat());
    return [...u32(9), 0, ...u16(rows.length), ...u16(packed.length), ...packed];
}

const EMPTY = Array.from({ length: 16 }, () => []);
function withCells(list) {
    const rows = EMPTY.map(() => []);
    for (const [row, ch, c] of list) rows[row][ch] = c;
    return rows;
}

const PAT0 = withCells([
    [0, 0, [49, 1, 0, 0, 0]], [4, 0, [52, 1, 0, 0, 0]], [8, 0, [97]], [12, 0, [55, 1, 0, 0x0f, 0x03]],
    [0, 1, [49, 2]],
    [0, 2, [49, 1, 0, 1, 0x08]], [4, 2, [0, 0, 0, 2, 0x04]],
    [0, 3, [53, 2]], [2, 3, [0, 0, 0, 4, 0x46]],
    [0, 4, [49, 1, 0x40]], [4, 4, [0, 0, 0, 0xa, 0x04]],
    [0, 5, [45, 2]], [6, 5, [57, 0, 0, 3, 0x10]],
    [2, 6, [49, 1, 0, 0xe, 0x93]],
    [0, 7, [61, 2]], [8, 7, [61, 2, 0, 9, 0x02]],
    [15, 0, [0, 0, 0, 0x0b, 0x01]],
]);
const PAT1 = withCells([
    [0, 0, [49, 1, 0x30]], [3, 0, [0, 0, 0, 0xe, 0x13]], [5, 0, [0, 0, 0, 0xd, 0x02]],
    [0, 1, [49, 2, 0, 0xe, 0xd2]],
    [4, 2, [49, 1, 0, 0xe, 0xc2]],
    [1, 3, [40, 2, 0, 0xe, 0xa2]],
    [8, 4, [0, 0, 0, 0xe, 0xe1]],
]);

/** The song: the header, the orders, the patterns, the instruments and their PCM. */
export function testSong() {
    const sawBytes = deltas8(SAW);
    const sineBytes = deltas16(SINE);
    const headerSize = 276; // the 20 fixed bytes after the size, and the 256-byte order table
    const orders = [0, 1, 0, 1];
    const head = [...'Extended Module: '].map((c) => c.charCodeAt(0));
    const h = pad([...head, ...text('ZigTest', 20), 0x1a, ...text('xm_song.mjs', 20), ...u16(0x0104), ...u32(headerSize),
        ...u16(orders.length), ...u16(0), ...u16(8), ...u16(2), ...u16(2), ...u16(1), ...u16(6), ...u16(125)], 80);
    const table = pad(orders, 256);
    const body = [...pattern(PAT0), ...pattern(PAT1)];
    const inst1 = [...instrument8(), ...sampleHeader(sawBytes.length, 0, sawBytes.length, 1, 48), ...sawBytes];
    const inst2 = [...instrument16(), ...sampleHeader(sineBytes.length, 32, 192, 0x10 | 2, 64), ...sineBytes];
    return Uint8Array.from([...h, ...table, ...body, ...inst1, ...inst2]);
}
