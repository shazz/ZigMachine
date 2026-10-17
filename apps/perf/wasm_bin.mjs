// Minimal WebAssembly binary reader/writer for the perf tools (frame_cost, wasm_lint).
// WHY hand-rolled: the tools need byte offsets of every instruction and must splice
// counters into code bodies; a 150-line reader beats a new dependency (no wabt/binaryen
// on the box) and keeps the gate free of npm installs.

export class Reader {
    constructor(buf, pos = 0) { this.buf = buf; this.pos = pos; }
    u8() { return this.buf[this.pos++]; }
    u32() {
        let r = 0, shift = 0, b;
        do { b = this.buf[this.pos++]; r += (b & 0x7f) * 2 ** shift; shift += 7; } while (b & 0x80);
        return r;
    }
    s32() {
        let r = 0, shift = 0, b;
        do { b = this.buf[this.pos++]; r |= (b & 0x7f) << shift; shift += 7; } while (b & 0x80 && shift < 35);
        if (shift < 32 && (b & 0x40)) r |= -1 << shift;
        return r;
    }
    s64() { // value not needed by the tools: skip it, return the raw bytes' start
        const at = this.pos;
        while (this.buf[this.pos++] & 0x80);
        return at;
    }
    bytes(n) { const b = this.buf.subarray(this.pos, this.pos + n); this.pos += n; return b; }
    name() { return new TextDecoder().decode(this.bytes(this.u32())); }
}

export function encU32(n) {
    const out = [];
    do { let b = n & 0x7f; n = Math.floor(n / 128); if (n) b |= 0x80; out.push(b); } while (n);
    return out;
}

export function encS32(n) {
    const out = [];
    for (;;) {
        const b = n & 0x7f; n >>= 7;
        if ((n === 0 && !(b & 0x40)) || (n === -1 && (b & 0x40))) { out.push(b); return out; }
        out.push(b | 0x80);
    }
}

export const encName = (s) => { const b = [...new TextEncoder().encode(s)]; return [...encU32(b.length), ...b]; };
export const section = (id, payload) => [id, ...encU32(payload.length), ...payload];

const VALTYPE = { 0x7f: "i32", 0x7e: "i64", 0x7d: "f32", 0x7c: "f64", 0x7b: "v128", 0x70: "funcref", 0x6f: "externref" };

function readLimits(r) { const f = r.u8(); const min = r.u32(); const max = f & 1 ? r.u32() : null; return { min, max }; }

function readImports(r, m) {
    for (let n = r.u32(); n--;) {
        const module = r.name(), name = r.name(), kind = r.u8();
        const imp = { module, name, kind };
        if (kind === 0) { imp.type = r.u32(); m.funcTypes.push(imp.type); m.numImportedFuncs++; }
        else if (kind === 1) { r.u8(); readLimits(r); }
        else if (kind === 2) { readLimits(r); m.numMemories++; }
        else if (kind === 3) { imp.valtype = VALTYPE[r.u8()]; r.u8(); m.globalTypes.push(imp.valtype); }
        m.imports.push(imp);
    }
}

function readTypes(r, m) {
    for (let n = r.u32(); n--;) {
        if (r.u8() !== 0x60) throw new Error("wasm_bin: non-func type");
        const params = [], results = [];
        for (let k = r.u32(); k--;) params.push(VALTYPE[r.u8()]);
        for (let k = r.u32(); k--;) results.push(VALTYPE[r.u8()]);
        m.types.push({ params, results });
    }
}

function readGlobals(r, m) {
    for (let n = r.u32(); n--;) {
        m.globalTypes.push(VALTYPE[r.u8()]); r.u8();
        while (r.u8() !== 0x0b); // init expr: consts only in practice, skip to its end
    }
}

function readNames(r, end, m) {
    while (r.pos < end) {
        const id = r.u8(), size = r.u32(), stop = r.pos + size;
        if (id === 1) for (let n = r.u32(); n--;) { const i = r.u32(); m.names.set(i, r.name()); }
        r.pos = stop;
    }
}

function readCode(r, m) {
    for (let n = r.u32(); n--;) {
        const size = r.u32();
        m.bodies.push({ start: r.pos, end: r.pos + size });
        r.pos += size;
    }
}

// Parse the sections the tools need. Offsets are into `buf` (the whole file).
export function parseModule(buf) {
    const r = new Reader(buf, 8);
    const m = {
        buf, sections: [], types: [], imports: [], funcTypes: [], numImportedFuncs: 0, numMemories: 0,
        globalTypes: [], exports: [], names: new Map(), bodies: [],
    };
    while (r.pos < buf.length) {
        const start = r.pos, id = r.u8(), size = r.u32(), payload = r.pos, end = payload + size;
        let custom = null;
        if (id === 0) { custom = r.name(); if (custom === "name") readNames(r, end, m); }
        else if (id === 1) readTypes(r, m);
        else if (id === 2) readImports(r, m);
        else if (id === 3) for (let n = r.u32(); n--;) m.funcTypes.push(r.u32());
        else if (id === 5) m.numMemories += r.u32();
        else if (id === 6) readGlobals(r, m);
        else if (id === 7) for (let n = r.u32(); n--;) m.exports.push({ name: r.name(), kind: r.u8(), index: r.u32() });
        else if (id === 10) readCode(r, m);
        m.sections.push({ id, start, payload, end, custom });
        r.pos = end;
    }
    return m;
}

export const funcName = (m, i) => m.names.get(i) ?? `f${i}`;
export const funcType = (m, i) => m.types[m.funcTypes[i]];
